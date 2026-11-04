# UAI Relay (Android companion)

Version **3.7.2** (Android version code 9).

**Settings > Kilo tunnel** enables automatic anonymous Kilo quota recovery.
Native Tor starts only after an explicit quota refusal, with one circuit retry
if the first exit is limited. Stop the relay to change the switch. Cowork in
Roblox and the companion show its status. Shared exits retain their own quotas;
this does not guarantee unlimited access. See [setup and evidence](../docs/KILO_TUNNEL.md).

A foreground service that holds the upstream provider connection while the
Project UAI client submits and polls through short loopback calls. The client
budgets each exchange at most five seconds. Some mobile executors cut long
`request()` calls off before a reasoning turn finishes; polling lets the companion
keep that provider connection open until the answer is ready. It is **not** the
Cowork bridge: there is no web UI, no static
serving, no agent state, no commands. Just the relay contract in
[docs/MOBILE_COMPANION.md](../docs/MOBILE_COMPANION.md) Section 4.

## Requirements

- Android 8.0+ (`minSdk 26`). Sideload only; no Play dependency.
- A mobile executor that exposes `request` / `http_request` / `syn.request` /
  `http.request` / `fluxus.request`, or working `game:HttpGet` and `game:HttpPost`.
  Plain `HttpService` cannot reach loopback plain-HTTP; the executor must perform
  requests locally on the phone.
- The client's `relay.mode` is `auto` by default: the script probes
  `127.0.0.1:8790`, pairs once for a stable token, and relays from then on.
  **Always** requires a relay and reports an unavailable companion instead of
  opening a direct provider request. Auto retains its direct fallback.

## Build

JDK 17 and Android SDK platform **37.1** are required. The checked-in Gradle
wrapper verifies Gradle 9.6.0 by SHA-256; Android Gradle plugin 9.4.1 supplies
Kotlin 2.2.10. Tor Android 0.4.9.14 requires the newer compile API. The app still
supports Android 8+ (`minSdk 26`) and retains `targetSdk 36`.

```powershell
# From companion/
./gradlew :app:assembleDebug          # APK at app/build/outputs/apk/debug/
./gradlew :app:testDebugUnitTest      # JVM contract tests, no device
```

`local.properties` must point at the SDK if `ANDROID_HOME` is unset:

```properties
sdk.dir=C\:\\Android\\Sdk
```

Install with `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

For production signing, automatic updates and release packaging, follow
[Android companion updates](UPDATES.md). The app checks official releases on
startup and every 15 minutes while its process is alive, downloads compatible
updates by default, and asks Android to install only after **Install update** is
tapped. The first transition from a debug-signed APK to the production signing
key requires uninstalling the debug app and pairing again; future updates keep
the same production signer.

## Use

1. Start the app and tap **Start relay**. The notification appears and the relay listens
   on `127.0.0.1:8790` only.
2. In Roblox, run the Project UAI script. The Cowork panel's Relay card shows the
   companion once paired — no token copying.
3. Keep Roblox and the relay running. **Stop relay** in the app is authoritative: the
   watchdogs stay down until you start again.

If Roblox cannot find the companion, first confirm that the app's status reads
**Relay on this phone: Running** and both show the same port. Opening the app alone does not start its
server. On that same phone, open `http://127.0.0.1:8790/api/hello` in a browser
(replace the port if it was changed). A JSON reply containing `"server":"uai-relay"`
and `"protocol":2` confirms that the local listener answered. This public endpoint
contains no pairing token or provider credential and does not count as a paired
Roblox connection.

If the browser succeeds but Roblox discovery fails, reload the current Project
UAI client and use **Scan now**. The relay detail reports the executor connection,
HTTP or protocol failure. A browser success does not prove that an executor can
reach loopback: some executors route requests remotely or block local plain HTTP.
Resetting pairing does not repair an unreachable `/api/hello` endpoint. If the
browser also cannot connect, check the companion's port and diagnostics and use
Stop/Start to restart its listener.

The client also checks executor request compatibility during discovery. If a
Delta build fails local `request` but permits `HttpGet`, companion 3.5.7 supports
an authenticated `HttpPost` transport. Update the APK and client together. It
uses POST bodies for credentials, submission, polling and cancellation; no
provider content or token is added to a URL. Phone HttpPost support must also work.

