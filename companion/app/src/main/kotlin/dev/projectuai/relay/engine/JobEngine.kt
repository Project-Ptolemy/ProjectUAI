package dev.projectuai.relay.engine

import dev.projectuai.relay.protocol.JobState
import dev.projectuai.relay.protocol.JobView
import dev.projectuai.relay.protocol.JobActivity
import dev.projectuai.relay.protocol.ActivitySnapshot
import dev.projectuai.relay.protocol.SubmitRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import okhttp3.Call
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.Buffer
import okio.BufferedSink
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException

/**
 * Owns the upstream connection so every executor-visible call is a few milliseconds.
 * Idempotent by submit id, cap-bounded for a phone, and terminal-by-state exactly as
 * src/net/relay.lua expects.
 */
class JobEngine(
    private val instance: String,
    private val scope: CoroutineScope,
    private val client: OkHttpClient = providerClient(),
    val limits: Limits = Limits(),
    private val clock: () -> Long = System::currentTimeMillis,
    private val onChanged: () -> Unit = {},
    private val ownerClock: () -> Long = { System.nanoTime() / 1_000_000L },
    private val kilo: KiloRoute? = null,
) {
    fun kiloCapability() = kilo?.capability() ?: dev.projectuai.relay.protocol.KiloCapability()
    data class Limits(
        val bodyBytes: Long = 8L * 1024 * 1024,
        val maxJobs: Int = 200,
        val maxActive: Int = 4,
        val retainedBytes: Long = 32L * 1024 * 1024,
        val retentionMs: Long = 60_000,
        val tombstones: Int = 20_000,
    )

    private class Job(val id: String, val provider: String, val startedAt: Long, var lastOwnerAt: Long) {
        @Volatile var state = JobState.RUNNING
        @Volatile var status = 0
        @Volatile var headers: Map<String, String> = emptyMap()
        @Volatile var body: String? = null
        @Volatile var error: String? = null
        @Volatile var errorCode: String? = null
        @Volatile var stage = "connecting"
        @Volatile var receivedBytes = 0L
        @Volatile var lastProgressAt = 0L
        @Volatile var finishedAt = 0L
        @Volatile var retained = 0L
        @Volatile var call: Call? = null
        @Volatile var cancelled = false
    }

    sealed class Submission {
        data class Accepted(val view: JobView) : Submission()
        data class Rejected(val status: Int, val message: String) : Submission()
    }

    private val lock = Any()
    private val jobs = LinkedHashMap<String, Job>()
    private val knownFingerprints = HashMap<String, String>()
    private val tombstones = ArrayDeque<String>()
    private val tombstoneSet = HashSet<String>()
    private var retainedBytes = 0L
    @Volatile private var activeJobs = 0
    @Volatile private var totalJobs = 0
    private var completedJobs = 0
    private var failedJobs = 0
    private var cancelledJobs = 0
    private var closed = false
    private var updatePaused = false
    private val recent = LinkedHashMap<String, JobActivity>()

    val activeCount: Int get() = activeJobs
    val retained: Long get() = retainedBytes
    val total: Int get() = totalJobs

    fun activity(): ActivitySnapshot = synchronized(lock) {
        ActivitySnapshot(activeJobs, totalJobs, completedJobs, failedJobs, cancelledJobs,
            recent.values.toList().asReversed().map { item -> jobs[item.id]?.let(::activityOf) ?: item })
    }

    private fun activityOf(job: Job) = JobActivity(job.id, job.provider, job.state, job.stage,
        job.startedAt, job.finishedAt, job.receivedBytes, job.status, job.errorCode)

    private fun notifyChanged() { runCatching(onChanged) }

    fun submit(request: SubmitRequest): Submission {
        sweep()
        if (!RequestRules.ID.matches(request.id)) return Submission.Rejected(400, "invalid inference id")
        if (request.instance != instance) {
            return Submission.Rejected(409, "The relay restarted; submit a new request")
        }
        RequestRules.validateUrl(request.url)?.let { return Submission.Rejected(400, it) }
        if (request.body.toByteArray(Charsets.UTF_8).size.toLong() > limits.bodyBytes) {
            return Submission.Rejected(413, "request body exceeds the relay limit")
        }

        val headers = RequestRules.filterRequestHeaders(request.headers)
        val timeout = RequestRules.clampTimeout(request.timeout)
        val fingerprint = Fingerprint.of(request.url, headers, request.body, request.sessionId)

        var job: Job? = null
        synchronized(lock) {
            if (closed) return Submission.Rejected(503, "relay stopped; no request was submitted")
            if (updatePaused) return Submission.Rejected(503, "relay update installation is open; no request was submitted")
            val known = knownFingerprints[request.id]
            if (known != null) {
                if (known != fingerprint) return Submission.Rejected(409, "inference id reused with a different request")
                val existing = jobs[request.id]
                if (existing != null) {
                    if (existing.state == JobState.RUNNING) existing.lastOwnerAt = ownerClock()
                    return Submission.Accepted(view(existing))
                }
                return Submission.Rejected(410, "expired; do not resubmit")
            }
            if (tombstoneSet.contains(request.id)) return Submission.Rejected(410, "expired; do not resubmit")
            if (activeJobs >= limits.maxActive) return Submission.Rejected(503, "at capacity; retry shortly")
            pruneLocked()
            if (jobs.size >= limits.maxJobs) return Submission.Rejected(503, "at capacity; retry shortly")
            val created = Job(request.id, request.url.toHttpUrl().host, clock(), ownerClock())
            job = created
            jobs[request.id] = created
            recent[request.id] = activityOf(created)
            while (recent.size > 12) recent.remove(recent.keys.first())
            knownFingerprints[request.id] = fingerprint
            activeJobs += 1
            totalJobs += 1
        }
        val started = job ?: return Submission.Rejected(503, "at capacity; retry shortly")
        // Wake-lock and UI observers must see acceptance before the provider can
        // block. Previously they only learned about a job after it finished.
        notifyChanged()
        scope.launch { execute(started, request, headers, timeout) }
        return Submission.Accepted(view(started))
    }

    fun poll(id: String): JobView? {
        sweep()
        synchronized(lock) {
            jobs[id]?.let {
                // RelayServer authenticates this exact job poll before calling us.
                // Status, hello and another job's traffic cannot keep it alive.
                if (it.state == JobState.RUNNING) it.lastOwnerAt = ownerClock()
                return view(it)
            }
            if (tombstoneSet.contains(id)) return JobView(id, JobState.EXPIRED, error = "expired; do not resubmit")
            return null
        }
    }

    fun cancel(id: String): Boolean {
        sweep()
        val job = synchronized(lock) { jobs[id] } ?: return false
        job.cancelled = true
        finish(job, JobState.CANCELLED, error = "cancelled", errorCode = "cancelled")
        job.call?.cancel()
        return true
    }

    fun cancelAll() {
        val running = synchronized(lock) { jobs.values.filter { it.state == JobState.RUNNING } }
        running.forEach {
            it.cancelled = true
            finish(it, JobState.CANCELLED, error = "relay stopped", errorCode = "cancelled")
            it.call?.cancel()
        }
    }

    /** Stop admission before cancellation, including accepted jobs not yet dispatched. */
    fun close() {
        synchronized(lock) { closed = true }
        cancelAll()
        kilo?.close()
    }

    /** Reserve an idle engine while Android's update installer is open. */
    fun pauseForUpdate(): Boolean {
        sweep()
        return synchronized(lock) {
            // Receipts can contain an empty body. Their presence, not byte count,
            // protects a result Roblox may still need to collect after completion.
            if (closed || activeJobs != 0 || jobs.isNotEmpty()) false
            else { updatePaused = true; true }
        }
    }

    fun resumeAfterUpdate() {
        synchronized(lock) { if (!closed) updatePaused = false }
    }

    /** Releases abandoned work independently from the provider's total running time. */
    fun sweep() {
        val ownerCutoff = ownerClock() - OWNER_LEASE_MS
        val abandoned = synchronized(lock) {
            jobs.values.filter { it.state == JobState.RUNNING && it.lastOwnerAt <= ownerCutoff }
        }
        abandoned.forEach { job ->
            if (finish(job, JobState.CANCELLED,
                    error = "The Roblox client stopped polling this request for two minutes; the provider connection was cancelled and not repeated.",
                    errorCode = "client_disconnected", ownerCutoff = ownerCutoff)) {
                job.call?.cancel()
            }
        }
        // Completed receipts keep their existing wall-clock retention contract.
        val now = clock()
        val expired = synchronized(lock) {
            jobs.values.filter { it.state != JobState.RUNNING && now - it.finishedAt > limits.retentionMs }.map { it.id }
        }
        if (expired.isEmpty()) return
        synchronized(lock) { expired.forEach { removeLocked(it) } }
        notifyChanged()
    }

    private fun execute(job: Job, request: SubmitRequest, headers: Map<String, String>, timeout: Int) {
        try {
            val builder = Request.Builder().url(request.url)
            headers.forEach { (key, value) -> builder.addHeader(key, value) }
            val mediaType = headers.entries.firstOrNull { it.key.equals("content-type", true) }
                ?.value?.toMediaTypeOrNull() ?: "application/json".toMediaTypeOrNull()
            val requestBody = request.body.toRequestBody(mediaType)
            builder.method("POST", object : RequestBody() {
                override fun contentType() = requestBody.contentType()
                override fun contentLength() = requestBody.contentLength()
                override fun writeTo(sink: BufferedSink) = requestBody.writeTo(sink)
                // Allow another address before dispatch, never an automatic replay
                // after sending. Kilo's complete quota refusal owns its separate call.
                override fun isOneShot() = true
            })
            val prepared = builder.build()
            val response = if (kilo != null && KiloRoute.eligible(prepared, request.body)) {
                kilo.execute(prepared, client, timeout, { job.cancelled }) { call ->
                    job.call = call
                    if (job.cancelled) call.cancel()
                }
            } else {
                val call = client.newCall(prepared)
                job.call = call
                if (job.cancelled) call.cancel()
                call.timeout().timeout(timeout.toLong() * 1000L, TimeUnit.MILLISECONDS)
                call.execute()
            }
            response.use {
                synchronized(lock) { if (job.state == JobState.RUNNING) job.stage = "receiving" }
                notifyChanged()
                val body = response.body
                val buffer = Buffer()
                var over = false
                if (body != null) {
                    val source = body.source()
                    var total = 0L
                    while (true) {
                        val read = source.read(buffer, 64L * 1024L)
                        if (read == -1L) break
                        total += read
                        val changed = synchronized(lock) {
                            if (job.state != JobState.RUNNING) false else {
                                job.receivedBytes = total
                                val now = clock()
                                if (now - job.lastProgressAt >= 1000) { job.lastProgressAt = now; true } else false
                            }
                        }
                        if (changed) notifyChanged()
                        if (total > limits.bodyBytes) { over = true; break }
                    }
                }
                if (over) {
                    finish(job, JobState.FAILED, error = "Provider response exceeds the relay body limit; the request was not repeated.", errorCode = "response_limit")
                } else {
                    val responseHeaders = RequestRules.filterResponseHeaders(
                        response.headers.toMultimap().mapValues { it.value.last() },
                    )
                    finish(job, JobState.COMPLETED, status = response.code, headers = responseHeaders, body = buffer.readUtf8())
                }
            }
        } catch (error: IOException) {
            if (job.cancelled) finish(job, JobState.CANCELLED, error = "cancelled", errorCode = "cancelled")
            else {
                val failure = transportFailure(error)
                finish(job, JobState.FAILED, error = failure.second, errorCode = failure.first)
            }
        } catch (error: RuntimeException) {
            // Exception text may contain URLs or header values. Diagnostics and
            // client errors expose only a bounded category, never that raw text.
            finish(job, JobState.FAILED, error = "The companion could not prepare or read the provider request; it was not repeated.", errorCode = "relay_failure")
        } finally {
            job.call = null
        }
    }

    private fun finish(
        job: Job,
        state: String,
        status: Int = 0,
        headers: Map<String, String> = emptyMap(),
        body: String? = null,
        error: String? = null,
        errorCode: String? = null,
        ownerCutoff: Long? = null,
    ): Boolean {
        synchronized(lock) {
            if (job.state != JobState.RUNNING) return false
            // A poll may have renewed ownership since sweep captured this job.
            if (ownerCutoff != null && job.lastOwnerAt > ownerCutoff) return false
            if (state == JobState.CANCELLED) job.cancelled = true
            job.state = state
            job.status = status
            job.headers = headers
            job.body = body
            job.error = error
            job.errorCode = errorCode
            job.stage = state
            job.finishedAt = clock()
            job.retained = (body?.toByteArray(Charsets.UTF_8)?.size ?: 0).toLong() +
                (error?.toByteArray(Charsets.UTF_8)?.size ?: 0).toLong()
            retainedBytes += job.retained
            activeJobs = (activeJobs - 1).coerceAtLeast(0)
            when (state) {
                JobState.COMPLETED -> completedJobs++
                JobState.FAILED -> failedJobs++
                JobState.CANCELLED -> cancelledJobs++
            }
            pruneLocked()
        }
        notifyChanged()
        return true
    }

    private fun pruneLocked() {
        while (jobs.size >= limits.maxJobs || retainedBytes > limits.retainedBytes) {
            val victim = jobs.values.firstOrNull { it.state != JobState.RUNNING } ?: break
            removeLocked(victim.id)
        }
    }

    private fun removeLocked(id: String) {
        val job = jobs.remove(id) ?: return
        if (recent.containsKey(id)) recent[id] = activityOf(job)
        retainedBytes -= job.retained
        tombstones.addLast(id)
        tombstoneSet.add(id)
        while (tombstoneSet.size > limits.tombstones) {
            val oldest = tombstones.removeFirst()
            tombstoneSet.remove(oldest)
            knownFingerprints.remove(oldest)
        }
    }

    private fun view(job: Job): JobView = synchronized(lock) {
        val completed = job.state == JobState.COMPLETED
        JobView(
            id = job.id,
            state = job.state,
            error = job.error,
            errorCode = job.errorCode,
            status = job.status,
            headers = if (completed) job.headers else emptyMap(),
            body = if (completed) job.body else null,
        )
    }

    companion object {
        const val OWNER_LEASE_MS = 120_000L

        /** Alternate connection routes are safe only with the one-shot inference body above. */
        fun providerClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .writeTimeout(0, TimeUnit.MILLISECONDS)
            .callTimeout(0, TimeUnit.MILLISECONDS)
            .retryOnConnectionFailure(true)
            .followRedirects(false)
            .followSslRedirects(false)
            .build()

        private fun transportFailure(error: IOException): Pair<String, String> = when (error) {
            is UnknownHostException -> "dns" to "The companion could not find the provider host; the request was not repeated."
            is ConnectException -> "connection" to "The companion could not connect to the provider; the request was not repeated."
            is SSLException -> "tls" to "The provider's secure connection failed; the request was not repeated."
            is InterruptedIOException -> "timeout" to "The provider connection or explicit request deadline expired; the request was not repeated."
            else -> "transport" to "The provider connection ended before a complete response arrived; the request was not repeated."
        }
    }
}
