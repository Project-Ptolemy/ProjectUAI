using System.Text;
using System.Text.Json;

namespace ProjectUai.Bridge;

// Synthetic offline checks. No installer, release download, app replacement, or
// bridge startup runs here. Runtime probes and read-only installation discovery
// use real child processes; installed coding CLIs are never started.
internal static class DesktopSelfTest
{
    public static async Task<int> RunAsync(string output)
    {
        var checks = new List<string>();
        string root = Path.Combine(Path.GetTempPath(), "uai-desktop-selftest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        string? oldFixture = Environment.GetEnvironmentVariable("UAI_TEST_NODE_VERSION");
        void Check(string name, bool condition) { if (!condition) throw new IOException(name); checks.Add(name); }
        void Reject(string name, Action action)
        {
            bool rejected = false;
            try { action(); } catch (Exception error) when (error is IOException or JsonException or ArgumentException or FormatException or InvalidOperationException) { rejected = true; }
            Check(name, rejected);
        }
        try
        {
            await DesktopCapabilityTest.RunAsync(Check);
            string preferencesPath = Path.Combine(root, "preferences.json");
            Check("Missing preferences preserve enabled integrations and manual startup", DesktopPreferences.Load(preferencesPath) == new DesktopPreferences());
            var savedPreferences = new DesktopPreferences(false, false, false, false, true, KiloEnabled: true, ClineEnabled: false); savedPreferences.Save(preferencesPath);
            Check("All desktop switches survive a new preferences load", DesktopPreferences.Load(preferencesPath) == savedPreferences);
            File.WriteAllText(preferencesPath, "{\"OpenCodeEnabled\":false}");
            Check("Partial older preferences keep defaults for newly added controls", DesktopPreferences.Load(preferencesPath) == new DesktopPreferences(OpenCodeEnabled: false));
            File.WriteAllText(preferencesPath, "{\"OpenCodeEnabled\":\"yes\"}");
            Check("Invalid preferences recover to usable defaults", DesktopPreferences.Load(preferencesPath) == new DesktopPreferences());
            var launch = new System.Diagnostics.ProcessStartInfo();
            launch.Environment["UAI_OPENCODE_BINARY"] = "C:\\Installed App\\opencode-cli.exe";
            savedPreferences.BridgeOptions.Apply(launch);
            Check("Kilo tunnel preference is passed only to the bridge process", launch.Environment["UAI_KILO_TUNNEL"] == "1");
            Check("Disabled integration switches are passed to the child process", launch.Environment["UAI_OPENCODE_DISABLED"] == "1" && launch.Environment["UAI_MCP_DISABLED"] == "1");
            Check("Cline opt-out overrides an inherited enable", launch.Environment["UAI_CLINE_DISABLED"] == "1");
            new DesktopPreferences().BridgeOptions.Apply(launch);
            Check("Kilo recovery is enabled by default", launch.Environment["UAI_KILO_TUNNEL"] == "1");
            Check("Cline is enabled by default and clears stale opt-out", launch.Environment["UAI_CLINE_DISABLED"] == "0");
            new DesktopPreferences(KiloEnabled: false).BridgeOptions.Apply(launch);
            Check("Kilo recovery can be disabled independently", launch.Environment["UAI_KILO_TUNNEL"] == "0");
            Check("Re-enabled integrations override stale disables and retain binary override", launch.Environment["UAI_OPENCODE_DISABLED"] == "0" && launch.Environment["UAI_MCP_DISABLED"] == "0" && launch.Environment["UAI_OPENCODE_BINARY"] == "C:\\Installed App\\opencode-cli.exe");
            await using (var statusBridge = new BridgeProcess())
            {
                using var ready = JsonDocument.Parse("""{"schema":1,"enabled":true,"available":true,"state":"ready","message":"Ready","version":"2.17.0"}""");
                statusBridge.ApplyClineCapability(ready.RootElement);
                Check("Cline readiness requires a supported capability", statusBridge.ClineState == "ready" && statusBridge.ClineVersion == "2.17.0");
                foreach (string invalid in new[] { "{}", "null", """{"schema":2,"state":"ready"}""", """{"schema":1,"state":"ready","available":false,"enabled":true}""", """{"schema":1,"state":"ready","available":true,"enabled":false}""" })
                {
                    using var value = JsonDocument.Parse(invalid);
                    statusBridge.ApplyClineCapability(value.RootElement);
                    Check("Cline clears stale ready state for unsupported or unavailable capability " + invalid, statusBridge.ClineState == "unavailable" && statusBridge.ClineVersion is null);
                }
                using var signedOut = JsonDocument.Parse("""{"schema":1,"enabled":true,"available":false,"state":"auth-required","message":"Sign in to Cline"}""");
                statusBridge.ApplyClineCapability(signedOut.RootElement);
                Check("Signed-out Cline has an actionable status without claiming readiness", statusBridge.ClineState == "auth-required" && statusBridge.ClineDetail == "Sign in to Cline");
            }
            var detectionNode = await NodeRuntime.FindAsync() ?? throw new IOException("Node.js is required for installation discovery checks.");
            var noNode = await TunnelInstallations.FindAsync(null, default);
            Check("Missing Node reports unknown installation rather than claiming apps are absent", noNode.OpenCode is null && noNode.Cline is null);
            string apps = Path.Combine(root, "Installed apps"); Directory.CreateDirectory(apps);
            var discoveryEnvironment = new Dictionary<string, string>
            {
                ["PATH"] = apps, ["USERPROFILE"] = apps, ["LOCALAPPDATA"] = apps, ["APPDATA"] = apps,
                ["ProgramFiles"] = apps, ["ProgramFiles(x86)"] = apps,
                ["SystemRoot"] = Environment.GetEnvironmentVariable("SystemRoot") ?? "C:\\Windows",
                ["UAI_OPENCODE_DISABLED"] = "1", ["UAI_CLINE_DISABLED"] = "1",
                ["NODE_OPTIONS"] = "--uai-invalid-preload-must-be-removed"
            };
            var absentApps = await TunnelInstallations.FindAsync(detectionNode, default, discoveryEnvironment);
            Check("Empty fixture installation paths report both CLIs missing", absentApps.OpenCode == false && absentApps.Cline == false);
            string openCodeFixture = Path.Combine(apps, "opencode-cli.exe"), clineFixture = Path.Combine(apps, "cline.exe");
            File.WriteAllBytes(openCodeFixture, [0x4d, 0x5a, 0, 0]);
            File.WriteAllBytes(clineFixture, [0x4d, 0x5a, 0, 0]);
            var installedApps = await TunnelInstallations.FindAsync(detectionNode, default, discoveryEnvironment);
            Check("Disabled CLIs are found before bridge startup without executing fixture binaries", installedApps.OpenCode == true && installedApps.Cline == true);
            File.Delete(openCodeFixture); File.Delete(clineFixture);
            var removedApps = await TunnelInstallations.FindAsync(detectionNode, default, discoveryEnvironment);
            Check("Refreshing discovery clears installations that were removed", removedApps.OpenCode == false && removedApps.Cline == false);
            string overrideDirectory = Path.Combine(root, "Explicit tool locations"); Directory.CreateDirectory(overrideDirectory);
            string overrideOpenCode = Path.Combine(overrideDirectory, "custom-open.exe"), overrideCline = Path.Combine(overrideDirectory, "custom-cline.exe");
            File.WriteAllBytes(overrideOpenCode, [0x4d, 0x5a, 0, 0]); File.WriteAllBytes(overrideCline, [0x4d, 0x5a, 0, 0]);
            discoveryEnvironment["UAI_OPENCODE_BINARY"] = overrideOpenCode;
            discoveryEnvironment["UAI_CLINE_BINARY"] = overrideCline;
            var overriddenApps = await TunnelInstallations.FindAsync(detectionNode, default, discoveryEnvironment);
            Check("Explicit native binary locations are shared with bridge detection", overriddenApps.OpenCode == true && overriddenApps.Cline == true);
            using (var cancelledDiscovery = new CancellationTokenSource())
            {
                cancelledDiscovery.Cancel(); bool discoveryStopped = false;
                try { await TunnelInstallations.FindAsync(detectionNode, cancelledDiscovery.Token, discoveryEnvironment); }
                catch (OperationCanceledException) { discoveryStopped = true; }
                Check("Cancelled discovery does not start a probe", discoveryStopped);
            }
            string launchFixture = Path.Combine(root, "App with spaces", "Cowork.exe");
            var replacement = DesktopUpdater.LaunchInfo(launchFixture, "--skip-update", "--update-receipt", "receipt with spaces.json");
            var fallbackLaunch = DesktopUpdater.LaunchInfo(launchFixture, "--skip-update");
            var helperLaunch = DesktopUpdater.LaunchInfo(launchFixture, "--apply-update", "request with spaces.json");
            Check("Updated and fallback windows launch normally while the helper stays hidden", replacement.WindowStyle == System.Diagnostics.ProcessWindowStyle.Normal && fallbackLaunch.WindowStyle == System.Diagnostics.ProcessWindowStyle.Normal && helperLaunch.WindowStyle == System.Diagnostics.ProcessWindowStyle.Hidden);
            Check("Update launch preserves paths and arguments with spaces without a shell", !replacement.UseShellExecute && replacement.FileName == launchFixture && replacement.ArgumentList[2] == "receipt with spaces.json");
            using var readyReceipt = JsonDocument.Parse("{\"pid\":37,\"processStart\":12345}");
            using var invalidReceipt = JsonDocument.Parse("{\"pid\":\"37\",\"processStart\":12345}");
            Check("Restart receipt identifies the exact process rather than a reused PID", DesktopUpdater.ReadinessMatches(readyReceipt.RootElement, 37, 12345) &&
                !DesktopUpdater.ReadinessMatches(readyReceipt.RootElement, 37, 12346) && !DesktopUpdater.ReadinessMatches(readyReceipt.RootElement, 38, 12345) &&
                !DesktopUpdater.ReadinessMatches(invalidReceipt.RootElement, 37, 12345));
            Check("Stable versions reject previews, leading zeroes, and overflow", UpdateFiles.StableVersion("24.1.0", out _) &&
                !UpdateFiles.StableVersion("24.1.0-rc.1", out _) && !UpdateFiles.StableVersion("024.1.0", out _) && !UpdateFiles.StableVersion("99999999999999.1.0", out _));
            Check("Missing Node returns a setup state without running another candidate", await NodeRuntime.FindAsync(default, [], Path.Combine(root, "empty-node")) is null);
            string executable = Environment.ProcessPath ?? throw new IOException("No test executable.");
            Environment.SetEnvironmentVariable("UAI_TEST_NODE_VERSION", "v16.20.0");
            Check("Node older than 18 is rejected", await NodeRuntime.FindAsync(default, [executable], Path.Combine(root, "empty-node")) is null);
            Environment.SetEnvironmentVariable("UAI_TEST_NODE_VERSION", "v24.1.0");
            Check("Supported Node is detected from the supplied executable", await NodeRuntime.FindAsync(default, [executable], Path.Combine(root, "empty-node")) is { Version: "24.1.0", Managed: false });
            string sum = new string('a', 64);
            Check("Official Node checksum selects the exact Windows executable", NodeRuntime.ParseChecksum(sum + "  win-x64/node.exe\n", "win-x64/node.exe") == sum);
            Reject("Ambiguous Node checksum is rejected", () => NodeRuntime.ParseChecksum(sum + "  win-x64/node.exe\n" + sum + "  win-x64/node.exe\n", "win-x64/node.exe"));
            Reject("A different platform checksum is rejected", () => NodeRuntime.ParseChecksum(sum + "  win-arm64/node.exe\n", "win-x64/node.exe"));
            byte[] sample = Encoding.UTF8.GetBytes("verified runtime bytes");
            string file = Path.Combine(root, "hash.bin"); File.WriteAllBytes(file, sample);
            UpdateFiles.VerifyFile(file, sample.Length, UpdateFiles.Hash(sample));
            File.WriteAllText(file, "changed runtime bytes");
            Reject("Runtime hash tampering is rejected", () => UpdateFiles.VerifyFile(file, sample.Length, UpdateFiles.Hash(sample)));
            Reject("Cache paths cannot escape through traversal", () => UpdateFiles.Child(root, "../escaped.exe"));
            bool urlRejected = false;
            try { await UpdateFiles.DownloadAsync(new Uri("https://untrusted.invalid/file.exe"), 16, false, default); } catch (IOException) { urlRejected = true; }
            Check("Untrusted update hosts are rejected before network access", urlRejected);

            string original = Path.Combine(root, "original"); Directory.CreateDirectory(original);
            string originalFile = Path.Combine(original, "My Cowork.exe"); File.WriteAllText(originalFile, "original app stays intact");
            string cache = Path.Combine(root, "cache");
            var updater = new DesktopUpdater(original, cacheDirectory: cache);
            var currentVersion = Version.Parse(DesktopUpdater.CurrentVersion);
            string updateVersion = new Version(currentVersion.Major, currentVersion.Minor + 1, 0).ToString();
            string laterVersion = new Version(currentVersion.Major, currentVersion.Minor + 2, 0).ToString();
            byte[] binary = Encoding.UTF8.GetBytes("MZ synthetic release: never execute");
            byte[] manifest = Manifest(updateVersion, binary);
            string key = updater.Stage(manifest, binary);
            var staged = updater.Verify(key);
            Check("Verified single executable stages in a private version cache", staged.Version == updateVersion && File.ReadAllBytes(staged.Entry).SequenceEqual(binary));
            Check("Staging preserves the exact original download", File.ReadAllText(originalFile) == "original app stays intact" && Directory.GetFiles(original).Length == 1);
            Reject("A tampered executable never stages", () => updater.Stage(manifest, Encoding.UTF8.GetBytes("different")));
            Reject("Manifest cannot select another asset path", () => updater.Stage(Manifest(updateVersion, binary, "../app.exe"), binary));
            Reject("Preview version metadata is not accepted", () => DesktopUpdater.ParseManifest(Manifest(updateVersion + "-rc.1", binary)));
            Reject("Invalid cache keys never resolve outside the cache", () => updater.Verify("../../original/My Cowork.exe"));
            File.WriteAllText(staged.Entry, "corrupted");
            Reject("Cached executable is checked again before launch", () => updater.Verify(key));
            Check("A fresh verified download repairs corrupt cached bytes", updater.Stage(manifest, binary) == key && updater.Verify(key).Version == updateVersion);
            string extra = Path.Combine(Path.GetDirectoryName(staged.Entry)!, "unexpected.dll"); File.WriteAllText(extra, "unlisted");
            Reject("Unlisted cached DLLs cannot affect an app launch", () => updater.Verify(key)); File.Delete(extra);

            int rollbacks = 0, launches = 0;
            bool failed = await updater.CompleteRestartAsync(key, candidate => { launches++; return Task.FromResult(false); }, () => rollbacks++);
            Check("Failed readiness invokes fallback once without activation", !failed && launches == 1 && rollbacks == 1 && !File.Exists(Path.Combine(cache, "active.json")));
            UpdateFiles.AtomicJson(Path.Combine(cache, "pending.json"), new { key });
            Check("A failed release does not force repeated automatic startup retries", !new DesktopUpdater(original, cacheDirectory: cache).ReadyToRestart);
            File.Delete(Path.Combine(cache, "failed.json"));
            UpdateFiles.AtomicJson(Path.Combine(cache, "pending.json"), new { key });
            bool accepted = await updater.CompleteRestartAsync(key, _ => Task.FromResult(true), () => rollbacks++);
            Check("Ready app activates atomically and consumes its pending marker", accepted && File.Exists(Path.Combine(cache, "active.json")) && !File.Exists(Path.Combine(cache, "pending.json")) && rollbacks == 1);
            string activeBefore = File.ReadAllText(Path.Combine(cache, "active.json"));
            string staleVersion = Path.Combine(cache, "versions", "9.9.9-" + new string('b', 64));
            Directory.CreateDirectory(staleVersion); Directory.SetLastWriteTimeUtc(staleVersion, DateTime.UtcNow.AddHours(-2));
            string staleQuarantine = Path.Combine(cache, ".invalid-stale");
            Directory.CreateDirectory(staleQuarantine); Directory.SetLastWriteTimeUtc(staleQuarantine, DateTime.UtcNow.AddHours(-2));
            string freshVersion = Path.Combine(cache, "versions", "9.9.9-" + new string('c', 64));
            Directory.CreateDirectory(freshVersion);
            updater.PruneStaleVersions();
            Check("Stale unreferenced updates are pruned while fresh entries survive",
                !Directory.Exists(staleVersion) && !Directory.Exists(staleQuarantine) && Directory.Exists(freshVersion) &&
                File.ReadAllText(Path.Combine(cache, "active.json")) == activeBefore && Directory.Exists(Path.GetDirectoryName(staged.Entry)!));
            byte[] later = Encoding.UTF8.GetBytes("MZ next synthetic release");
            string next = updater.Stage(Manifest(laterVersion, later), later);
            bool rollback = await updater.CompleteRestartAsync(next, _ => throw new IOException("simulated launch failure"), () => rollbacks++);
            Check("A failed newer app keeps the previous active release", !rollback && rollbacks == 2 && File.ReadAllText(Path.Combine(cache, "active.json")) == activeBefore);
            bool tamperedDuringLaunch = await updater.CompleteRestartAsync(next, candidate => { File.WriteAllText(candidate.Entry, "changed after start"); return Task.FromResult(true); }, () => rollbacks++);
            Check("Hash changes during readiness cannot activate", !tamperedDuringLaunch && rollbacks == 3 && File.ReadAllText(Path.Combine(cache, "active.json")) == activeBefore);
            bool missingCandidate = await updater.CompleteRestartAsync(laterVersion + "-" + new string('f', 64), _ => { launches++; return Task.FromResult(true); }, () => rollbacks++);
            Check("A missing candidate reopens fallback without attempting a launch", !missingCandidate && rollbacks == 4 && launches == 1 && File.ReadAllText(Path.Combine(cache, "active.json")) == activeBefore);
            string repairedNext = updater.Stage(Manifest(laterVersion, later), later);
            File.WriteAllText(Path.Combine(cache, "pending.json"), "{broken}");
            bool committedWithBrokenCleanup = await updater.CompleteRestartAsync(repairedNext, _ => Task.FromResult(true), () => rollbacks++);
            Check("Pending cleanup cannot roll back an already committed ready app", committedWithBrokenCleanup && rollbacks == 4 &&
                File.ReadAllText(Path.Combine(cache, "active.json")).Contains(repairedNext, StringComparison.Ordinal));

            using var releaseList = JsonDocument.Parse(JsonSerializer.SerializeToUtf8Bytes(new[] { Release(updateVersion), Release("9.0.0", true), Release("4.0.0", false, true) }));
            Check("Selection accepts only stable official executable assets", DesktopUpdater.SelectRelease(releaseList.RootElement, DesktopUpdater.CurrentVersion)?.Version == updateVersion);
            object malformed = new { draft = false, prerelease = false, tag_name = 123, assets = new object[] { null!, 42, new { name = true } } };
            using var mixedReleases = JsonDocument.Parse(JsonSerializer.SerializeToUtf8Bytes(new object[] { null!, 42, malformed, Release(updateVersion), Release(laterVersion) }));
            Check("Malformed release entries do not conceal the newest valid update", DesktopUpdater.SelectRelease(mixedReleases.RootElement, DesktopUpdater.CurrentVersion)?.Version == laterVersion);
            using var desktopTagRelease = JsonDocument.Parse(JsonSerializer.SerializeToUtf8Bytes(new[] { Release(laterVersion, desktopTag: true) }));
            Check("Dedicated desktop release tags remain compatible", DesktopUpdater.SelectRelease(desktopTagRelease.RootElement, DesktopUpdater.CurrentVersion)?.Version == laterVersion);
            using var duplicateAssets = JsonDocument.Parse(JsonSerializer.SerializeToUtf8Bytes(new[] { Release(updateVersion, duplicateAssets: true) }));
            Check("Duplicate executable assets cannot select an ambiguous download", DesktopUpdater.SelectRelease(duplicateAssets.RootElement, DesktopUpdater.CurrentVersion) is null);
            int downloads = 0;
            byte[] releases = JsonSerializer.SerializeToUtf8Bytes(new[] { Release(updateVersion) });
            var downloaded = new DesktopUpdater(original, (uri, limit, node, token) =>
            {
                downloads++;
                return Task.FromResult(uri.Host == "api.github.com" ? releases : uri.AbsolutePath.EndsWith("desktop-release.json", StringComparison.Ordinal) ? manifest : binary);
            }, Path.Combine(root, "downloaded"));
            await downloaded.CheckAsync();
            Check("Offline release check downloads and stages without launching", downloads == 3 && downloaded.ReadyToRestart && downloaded.AvailableVersion == updateVersion);
            var reopened = new DesktopUpdater(original, cacheDirectory: Path.Combine(root, "downloaded"));
            Check("Pending update survives a fresh app instance", reopened.ReadyToRestart && reopened.AvailableVersion == updateVersion);
            string downloadedCache = Path.Combine(root, "downloaded");
            File.Delete(Path.Combine(downloadedCache, "pending.json"));
            int cachedDownloads = 0;
            var cachedUpdater = new DesktopUpdater(original, (uri, limit, node, token) =>
            {
                cachedDownloads++;
                return Task.FromResult(uri.Host == "api.github.com" ? releases : uri.AbsolutePath.EndsWith("desktop-release.json", StringComparison.Ordinal)
                    ? manifest : throw new IOException("A verified executable should not download again."));
            }, downloadedCache);
            await cachedUpdater.CheckAsync();
            Check("Interrupted checks reuse an intact cached executable", cachedDownloads == 2 && cachedUpdater.ReadyToRestart);
            File.Delete(Path.Combine(downloadedCache, "pending.json"));
            UpdateFiles.AtomicJson(Path.Combine(downloadedCache, "failed.json"), new { key });
            cachedDownloads = 0;
            var retryUpdater = new DesktopUpdater(original, (uri, limit, node, token) =>
            {
                cachedDownloads++;
                return Task.FromResult(uri.Host == "api.github.com" ? releases : manifest);
            }, downloadedCache);
            await retryUpdater.CheckAsync();
            Check("Automatic checks avoid downloading or retrying a rejected executable", cachedDownloads == 2 && !retryUpdater.ReadyToRestart && retryUpdater.State == "Unavailable");
            await retryUpdater.CheckAsync(retryFailed: true);
            Check("An explicit check can retry a rejected release without losing cached integrity", cachedDownloads == 4 && retryUpdater.ReadyToRestart &&
                !File.Exists(Path.Combine(downloadedCache, "failed.json")) && File.Exists(Path.Combine(downloadedCache, "pending.json")));

            using var canceled = new CancellationTokenSource();
            int canceledDownloads = 0;
            var canceledUpdater = new DesktopUpdater(original, (uri, limit, node, token) =>
            {
                canceledDownloads++;
                canceled.Cancel();
                return Task.FromResult(releases);
            }, Path.Combine(root, "canceled"));
            bool observedCancellation = false;
            try { await canceledUpdater.CheckAsync(canceled.Token); } catch (OperationCanceledException) { observedCancellation = true; }
            Check("Cancellation during a check stops staging and is not an unavailable update", observedCancellation && canceledDownloads == 1 &&
                canceledUpdater.State == "Current" && !canceledUpdater.ReadyToRestart && !File.Exists(Path.Combine(root, "canceled", "pending.json")));
            try { await canceledUpdater.CheckAsync(canceled.Token); } catch (OperationCanceledException) { }
            Check("A pre-canceled update check performs no further download", canceledDownloads == 1);

            int failureDownloads = 0;
            var networkRecovery = new DesktopUpdater(original, (uri, limit, node, token) =>
            {
                failureDownloads++;
                return failureDownloads == 1 ? Task.FromException<byte[]>(new HttpRequestException("offline")) : Task.FromResult(Encoding.UTF8.GetBytes("[]"));
            }, Path.Combine(root, "network-recovery"));
            await networkRecovery.CheckAsync();
            Check("Network failure leaves the app usable without a pending update", networkRecovery.State == "Unavailable" && !networkRecovery.ReadyToRestart);
            await networkRecovery.CheckAsync();
            Check("A failed network check releases its gate for the next attempt", failureDownloads == 2 && networkRecovery.State == "Current");

            var blockedFetch = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
            int concurrentDownloads = 0;
            var concurrentUpdater = new DesktopUpdater(original, (uri, limit, node, token) =>
            {
                Interlocked.Increment(ref concurrentDownloads);
                return blockedFetch.Task;
            }, Path.Combine(root, "concurrent"));
            Task firstCheck = concurrentUpdater.CheckAsync();
            await concurrentUpdater.CheckAsync();
            blockedFetch.SetResult(Encoding.UTF8.GetBytes("[]"));
            await firstCheck;
            Check("Concurrent checks share one download and leave a settled state", concurrentDownloads == 1 && concurrentUpdater.State == "Current");
            Check("Installation cache identity ignores trailing separator and casing", DesktopUpdater.CacheFor(original) == DesktopUpdater.CacheFor(original.ToUpperInvariant() + Path.DirectorySeparatorChar));
            await File.WriteAllTextAsync(output, JsonSerializer.Serialize(new { ok = true, checks }, new JsonSerializerOptions { WriteIndented = true }));
            return 0;
        }
        catch (Exception error)
        {
            await File.WriteAllTextAsync(output, JsonSerializer.Serialize(new { ok = false, checks, error = error.ToString() }, new JsonSerializerOptions { WriteIndented = true }));
            return 1;
        }
        finally
        {
            Environment.SetEnvironmentVariable("UAI_TEST_NODE_VERSION", oldFixture);
            UpdateFiles.RemoveOwnedDirectory(Path.GetTempPath(), root);
        }
    }

    private static byte[] Manifest(string version, byte[] bytes, string? filename = null) => JsonSerializer.SerializeToUtf8Bytes(new {
        format = "project-uai-desktop-release", schema = 1, version, platform = "win-x64", protocol = 1,
        package = new { name = filename ?? $"UAI-Bridge-{version}-win-x64.exe", bytes = bytes.Length, sha256 = UpdateFiles.Hash(bytes) } });

    private static object Release(string version, bool prerelease = false, bool untrusted = false, bool desktopTag = false, bool duplicateAssets = false)
    {
        string tag = (desktopTag ? "desktop-v" : "v") + version;
        string[] names = duplicateAssets ? ["desktop-release.json", $"UAI-Bridge-{version}-win-x64.exe", $"UAI-Bridge-{version}-win-x64.exe"]
            : ["desktop-release.json", $"UAI-Bridge-{version}-win-x64.exe"];
        return new { draft = false, prerelease, tag_name = tag, assets = names.Select(name => new {
            name, browser_download_url = $"https://github.com/{(untrusted ? "Other/Repo" : "Project-Ptolemy/ProjectUAI")}/releases/download/{tag}/{name}" }).ToArray() };
    }
}