During native request discovery, if a
completed native call throws, public hello probes can try minimal request options
and distinct request aliases. Only an authenticated companion selects a working
profile for later local calls. Pairing and provider work are not replayed to test
these alternatives. The diagnostic lists the attempted aliases and option forms.
This helps distinguish option rejection from an unreachable listener; it does not
by itself establish Delta or OpenCode support on a phone. A later Delta report
(October 18, 2026) confirmed OpenCode inference through the UAI Relay app; mobile
OpenCode requires the UAI Relay app from Discord. The
[standard request API](https://docs.sunc.io/Miscellaneous/request/) documents
optional Headers and does not document Timeout.

Version 3.6.0 puts connection status and Start/Stop first. Setup steps explain what
to do in Roblox. **Your messages** shows active work and received responses;
expand recent messages for details. Connection settings and diagnostics are
collapsed initially. App update progress, installation and recovery actions stay
visible when needed.

If pairing succeeds but a message returns `invalid executor request`, the outer
HttpPost message could not be decoded; this is before provider dispatch and token
validation. 3.6.0 accepts gzip bodies, including chunked uploads and wrappers that
omit Content-Encoding. Earlier apps parsed these compressed bytes as JSON and
rejected them. Update the app and reload the script; resetting pairing does not
repair request encoding. Both compressed and expanded requests are limited to
8 MiB. The reported Delta device's exact transmitted bytes remain unobserved.

Version 3.6.5 also caps the complete UTF-8 reply sent to the executor at 8 MiB,
including JSON escaping and the extra `/api/executor` envelope. It counts the
retained body's encoded size before allocating that expanded reply. An oversized
reply returns HTTP 413, or status 413 inside the executor envelope, with a fixed
`response_limit` category. The client stops polling that job without resubmitting
inference; resetting pairing cannot repair a response-size refusal.

The updated client serializes ordinary native HTTP exchanges on touch-only
hosts, keeping a still-running native call's ownership after a Lua timeout,
Stop or client reload. Cancellation has a separate bounded lane. Expanded
thinking on touch-only hosts uses an 8 KiB presentation excerpt before Markdown
formatting and native measurement; oversized RichText falls back to plain text.
Original provider reasoning stays in model context and persistence. These changes
reduce avoidable native work; they do not attribute or establish a fix for the
reported Roblox native crash. See [the investigation](../docs/INVESTIGATION_MOBILE_CRASHES.md).

The Roblox status reports actual pairing or authenticated client contact in the
current service run. A saved token alone is shown as saved pairing, not a live
connection. Requests shows accepted jobs, active work, received responses,
failures and cancellations. If Accepted stays at zero, inference has not reached
the app. Recent jobs show only the provider hostname, elapsed time, received bytes
and a safe result category; provider keys and message contents never appear.

Updated clients negotiate `capabilities.inference = {schema:1, unlimited:true}`
and send `timeout:0` for requests without an explicit finite budget. The companion
does not stop these requests because a model is quiet or reasoning takes longer
than ten seconds. Stop, an explicit request deadline, an upstream failure or the
existing response-size limit still ends work. Older clients retain their positive
timeout, and an omitted timeout remains 180 seconds. Each connection attempt has
a 15-second limit. A failed connection can try the provider's remaining addresses
before sending the HTTP request, so an unreachable first address does not hide a
reachable provider. All attempts share the original explicit request deadline.
Established request reads and writes have no hidden timeout. Inference bodies
are marked one-shot: connection loss after sending, retryable HTTP responses and
redirects cannot automatically replay the POST. Kilo's explicit, complete quota
refusal retains its separately controlled recovery.

Each running job also needs contact from its waiting Roblox client. A matching
submission retry or authenticated poll for that job renews a two-minute ownership
lease. The service checks leases every five seconds and cancels abandoned provider
connections, releasing the wake lock when no jobs remain. This is independent of
total reasoning time: regular polling can keep a job alive indefinitely. Hello,
status and other jobs cannot renew it. A lost client produces terminal
`client_disconnected`; reconnecting never repeats that inference automatically.

## Survival notes

- The service uses `foregroundServiceType="specialUse"`; Android 15 caps `dataSync`
  services at six hours per day, which would end a long session.
- An exact-alarm watchdog and `BOOT_COMPLETED` resurrect the service unless the
  user pressed Stop. **Force stop** is unrecoverable without reopening the app.
- Grant the battery-optimisation exemption, and allow auto-start in vendor settings
  on Xiaomi/Samsung/Oppo/vivo. The Diagnostics screen logs every restart.

## Security

- Loopback binding only (`127.0.0.1`), never `allowLan`.
- 64-hex token, constant-time compare, generated once and stored in
  `EncryptedSharedPreferences`; `allowBackup=false`.
- `/api/pair` validates the Host and rejects browser Origins; the API never emits
  CORS headers and never serves files.
- Provider keys transit a job in memory only and are never logged or persisted.
  Raw network exception messages are excluded from diagnostics and client errors.

## Verification

For an opt-in measurement on the actual phone, use the
[console diagnostic tools](tools/README.md). They check pairing, a controlled
45-second response through short executor polls, idempotency and cancellation
without any provider API key. Their result does not establish OpenCode access.

`app/src/test` runs on the JVM with a real CIO server and a `MockWebServer`
upstream: header filtering, URL safety, fingerprint idempotency, instance skew,
capacity 503, cancellation, tombstones, negotiated unlimited requests, explicit
deadlines, delayed responses beyond ten seconds, no automatic replay, live
activity, and the pair/auth/hello contract. Android manifest, package installer
and service behavior need a native device or emulator. Actual executor support
requires a phone running the target Roblox executor and the companion; JVM tests
and an emulator without that executor cannot establish it.

Before trusting the companion on a given executor, run the Phase 0 measurement in
`docs/MOBILE_COMPANION.md` Section 9.4: confirm loopback reachability and find the
exact wall. Executors that do not cut long calls do not need this app.
