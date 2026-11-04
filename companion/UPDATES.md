# Android companion updates

Current companion: **3.7.2 (Android version code 9)**. Provider connections can
try remaining resolved addresses when an earlier connection attempt fails before
sending the request. This fixes failures caused by an unreachable first address
without automatically repeating a sent inference request. All attempts share the
original explicit deadline; certificate validation and the 8 MiB response limit
remain enforced. Kilo's complete quota refusal retains its separately controlled
recovery. The APK retains the existing production signing identity and application
ID.

The companion checks the official `Project-Ptolemy/ProjectUAI` GitHub releases at
startup and every 15 minutes while its app or relay process is alive. Compatible
updates download automatically by default. Turning off **Download updates
automatically** leaves metadata checks enabled; **Check now** or **Download
update** performs an explicit download. A verified download survives an app
restart and is checked again before installation.

**Install update** stages the verified APK in an Android installation session
owned by UAI Relay. Android requires the user to allow installation from UAI Relay
and confirm the update; ordinary sideloaded apps cannot silently replace
themselves. If active requests or retained replies remain, try Install again when
the relay is idle. Checking and downloading do not stop inference.

Once installation begins, new submissions are temporarily refused without being
forwarded. The pending session is saved across process restarts. If Android's
confirmation is ready while the app is in the background, **Continue
installation** opens it when you return. **Resume relay** cancels an interrupted
attempt by abandoning its owned Android session before reopening admission. If
Android cannot abandon the session, admission stays paused. The verified download
remains available for another attempt. If process death loses Android's pending
confirmation prompt, use Resume relay and then try Install again. After Android
reports success, the old process stays paused until the matching updated app
starts. A relay that was
running before installation can resume after replacement; an explicit Stop is
preserved.

## Signing continuity

Every production APK must retain application ID `dev.projectuai.relay` and the
same signing key. The reviewed public certificate is pinned in
[`release-policy.json`](release-policy.json). The release packager rejects debug
APKs and any signer that differs from this pin. The installed app also checks that
the downloaded APK's certificate matches its own installed certificate. Key
rotation is not supported by this release contract.

An existing APK signed with Android's debug key cannot receive the first
production-signed APK as an in-place update. That one-time transition requires
uninstalling the debug app and installing the production APK manually. Uninstall
clears the app's settings and pairing token, so start the relay and pair again.
Subsequent updates signed with the same production key normally preserve app
data. Do not uninstall a production app merely to apply a normal update.

Keep the private keystore and its recoverable password securely backed up outside
the repository. A Windows DPAPI-encrypted password is tied to its Windows user
and machine; copying that encrypted file alone does not make a portable backup.
Losing the signing key prevents future in-place updates. Never place a private
key, password, provider credential or local credential path in source, release
assets, command arguments or logs.

## Official release assets

Use a stable `relay-vVERSION` tag, such as `relay-v3.5.6`. A stable `vVERSION` tag
is also accepted when it contains the companion assets. Drafts and prereleases
are excluded. Each release must contain these assets together:

- `relay-release.json`
- `UAI-Relay-VERSION.apk`
- `UAI-Relay-VERSION.apk.sha256` (convenience checksum for manual downloads)

The 3.5.6 release introduces these companion assets under the shared `v3.5.6`
tag. Generating local assets does not make an update available; publishing all
three assets with the official release makes them discoverable by the updater.

The manifest has this shape. The displayed size and APK digest are illustrative;
the packager computes the real values from the signed APK.

```json
{
  "format": "project-uai-relay-release",
  "schema": 1,
  "version": "3.5.6",
  "versionCode": 3,
  "platform": "android",
  "applicationId": "dev.projectuai.relay",
  "minSdk": 26,
  "protocol": 2,
  "package": {
    "name": "UAI-Relay-3.5.6.apk",
    "bytes": 123,
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "signerSha256": "ad7d215b8ad67ce70ae2ce89ad3ea959b68202b5c38e72141a68f7d54331f4b5"
  }
}
```

The app derives download URLs from the exact official repository, release tag
and asset names. It does not accept a manifest-supplied URL. Downloads have a
150 MiB ceiling. Before staging and again before installation, the app checks
the byte count, SHA-256, package ID, version name/code, minimum SDK and signing
certificate. Both the semantic version and Android version code must be newer.
Increment `versionCode` for every released build; use three numeric version
components without leading zeroes or prerelease suffixes. Components may be at
most six digits, and `versionCode` must be at most 2,100,000,000.

The public manifest and checksum are integrity metadata, not a substitute for
the APK's signature. Keep the signing key separate from access to GitHub releases.

## Preparing a release

JDK 17, Node.js, Android SDK platform 37.1 and SDK build-tools are required. The
Gradle wrapper pins and verifies Gradle 9.6.0; AGP 9.4.1 supplies Kotlin 2.2.10.
The newer compile API supports Tor Android while minimum and target Android
versions remain 26 and 36. Set `ANDROID_HOME`, or
pass `--sdk` to the packager. On Windows it also checks the normal local Android
SDK directory. The Gradle signing configuration reads only these environment
variables from the build process:

| Variable | Value |
| --- | --- |
| `UAI_ANDROID_KEYSTORE` | Private keystore filename outside the repository |
| `UAI_ANDROID_STORE_PASSWORD` | Keystore password |
| `UAI_ANDROID_KEY_ALIAS` | Stable release key alias |
| `UAI_ANDROID_KEY_PASSWORD` | Key password |

