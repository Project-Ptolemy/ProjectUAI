package dev.projectuai.relay.engine

import dev.projectuai.relay.protocol.JobState
import dev.projectuai.relay.protocol.JobView
import dev.projectuai.relay.protocol.SubmitRequest
import dev.projectuai.relay.protocol.ActivitySnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.net.UnknownHostException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.io.IOException
import okhttp3.Call
import okhttp3.Dns
import okhttp3.EventListener
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody

class JobEngineTest {
    private lateinit var upstream: MockWebServer
    private lateinit var scope: CoroutineScope
    private val instance = "inst-test"

    @Before
    fun setUp() {
        upstream = MockWebServer()
        upstream.start()
        scope = CoroutineScope(Dispatchers.IO)
    }

    @After
    fun tearDown() {
        scope.cancel()
        upstream.shutdown()
    }

    private fun engine(limits: JobEngine.Limits = JobEngine.Limits()) = JobEngine(instance, scope, limits = limits)

    private fun submitRequest(
        id: String = "inference_abcdef12",
        url: String? = null,
        timeout: Int = 180,
        headers: Map<String, String> = mapOf("Authorization" to "Bearer key"),
        instanceValue: String = instance,
        body: String = "{\"model\":\"m\"}",
    ) = SubmitRequest(
        id = id,
        instance = instanceValue,
        url = url ?: upstream.url("/v1/chat/completions").toString(),
        headers = headers,
        body = body,
        timeout = timeout,
    )

    private fun waitFor(engine: JobEngine, id: String, waitMs: Long = 5000): JobView? {
        val deadline = System.currentTimeMillis() + waitMs
        while (System.currentTimeMillis() < deadline) {
            val view = engine.poll(id)
            if (view != null && view.state != JobState.RUNNING) return view
            Thread.sleep(20)
        }
        return engine.poll(id)
    }