Load these values from the release machine's secret store into the process
environment. All four must be present together. Omitting all four produces an
unsigned local release APK, which cannot pass the packager. Do not use Gradle
`-P` arguments, shell history or committed properties for signing secrets.

Follow the project's review order:

1. Update version metadata and manually review every source, documentation and
   test change, including the signing configuration and packager inputs.
2. Build the signed APK from `companion/` with
   `./gradlew --no-daemon :app:assembleRelease` in the prepared environment.
3. Inspect the generated APK, its manifest and signing certificate. The Android
   SDK's `aapt dump badging` and `apksigner verify --verbose --print-certs` expose
   this public information.
4. From the repository root, generate local assets:

   ```powershell
   node tools/build_companion.js --apk companion/app/build/outputs/apk/release/app-release.apk
   ```

5. Inspect all three generated files under `companion/release/`. The packager
   copies the signed APK unchanged, emits deterministic manifest/checksum files,
   and verifies the certificate against the committed pin. It inspects a private
   snapshot so a concurrent Gradle build cannot replace the verified input.
6. Run verification only after that inspection:

   ```powershell
   node --test test/build_companion.test.js
   node tools/build_companion.js --apk companion/app/build/outputs/apk/release/app-release.apk --check
   ```

   Also run the companion JVM suite from `companion/` with
   `./gradlew --no-daemon :app:testDebugUnitTest`, and perform the applicable
   native-device acceptance checks. Manually review every fix before rebuilding
   or retesting.
7. Publish the three reviewed assets together to an authorized official release.
   Do not mark a release public until every asset is uploaded. Never edit an
   already published APK in place; publish a newer version and version code.

The build and packaging commands do not publish a release. Generated APK assets
are ignored by Git. `--out DIR` selects another local destination; `--check`
reverifies the signed input and requires every generated output byte to match.
An optional `--signer-sha256` assertion must match the committed pin and cannot
override it.

## Device acceptance

JVM tests cover release selection, validation, downloads, persistence and
tampering. Successful compilation and JVM checks do not establish Android's
native package parsing or installer behavior. On a real Android 8+ device, verify
an upgrade between two builds signed with the production key, denial/grant of
installation permission, installer cancellation, process death during APK staging
and confirmation, recovery through Resume relay, idle admission, data retention,
service restart and an interrupted download. Confirm that a request in progress
is never cancelled merely because an update is available. No native-device
update run has been recorded for this implementation yet.

## Local verification — October 25, 2026

The reviewed production build is `UAI-Relay-3.7.0.apk`, Android version code 7,
39,830,460 bytes. Its SHA-256 is:

```text
fc6c65cf8bbc27c6d701190a14142152c8ca7788c5727ebbc483006a0a876ad4
```

The signed APK and all three release assets were inspected before verification.
SDK tools confirmed application ID `dev.projectuai.relay`, minimum SDK 26,
target SDK 36, non-debuggable status and one valid APK Signature Scheme v2 signer
matching the production pin. The APK includes Tor and its notices for
`arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`. All 64-bit native libraries have
16 KiB ELF LOAD alignment, and `zipalign -c -P 16 4` passed for the final APK.

All 89 companion JVM tests passed, with no failures, errors or skips, including
seven Kilo cases covering credential exclusion, bounded quota recovery,
cooldown status, original deadlines, cancellation and incomplete refusals.
The packager's ten tests and `tools/build_companion.js --check` passed.
`lintRelease` completed with zero errors and 35 warnings: target SDK policy,
battery/wake-lock behavior, dependency updates, icon/label and Kotlin API
suggestions. These warnings remain visible in the generated lint report.

No Android device was attached for this run. Native Tor bootstrap, circuit
changes, Android install/update behavior and actual mobile executor input remain
device acceptance checks; JVM and static APK checks do not establish them.

## Local verification — October 18, 2026

The reviewed production build is `UAI-Relay-3.5.6.apk`, Android version code 3,
9,606,374 bytes. Its SHA-256 is:

```text
985b0686f53c7cdc868c749a445c26e43e88c8affbdeda95c8b7214a65c44240
```

The APK, manifest and checksum were inspected before verification. Android SDK
tools confirmed package `dev.projectuai.relay`, minimum SDK 26, target SDK 36,
non-debuggable status and one valid APK Signature Scheme v2 signer matching the
public pin above. The installer receiver is private. All three packaged files
passed `tools/build_companion.js --check`, and the unchanged packager's ten tests
passed.

All 68 companion JVM tests passed, with no failures or skips. `lintRelease`
completed with zero errors and 24 warnings. These cover the deliberate wake-lock
and battery-exemption behavior, available dependency updates and presentation or
KTX suggestions; they remain visible in the lint report. An initial test run
exposed stale incremental test bytecode after a constructor change. Recompiling
the test classes without incremental compilation corrected that build artifact;
the fresh full suite passed. Inspection of production class and DEX constructor
references found no corresponding stale linkage in the APK.

A scan of public files and all 126 unpacked APK entries found none of the known
handover credentials or local signing secrets. These are Windows build, JVM and
static artifact checks. They do not establish native Android installation,
service survival, mobile executor compatibility or OpenCode access on a phone.
Packaging does not publish assets; GitHub publication requires its own release
verification.