    @Test
    fun `completes a forwarded request with filtered headers`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{\"answer\":1}"))
        val engine = engine()
        assertTrue(engine.submit(submitRequest()) is JobEngine.Submission.Accepted)
        val view = waitFor(engine, "inference_abcdef12")!!
        assertEquals(JobState.COMPLETED, view.state)
        assertEquals(200, view.status)
        assertEquals("{\"answer\":1}", view.body)
        val recorded = upstream.takeRequest()
        assertEquals("/v1/chat/completions", recorded.path)
        assertEquals("identity", recorded.getHeader("accept-encoding"))
        assertEquals("Bearer key", recorded.getHeader("authorization"))
    }

    @Test
    fun `is idempotent for the same id and fingerprint`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        val engine = engine()
        engine.submit(submitRequest())
        waitFor(engine, "inference_abcdef12")
        assertTrue(engine.submit(submitRequest()) is JobEngine.Submission.Accepted)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `rejects the same id with a different request`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        val engine = engine()
        engine.submit(submitRequest())
        waitFor(engine, "inference_abcdef12")
        val conflict = engine.submit(submitRequest(body = "{\"changed\":true}"))
        assertTrue(conflict is JobEngine.Submission.Rejected)
        assertEquals(409, (conflict as JobEngine.Submission.Rejected).status)
    }

    @Test
    fun `rejects a stale instance without touching the provider`() {
        val engine = engine()
        val result = engine.submit(submitRequest(instanceValue = "other"))
        assertTrue(result is JobEngine.Submission.Rejected)
        assertEquals(409, (result as JobEngine.Submission.Rejected).status)
        assertEquals(0, upstream.requestCount)
    }

    @Test
    fun `rejects an unsafe url`() {
        val result = engine().submit(submitRequest(url = "http://169.254.169.254/latest"))
        assertTrue(result is JobEngine.Submission.Rejected)
        assertEquals(400, (result as JobEngine.Submission.Rejected).status)
    }

    @Test
    fun `answers at capacity with 503`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}").setBodyDelay(2, TimeUnit.SECONDS))
        val engine = engine(JobEngine.Limits(maxActive = 1))
        assertTrue(engine.submit(submitRequest(id = "inference_first000")) is JobEngine.Submission.Accepted)
        val second = engine.submit(submitRequest(id = "inference_second00"))
        assertTrue(second is JobEngine.Submission.Rejected)
        assertEquals(503, (second as JobEngine.Submission.Rejected).status)
    }

    @Test
    fun `cancels a running job`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}").setBodyDelay(2, TimeUnit.SECONDS))
        val engine = engine()
        engine.submit(submitRequest())
        Thread.sleep(100)
        assertTrue(engine.cancel("inference_abcdef12"))
        assertEquals(JobState.CANCELLED, waitFor(engine, "inference_abcdef12")!!.state)
    }

    @Test
    fun `tombstones an evicted job as expired`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        val engine = engine(JobEngine.Limits(retentionMs = 0))
        engine.submit(submitRequest())
        waitFor(engine, "inference_abcdef12")
        Thread.sleep(20)
        engine.sweep()
        assertEquals(JobState.EXPIRED, engine.poll("inference_abcdef12")?.state)
    }

    @Test
    fun `unknown id reads as null for a 404`() {
        assertNull(engine().poll("inference_missing"))
    }

    @Test
    fun `carries an upstream error status without resubmitting`() {
        upstream.enqueue(MockResponse().setResponseCode(500).setBody("boom"))
        val engine = engine()
        engine.submit(submitRequest())
        val view = waitFor(engine, "inference_abcdef12")!!
        assertEquals(JobState.COMPLETED, view.state)
        assertEquals(500, view.status)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `unlimited reasoning survives ten seconds of silence while explicit deadlines still apply`() {
        upstream.enqueue(MockResponse().setBody("long answer").setBodyDelay(12, TimeUnit.SECONDS))
        upstream.enqueue(MockResponse().setBody("too late").setBodyDelay(12, TimeUnit.SECONDS))
        val engine = engine()
        engine.submit(submitRequest(id = "inference_unlimited", timeout = 0))
        assertTrue(upstream.takeRequest(2, TimeUnit.SECONDS) != null)
        engine.submit(submitRequest(id = "inference_finite00", timeout = 10))
        assertTrue(upstream.takeRequest(2, TimeUnit.SECONDS) != null)
        val bounded = waitFor(engine, "inference_finite00", 15_000)!!
        assertEquals(JobState.FAILED, bounded.state)
        assertEquals("timeout", bounded.errorCode)
        val unlimited = waitFor(engine, "inference_unlimited", 5000)!!
        assertEquals(JobState.COMPLETED, unlimited.state)
        assertEquals("long answer", unlimited.body)
        assertEquals(2, upstream.requestCount)
    }

    @Test
    fun `notifies on acceptance and counts terminal states without duplicate submission`() {
        upstream.enqueue(MockResponse().setBody("answer").setBodyDelay(150, TimeUnit.MILLISECONDS))
        val observations = CopyOnWriteArrayList<ActivitySnapshot>()
        lateinit var engine: JobEngine
        engine = JobEngine(instance, scope, onChanged = { observations.add(engine.activity()) })
        engine.submit(submitRequest())
        assertTrue(observations.any { it.activeJobs == 1 && it.acceptedJobs == 1 && it.completedJobs == 0 })
        waitFor(engine, "inference_abcdef12")
        engine.submit(submitRequest())
        val activity = engine.activity()
        assertEquals(1, activity.acceptedJobs)
        assertEquals(1, activity.completedJobs)
        assertEquals(0, activity.activeJobs)
        assertEquals(6L, activity.recent.single().receivedBytes)
        assertEquals(upstream.url("/").host, activity.recent.single().provider)
    }

    @Test
    fun `transport disconnect is terminal and never repeated`() {
        upstream.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST))
        upstream.enqueue(MockResponse().setBody("must not retry"))
        val engine = engine()
        engine.submit(submitRequest())
        val failed = waitFor(engine, "inference_abcdef12")!!
        assertEquals(JobState.FAILED, failed.state)
        assertEquals("transport", failed.errorCode)
        assertEquals(1, upstream.requestCount)
        assertEquals(1, engine.activity().failedJobs)
    }

    @Test
    fun `an unreachable first provider address can fall back before sending the post`() {
        val unavailable = InetAddress.getByName("127.0.0.2")
        val available = InetAddress.getByName(upstream.hostName)
        assertFalse(unavailable == available)
        val attempts = CopyOnWriteArrayList<InetAddress>()
        fun client() = JobEngine.providerClient().newBuilder()
            .proxy(Proxy.NO_PROXY)
            .connectTimeout(250, TimeUnit.MILLISECONDS)
            .dns(object : Dns {
                override fun lookup(hostname: String) = listOf(unavailable, available)
            })
            .eventListener(object : EventListener() {
                override fun connectStart(call: Call, address: InetSocketAddress, proxy: Proxy) {
                    attempts.add(address.address)
                }
            }).build()
        val request = submitRequest(url = upstream.url("/v1/chat/completions").newBuilder()
            .host("provider.test").build().toString())
        upstream.enqueue(MockResponse().setBody("reachable address"))

        // Reproduce the previous configuration: one failed address masks a
        // reachable provider, even though no HTTP request was dispatched.
        val previous = JobEngine(instance, scope, client().newBuilder().retryOnConnectionFailure(false).build())
        previous.submit(request)
        assertEquals(JobState.FAILED, waitFor(previous, request.id)!!.state)
        assertEquals(listOf(unavailable), attempts.toList())
        assertEquals(0, upstream.requestCount)

        attempts.clear()
        val fixed = JobEngine(instance, scope, client())
        fixed.submit(request)
        val view = waitFor(fixed, request.id)!!
        assertEquals(JobState.COMPLETED, view.state)
        assertEquals("reachable address", view.body)
        assertEquals(listOf(unavailable, available), attempts.toList())
        assertEquals(1, upstream.requestCount)
        val received = upstream.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("POST", received.method)
        assertEquals(request.body, received.body.readUtf8())
        assertEquals("Bearer key", received.getHeader("Authorization"))
    }

    @Test
    fun `retryable provider statuses never automatically replay the post`() {
        val status = AtomicInteger(408)
        upstream.dispatcher = object : okhttp3.mockwebserver.Dispatcher() {
            override fun dispatch(request: okhttp3.mockwebserver.RecordedRequest) =
                MockResponse().setResponseCode(status.get()).setHeader("Retry-After", "0").setBody("refused")
        }
        val engine = engine()
        for (code in listOf(408, 503)) {
            status.set(code)
            val request = submitRequest(id = "inference_status_$code")
            val before = upstream.requestCount
            engine.submit(request)
            val view = waitFor(engine, request.id)!!
            assertEquals(JobState.COMPLETED, view.state)
            assertEquals(code, view.status)
            assertEquals("refused", view.body)
            assertEquals(before + 1, upstream.requestCount)
        }
    }

    @Test
    fun `a partial request body is terminal and never repeated`() {
        upstream.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_DURING_REQUEST_BODY))
        upstream.enqueue(MockResponse().setBody("must not retry"))
        val engine = engine()
        engine.submit(submitRequest(body = "x".repeat(512 * 1024)))
        val failed = waitFor(engine, "inference_abcdef12")!!
        assertEquals(JobState.FAILED, failed.state)
        assertEquals("transport", failed.errorCode)
        assertEquals(1, upstream.requestCount)
        assertEquals(1, engine.activity().failedJobs)
    }

    @Test
    fun `redirect does not replay the provider post`() {
        upstream.enqueue(MockResponse().setResponseCode(307).setHeader("Location", upstream.url("/replay")))
        upstream.enqueue(MockResponse().setBody("must not replay"))
        val engine = engine()
        engine.submit(submitRequest())
        assertEquals(307, waitFor(engine, "inference_abcdef12")!!.status)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `diagnostic failures categorize without leaking raw errors`() {
        val client = JobEngine.providerClient().newBuilder().addInterceptor {
            throw UnknownHostException("private-provider-key-and-query")
        }.build()
        val engine = JobEngine(instance, scope, client)
        engine.submit(submitRequest())
        val failed = waitFor(engine, "inference_abcdef12")!!
        assertEquals("dns", failed.errorCode)
        assertFalse(failed.error.orEmpty().contains("private-provider"))
        assertEquals("dns", engine.activity().recent.single().errorCode)
    }

    @Test
    fun `cancelled unlimited request settles once and releases active state`() {
        upstream.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val engine = engine()
        engine.submit(submitRequest(timeout = 0))
        assertTrue(upstream.takeRequest(2, TimeUnit.SECONDS) != null)
        engine.cancel("inference_abcdef12")
        engine.cancel("inference_abcdef12")
        assertEquals(JobState.CANCELLED, engine.poll("inference_abcdef12")!!.state)
        assertEquals(0, engine.activity().activeJobs)
        assertEquals(1, engine.activity().cancelledJobs)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `closing cancels active work and prevents later admission`() {
        upstream.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val engine = engine()
        engine.submit(submitRequest(timeout = 0))
        assertTrue(upstream.takeRequest(2, TimeUnit.SECONDS) != null)
        engine.close()
        val rejected = engine.submit(submitRequest(id = "inference_afterstop", timeout = 0))
        assertTrue(rejected is JobEngine.Submission.Rejected)
        assertEquals(JobState.CANCELLED, engine.poll("inference_abcdef12")!!.state)
        assertEquals(0, engine.activity().activeJobs)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `owner loss cancels a silent unlimited call without incoming traffic or wall clock dependence`() {
        upstream.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val ownerTime = AtomicLong(0)
        val wallTime = AtomicLong(1_000_000)
        val nativeCancelled = CountDownLatch(1)
        val client = JobEngine.providerClient().newBuilder().eventListener(object : EventListener() {
            override fun callFailed(call: Call, ioe: IOException) {
                if (call.isCanceled()) nativeCancelled.countDown()
            }
        }).build()
        val engine = JobEngine(instance, scope, client, clock = { wallTime.get() }, ownerClock = { ownerTime.get() })
        engine.submit(submitRequest(timeout = 0))
        assertTrue(upstream.takeRequest(2, TimeUnit.SECONDS) != null)
        ownerTime.set(JobEngine.OWNER_LEASE_MS - 1)
        wallTime.set(Long.MAX_VALUE / 2)
        engine.sweep()
        assertEquals(1, engine.activeCount)
        assertEquals(1, engine.activity().activeJobs)
        ownerTime.set(JobEngine.OWNER_LEASE_MS)
        engine.sweep()
        assertTrue(nativeCancelled.await(2, TimeUnit.SECONDS))
        val settled = engine.poll("inference_abcdef12")!!
        assertEquals(JobState.CANCELLED, settled.state)
        assertEquals("client_disconnected", settled.errorCode)
        assertEquals(0, engine.activeCount)
        assertEquals(1, engine.activity().cancelledJobs)
        val duplicate = engine.submit(submitRequest(timeout = 0)) as JobEngine.Submission.Accepted
        assertEquals(JobState.CANCELLED, duplicate.view.state)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `only the exact job poll or matching submission renews ownership beyond total deadlines`() {
        repeat(2) { upstream.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE)) }
        val ownerTime = AtomicLong(0)
        val engine = JobEngine(instance, scope, ownerClock = { ownerTime.get() })
        val first = submitRequest(id = "inference_owner_one", timeout = 0)
        val second = submitRequest(id = "inference_owner_two", timeout = 0)
        engine.submit(first)
        engine.submit(second)
        repeat(2) { assertTrue(upstream.takeRequest(2, TimeUnit.SECONDS) != null) }
        ownerTime.set(119_000)
        assertEquals(JobState.RUNNING, engine.poll(first.id)!!.state)
        assertTrue(engine.submit(second) is JobEngine.Submission.Accepted)
        ownerTime.set(238_000)
        assertEquals(JobState.RUNNING, engine.poll(first.id)!!.state)
        assertTrue(engine.submit(second.copy(body = "different")) is JobEngine.Submission.Rejected)
        assertNull(engine.poll("inference_unknown"))
        engine.activity()
        ownerTime.set(239_000)
        engine.sweep()
        assertEquals(JobState.CANCELLED, engine.poll(second.id)!!.state)
        assertEquals("client_disconnected", engine.poll(second.id)!!.errorCode)
        for (time in listOf(357_000L, 476_000L)) {
            ownerTime.set(time)
            assertEquals(JobState.RUNNING, engine.poll(first.id)!!.state)
        }
        assertEquals(1, engine.activeCount)
        assertEquals(2, upstream.requestCount)
        engine.close()
    }

    @Test
    fun `update reservation rejects new provider work until released`() {
        val engine = engine()
        assertTrue(engine.pauseForUpdate())
        assertTrue(engine.pauseForUpdate())
        assertNull(engine.poll("inference_unknown"))
        assertFalse(engine.cancel("inference_unknown"))
        val rejected = engine.submit(submitRequest()) as JobEngine.Submission.Rejected
        assertEquals(503, rejected.status)
        assertEquals(0, engine.total)
        assertEquals(0, upstream.requestCount)

        engine.resumeAfterUpdate()
        engine.resumeAfterUpdate()
        upstream.enqueue(MockResponse().setBody("ready again"))
        assertTrue(engine.submit(submitRequest()) is JobEngine.Submission.Accepted)
        assertEquals("ready again", waitFor(engine, "inference_abcdef12")!!.body)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `update waits for active jobs and cancellation receipts without cancelling work`() {
        upstream.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val wallTime = AtomicLong(1_000)
        val engine = JobEngine(instance, scope, clock = { wallTime.get() })
        engine.submit(submitRequest(timeout = 0))
        assertTrue(upstream.takeRequest(2, TimeUnit.SECONDS) != null)
        assertFalse(engine.pauseForUpdate())
        assertEquals(JobState.RUNNING, engine.poll("inference_abcdef12")!!.state)
        assertTrue(engine.cancel("inference_abcdef12"))
        assertEquals(JobState.CANCELLED, engine.poll("inference_abcdef12")!!.state)
        assertFalse(engine.pauseForUpdate())
        wallTime.addAndGet(engine.limits.retentionMs)
        assertFalse(engine.pauseForUpdate())
        wallTime.incrementAndGet()
        assertTrue(engine.pauseForUpdate())
        assertEquals(JobState.EXPIRED, engine.poll("inference_abcdef12")!!.state)
        assertFalse(engine.cancel("inference_abcdef12"))
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `empty completion receipts delay an update and closing never resumes admission`() {
        upstream.enqueue(MockResponse().setResponseCode(204))
        val wallTime = AtomicLong(1_000)
        val engine = JobEngine(instance, scope, clock = { wallTime.get() })
        engine.submit(submitRequest())
        assertEquals(JobState.COMPLETED, waitFor(engine, "inference_abcdef12")!!.state)
        assertEquals(0L, engine.retained)
        assertFalse(engine.pauseForUpdate())
        wallTime.addAndGet(engine.limits.retentionMs + 1)
        assertTrue(engine.pauseForUpdate())
        engine.close()
        engine.resumeAfterUpdate()
        assertFalse(engine.pauseForUpdate())
        assertEquals(503, (engine.submit(submitRequest(id = "inference_after_update")) as JobEngine.Submission.Rejected).status)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `update reservation and concurrent admission have one winner`() {
        val workers = Executors.newFixedThreadPool(2)
        try {
            repeat(32) {
                val dispatches = AtomicInteger(0)
                val client = JobEngine.providerClient().newBuilder().addInterceptor { chain ->
                    dispatches.incrementAndGet()
                    Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                        .code(200).message("OK").body("answer".toResponseBody()).build()
                }.build()
                val engine = JobEngine(instance, scope, client)
                val start = CountDownLatch(1)
                val ready = CountDownLatch(2)
                val pause = workers.submit(Callable {
                    ready.countDown()
                    start.await()
                    engine.pauseForUpdate()
                })
                val submission = workers.submit(Callable {
                    ready.countDown()
                    start.await()
                    engine.submit(submitRequest())
                })
                assertTrue(ready.await(2, TimeUnit.SECONDS))
                start.countDown()
                if (pause.get(2, TimeUnit.SECONDS)) {
                    assertEquals(503, (submission.get(2, TimeUnit.SECONDS) as JobEngine.Submission.Rejected).status)
                    assertEquals(0, engine.total)
                    assertEquals(0, dispatches.get())
                } else {
                    assertTrue(submission.get(2, TimeUnit.SECONDS) is JobEngine.Submission.Accepted)
                    assertEquals(JobState.COMPLETED, waitFor(engine, "inference_abcdef12")!!.state)
                    assertEquals(1, dispatches.get())
                }
                engine.close()
            }
        } finally { workers.shutdownNow() }
    }
}
