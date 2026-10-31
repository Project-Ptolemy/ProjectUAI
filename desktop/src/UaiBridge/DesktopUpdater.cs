using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProjectUai.Bridge;

internal sealed class DesktopUpdater
{
    public const string CurrentVersion = "3.8.0";
    private const string Repo = "Project-Ptolemy/ProjectUAI";
    private const string ManifestName = "desktop-release.json";
    private const string Executable = "UAI Bridge.exe";
    private const int MaxExecutable = 200 << 20;
    public static string InstallationRoot { get; private set; } = Path.GetFullPath(AppContext.BaseDirectory);
    public static string InstallationExecutable { get; private set; } = Environment.ProcessPath ?? Path.Combine(InstallationRoot, Executable);
    private readonly string cache;
    private readonly Func<Uri, int, bool, CancellationToken, Task<byte[]>> download;
    private int checking;
    private int applying;
    private string? stagedKey;
    public string State { get; private set; } = "Current";
    public string Detail { get; private set; } = "Updates are checked automatically.";
    public string? AvailableVersion { get; private set; }
    public bool ReadyToRestart => stagedKey is not null;
    public event Action? Changed;

    public DesktopUpdater(string? installationRoot = null, Func<Uri, int, bool, CancellationToken, Task<byte[]>>? fetch = null, string? cacheDirectory = null)
    {
        string root = Path.GetFullPath(installationRoot ?? InstallationRoot);
        cache = cacheDirectory is null ? CacheFor(root) : Path.GetFullPath(cacheDirectory); download = fetch ?? UpdateFiles.DownloadAsync;
        try
        {
            string key = ReadPointer("pending.json");
            var pending = Verify(key);
            if (!Rejected(key) && Version.Parse(pending.Version) > Version.Parse(CurrentVersion))
            { stagedKey = key; AvailableVersion = pending.Version; State = "Ready"; Detail = "An update is ready for the next app restart."; }
        }
        catch (Exception error) when (Recoverable(error)) { }
    }

    internal static string CacheFor(string root) => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ProjectUAI", "desktop-updates", UpdateFiles.Hash(Encoding.UTF8.GetBytes(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar).ToLowerInvariant()))[..32]);
    private static bool Recoverable(Exception error) => error is IOException or UnauthorizedAccessException or JsonException or ArgumentException or
        KeyNotFoundException or InvalidOperationException or FormatException or HttpRequestException or OperationCanceledException or System.ComponentModel.Win32Exception or TimeoutException;
    private void Set(string state, string detail) { State = state; Detail = detail; Changed?.Invoke(); }
    private string ReadPointer(string name)
    {
        using var doc = JsonDocument.Parse(UpdateFiles.ReadBounded(Path.Combine(cache, name), 4096));
        string key = doc.RootElement.GetProperty("key").GetString() ?? "";
        if (!ValidKey(key)) throw new IOException("Invalid update pointer.");
        return key;
    }
    private bool Rejected(string key)
    {
        try { return ReadPointer("failed.json") == key; }
        catch (Exception error) when (Recoverable(error)) { return false; }
    }

    public async Task CheckAsync(CancellationToken cancellationToken = default, bool retryFailed = false)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (Interlocked.CompareExchange(ref checking, 1, 0) != 0) return;
        try
        {
            if (ReadyToRestart) return;
            AvailableVersion = null;
            Set("Checking", "Checking GitHub for an app update...");
            using var releases = JsonDocument.Parse(await download(new Uri($"https://api.github.com/repos/{Repo}/releases?per_page=100"), 2 << 20, false, cancellationToken));
            cancellationToken.ThrowIfCancellationRequested();
            var candidate = SelectRelease(releases.RootElement, CurrentVersion);
            if (candidate is null) { Set("Current", "You have the latest compatible app release."); return; }
            var (version, manifestUri, archiveUri) = candidate.Value;
            byte[] manifestBytes = await download(manifestUri, 64 << 10, false, cancellationToken);
            var manifest = ParseManifest(manifestBytes, version);
            cancellationToken.ThrowIfCancellationRequested();
            string key = manifest.Version + "-" + manifest.Hash;
            AvailableVersion = version;
            if (!retryFailed && Rejected(key))
            {
                Set("Unavailable", $"Version {version} could not start previously. Check for updates to retry it.");
                return;
            }
            // A verified cached download can be reused after an interrupted check.
            bool cached = false;
            try { Verify(key); cached = true; } catch (Exception error) when (Recoverable(error)) { }
            if (!cached)
            {
                Set("Downloading", $"Downloading app version {version}...");
                byte[] archive = await download(archiveUri, checked((int)manifest.Bytes), false, cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                Stage(manifestBytes, archive);
            }
            cancellationToken.ThrowIfCancellationRequested();
            if (retryFailed) RemovePointerIfMatches("failed.json", key);
            UpdateFiles.AtomicJson(Path.Combine(cache, "pending.json"), new { key });
            stagedKey = key;
            PruneStaleVersions();
            Set("Ready", $"Version {version} is ready. It will apply when the app restarts.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            AvailableVersion = null;
            Set("Current", "The update check was canceled. Check again whenever you are ready.");
            throw;
        }
        catch (Exception error) when (Recoverable(error))
        {
            Set("Unavailable", error is HttpRequestException or OperationCanceledException
                ? "The update service could not be reached. Check again when the connection is available."
                : "Could not verify an app update. Check again to retry; this version remains ready to use.");
        }
        finally { Volatile.Write(ref checking, 0); }
    }

    internal static (string Version, Uri Manifest, Uri Archive)? SelectRelease(JsonElement releases, string current)
    {
        if (releases.ValueKind != JsonValueKind.Array) throw new IOException("Invalid release list.");
        if (!UpdateFiles.StableVersion(current, out var currentVersion)) throw new ArgumentException("Invalid current desktop version.", nameof(current));
        var candidates = new List<(string Version, Uri Manifest, Uri Archive)>();
        foreach (var release in releases.EnumerateArray().Take(100))
        {
            if (release.ValueKind != JsonValueKind.Object || !release.TryGetProperty("draft", out var draft) || draft.ValueKind != JsonValueKind.False ||
                !release.TryGetProperty("prerelease", out var pre) || pre.ValueKind != JsonValueKind.False ||
                !release.TryGetProperty("tag_name", out var tagElement) || tagElement.ValueKind != JsonValueKind.String ||
                !release.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array) continue;
            string tag = tagElement.GetString() ?? "";
            var match = Regex.Match(tag, @"\A(?:desktop-)?v(\d+\.\d+\.\d+)\z");
            if (!match.Success || !UpdateFiles.StableVersion(match.Groups[1].Value, out var parsed) || parsed <= currentVersion) continue;
            string version = match.Groups[1].Value;
            Uri? Asset(string name)
            {
                string expected = $"https://github.com/{Repo}/releases/download/{tag}/{name}";
                var matches = assets.EnumerateArray().Where(asset => asset.ValueKind == JsonValueKind.Object &&
                    asset.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String && n.GetString() == name).ToArray();
                return matches.Length == 1 && matches[0].TryGetProperty("browser_download_url", out var u) &&
                    u.ValueKind == JsonValueKind.String && u.GetString() == expected ? new Uri(expected) : null;
            }
            var manifest = Asset(ManifestName); var archive = Asset($"UAI-Bridge-{version}-win-x64.exe");
            if (manifest is not null && archive is not null) candidates.Add((version, manifest, archive));
        }
        return candidates.Count == 0 ? null : candidates.OrderByDescending(item => Version.Parse(item.Version))
            .ThenBy(item => item.Manifest.AbsoluteUri, StringComparer.Ordinal).First();
    }

    internal sealed record ReleaseManifest(string Version, string Hash, long Bytes);
    internal static ReleaseManifest ParseManifest(byte[] bytes, string? expected = null)
    {
        using var doc = JsonDocument.Parse(Encoding.UTF8.GetString(bytes).TrimStart('\uFEFF'));
        var value = doc.RootElement;
        string version = value.GetProperty("version").GetString() ?? "";
        var package = value.GetProperty("package");
        string hash = package.GetProperty("sha256").GetString() ?? "";
        long size = package.GetProperty("bytes").GetInt64();
        if (value.GetProperty("format").GetString() != "project-uai-desktop-release" || value.GetProperty("schema").GetInt32() != 1 ||
            value.GetProperty("protocol").GetInt32() != 1 || value.GetProperty("platform").GetString() != "win-x64" ||
            !UpdateFiles.StableVersion(version, out _) || (expected is not null && version != expected) ||
            package.GetProperty("name").GetString() != $"UAI-Bridge-{version}-win-x64.exe" || size <= 0 || size > MaxExecutable ||
            !Regex.IsMatch(hash, @"\A[a-f0-9]{64}\z")) throw new IOException("Incompatible desktop release manifest.");
        return new ReleaseManifest(version, hash, size);
    }

    internal string Stage(byte[] manifestBytes, byte[] executableBytes)
    {
        if (manifestBytes.Length > 64 << 10) throw new IOException("Desktop release metadata is too large.");
        var manifest = ParseManifest(manifestBytes);
        if (executableBytes.Length != manifest.Bytes || UpdateFiles.Hash(executableBytes) != manifest.Hash)
            throw new IOException("Desktop executable SHA-256 mismatch.");
        string key = manifest.Version + "-" + manifest.Hash;
        string destination = UpdateFiles.Child(cache, "versions/" + key);
        UpdateFiles.NoLinks(destination); Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        if (Directory.Exists(destination))
        {
            try { Verify(key); return key; }
            catch (Exception error) when (Recoverable(error))
            { Directory.Move(destination, UpdateFiles.Child(cache, ".invalid-" + Guid.NewGuid().ToString("N"))); }
        }
        string stage = UpdateFiles.Child(cache, ".stage-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(stage);
        try
        {
            File.WriteAllBytes(Path.Combine(stage, Executable), executableBytes);
            File.WriteAllBytes(Path.Combine(stage, ManifestName), manifestBytes);
            VerifyContents(stage, manifest);
            try { Directory.Move(stage, destination); }
            catch (IOException) when (Directory.Exists(destination))
            {
                // Another check may have atomically staged the same release.
                Verify(key);
            }
            return key;
        }
        finally { UpdateFiles.RemoveOwnedDirectory(cache, stage); }
    }

    internal sealed record CachedRelease(string Key, string Version, string Entry);
    private static bool ValidKey(string key) => Regex.IsMatch(key, @"\A\d+\.\d+\.\d+-[a-f0-9]{64}\z");
    internal CachedRelease Verify(string key)
    {
        if (!ValidKey(key)) throw new IOException("Invalid cached desktop version.");
        string directory = UpdateFiles.Child(cache, "versions/" + key);
        var manifest = ParseManifest(UpdateFiles.ReadBounded(Path.Combine(directory, ManifestName), 64 << 10));
        if (key != manifest.Version + "-" + manifest.Hash) throw new IOException("Cached desktop manifest mismatch.");
        VerifyContents(directory, manifest);
        return new CachedRelease(key, manifest.Version, Path.Combine(directory, Executable));
    }

    private static void VerifyContents(string directory, ReleaseManifest manifest)
    {
        UpdateFiles.NoLinks(directory);
        UpdateFiles.VerifyFile(Path.Combine(directory, Executable), manifest.Bytes, manifest.Hash);
        foreach (string entry in Directory.EnumerateFileSystemEntries(directory))
        {
            UpdateFiles.NoLinks(entry);
            if (Directory.Exists(entry) || Path.GetFileName(entry) is not (Executable or ManifestName))
                throw new IOException("Unexpected cached release file.");
        }
    }
    // Launch an independent, installed helper. It waits for this app and its
    // bridge to close, then verifies again and starts the staged copy. No file in
    // the original download is overwritten; its shortcut remains a safe fallback.
    public bool ApplyOnExit() => ApplyOnExitAsync().GetAwaiter().GetResult();

    public async Task<bool> ApplyOnExitAsync(CancellationToken cancellationToken = default)
    {
        if (Interlocked.CompareExchange(ref applying, 1, 0) != 0) return false;
        string? request = null;
        Process? helperProcess = null;
        bool accepted = false;
        try
        {
            if (stagedKey is not { } key) return false;
            cancellationToken.ThrowIfCancellationRequested();
            Verify(key);
            string helper = Environment.ProcessPath ?? throw new IOException("Application path is unavailable.");
            request = UpdateFiles.Child(cache, ".request-" + Guid.NewGuid().ToString("N") + ".json");
            using var parent = Process.GetCurrentProcess();
            UpdateFiles.AtomicJson(request, new { key, installationRoot = InstallationRoot,
                parentPid = Environment.ProcessId, parentStart = parent.StartTime.ToUniversalTime().Ticks,
                fallback = helper });
            helperProcess = Start(helper, "--installation-root", InstallationRoot, "--installation-executable", InstallationExecutable, "--apply-update", request);
            string acknowledgment = request + ".accepted";
            for (int attempt = 0; attempt < 200; attempt++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (File.Exists(acknowledgment))
                {
                    using var response = JsonDocument.Parse(UpdateFiles.ReadBounded(acknowledgment, 4096));
                    accepted = !helperProcess.HasExited && response.RootElement.GetProperty("key").GetString() == key &&
                        ReadinessMatches(response.RootElement, helperProcess.Id, helperProcess.StartTime.ToUniversalTime().Ticks);
                    break;
                }
                if (helperProcess.HasExited) break;
                await Task.Delay(50, cancellationToken).ConfigureAwait(false);
            }
            if (!accepted) throw new IOException("The update helper did not accept the restart request.");
            stagedKey = null;
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        { Set("Ready", "The restart was canceled. The update is still ready."); throw; }
        catch (Exception error) when (Recoverable(error))
        { Set("Unavailable", "The update could not restart. The current app is still available; try again later."); return false; }
        finally
        {
            if (!accepted) StopCandidate(helperProcess);
            helperProcess?.Dispose();
            if (request is not null)
            {
                TryDeleteFile(request + ".accepted");
                if (!accepted) TryDeleteFile(request);
            }
            Volatile.Write(ref applying, 0);
        }
    }

    private static Process Start(string executable, params string[] args)
    {
        return Process.Start(LaunchInfo(executable, args)) ?? throw new IOException("The updated app could not start.");
    }

    internal static ProcessStartInfo LaunchInfo(string executable, params string[] args)
    {
        // The updater helper has no window. The replacement and fallback are
        // interactive apps and must return to the taskbar visibly after restart.
        var info = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
            WindowStyle = args.Contains("--apply-update") ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal,
            WorkingDirectory = Path.GetDirectoryName(executable)! };
        foreach (string argument in args) info.ArgumentList.Add(argument);
        return info;
    }

    public static void Configure(string[] args)
    {
        int at = Array.IndexOf(args, "--installation-root");
        if (at >= 0 && at + 1 < args.Length && Path.IsPathFullyQualified(args[at + 1])) InstallationRoot = Path.GetFullPath(args[at + 1]);
        at = Array.IndexOf(args, "--installation-executable");
        if (at >= 0 && at + 1 < args.Length && Path.IsPathFullyQualified(args[at + 1]) &&
            SamePath(Path.GetDirectoryName(Path.GetFullPath(args[at + 1]))!, InstallationRoot))
            InstallationExecutable = Path.GetFullPath(args[at + 1]);
    }

    private static bool SamePath(string left, string right) => string.Equals(Path.TrimEndingDirectorySeparator(Path.GetFullPath(left)),
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(right)), StringComparison.OrdinalIgnoreCase);

    public static async Task<int> RunHelperAsync(string requestFile)
    {
        var updater = new DesktopUpdater();
        string? fallback = null;
        string? request = null;
        bool parentExited = false;
        Process? candidateChild = null;
        try
        {
            request = UpdateFiles.Child(updater.cache, Path.GetRelativePath(updater.cache, requestFile));
            if (!Regex.IsMatch(Path.GetFileName(request), @"\A\.request-[a-f0-9]{32}\.json\z")) return 1;
            using var doc = JsonDocument.Parse(UpdateFiles.ReadBounded(request, 8192));
            var value = doc.RootElement;
            if (!SamePath(value.GetProperty("installationRoot").GetString()!, InstallationRoot)) return 1;
            string key = value.GetProperty("key").GetString()!;
            if (!ValidKey(key)) return 1;
            string old = value.GetProperty("fallback").GetString()!;
            string baseExe = InstallationExecutable;
            string activeExe = baseExe;
            try { activeExe = updater.Verify(updater.ReadPointer("active.json")).Entry; } catch (Exception error) when (Recoverable(error)) { }
            // A cached running app can have been damaged on disk. Recover to the
            // retained installation rather than attempting those damaged bytes.
            string? activePath = null;
            try { activePath = UpdateFiles.Child(updater.cache, "versions/" + updater.ReadPointer("active.json") + "/" + Executable); }
            catch (Exception error) when (Recoverable(error)) { }
            if (!SamePath(old, baseExe) && !SamePath(old, activeExe) && (activePath is null || !SamePath(old, activePath))) return 1;
            fallback = SamePath(old, activeExe) ? activeExe : baseExe;
            try
            {
                using var parent = Process.GetProcessById(value.GetProperty("parentPid").GetInt32());
                if (parent.StartTime.ToUniversalTime().Ticks != value.GetProperty("parentStart").GetInt64()) return 1;
                // The app stays open until this receipt confirms the helper owns
                // a validated request. Candidate verification belongs to the
                // restart transaction so every later failure reopens fallback.
                using var helper = Process.GetCurrentProcess();
                UpdateFiles.AtomicJson(request + ".accepted", new { key, pid = Environment.ProcessId,
                    processStart = helper.StartTime.ToUniversalTime().Ticks });
                await parent.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(30));
                parentExited = true;
            }
            catch (ArgumentException)
            {
                parentExited = true;
                using var helper = Process.GetCurrentProcess();
                UpdateFiles.AtomicJson(request + ".accepted", new { key, pid = Environment.ProcessId,
                    processStart = helper.StartTime.ToUniversalTime().Ticks });
            }
            bool success = await updater.CompleteRestartAsync(key, async candidate =>
            {
                string receipt = UpdateFiles.Child(updater.cache, ".ready-" + Guid.NewGuid().ToString("N") + ".json");
                candidateChild?.Dispose();
                var child = candidateChild = Start(candidate.Entry, "--installation-root", InstallationRoot, "--installation-executable", InstallationExecutable,
                    "--skip-update", "--update-receipt", receipt);
                long start = child.StartTime.ToUniversalTime().Ticks;
                bool ready = false;
                try
                {
                    for (int wait = 0; wait < 150; wait++)
                    {
                        if (File.Exists(receipt))
                        {
                            using var response = JsonDocument.Parse(UpdateFiles.ReadBounded(receipt, 4096));
                            ready = !child.HasExited && response.RootElement.GetProperty("version").GetString() == candidate.Version &&
                                ReadinessMatches(response.RootElement, child.Id, start);
                            break;
                        }
                        if (child.HasExited) break;
                        await Task.Delay(200);
                    }
                    return ready;
                }
                finally
                {
                    if (!ready) StopCandidate(child);
                    TryDeleteFile(receipt);
                }
            }, () =>
            {
                StopCandidate(candidateChild);
                using var oldApp = Start(fallback, "--installation-root", InstallationRoot, "--installation-executable", InstallationExecutable, "--skip-update");
            });
            return success ? 0 : 1;
        }
        catch (Exception error) when (Recoverable(error))
        {
            StopCandidate(candidateChild);
            if (fallback is not null && parentExited)
                try { using var old = Start(fallback, "--installation-root", InstallationRoot, "--installation-executable", InstallationExecutable, "--skip-update"); } catch (Exception failure) when (Recoverable(failure)) { }
            return 1;
        }
        finally
        {
            candidateChild?.Dispose();
            if (request is not null)
            {
                TryDeleteFile(request);
                TryDeleteFile(request + ".accepted");
            }
        }
    }

    internal static bool ReadinessMatches(JsonElement receipt, int pid, long processStart) =>
        receipt.ValueKind == JsonValueKind.Object && receipt.TryGetProperty("pid", out var id) && id.ValueKind == JsonValueKind.Number &&
        id.TryGetInt32(out int actualPid) && actualPid == pid && receipt.TryGetProperty("processStart", out var started) &&
        started.ValueKind == JsonValueKind.Number && started.TryGetInt64(out long actualStart) && actualStart == processStart;

    private static void TryDeleteFile(string file)
    {
        try { UpdateFiles.NoLinks(file); if (File.Exists(file)) File.Delete(file); }
        catch (Exception error) when (Recoverable(error)) { }
    }

    private void RemovePointerIfMatches(string name, string key)
    {
        string file = Path.Combine(cache, name);
        UpdateFiles.NoLinks(file);
        if (File.Exists(file) && ReadPointer(name) == key) File.Delete(file);
    }

    private static void StopCandidate(Process? child)
    {
        try { if (child is not null && !child.HasExited) { child.Kill(true); child.WaitForExit(5000); } }
        catch (Exception error) when (Recoverable(error)) { }
    }

    // The same transaction is exercised offline with a synthetic readiness
    // provider: a failed launch never advances the pointer or loses fallback.
    internal async Task<bool> CompleteRestartAsync(string key, Func<CachedRelease, Task<bool>> launch, Action rollback)
    {
        try
        {
            var candidate = Verify(key);
            if (!await launch(candidate)) throw new IOException("The updated app did not become ready.");
            Verify(key);
            UpdateFiles.AtomicJson(Path.Combine(cache, "active.json"), new { key });
            // A cleanup failure after committing must not roll back a ready app.
            try
            {
                RemovePointerIfMatches("pending.json", key);
            }
            catch (Exception error) when (Recoverable(error)) { }
            try { RemovePointerIfMatches("failed.json", key); }
            catch (Exception error) when (Recoverable(error)) { }
            if (stagedKey == key) stagedKey = null;
            PruneStaleVersions();
            return true;
        }
        catch (Exception error) when (Recoverable(error))
        {
            try { if (ValidKey(key)) UpdateFiles.AtomicJson(Path.Combine(cache, "failed.json"), new { key }); }
            catch (Exception cleanup) when (Recoverable(cleanup)) { }
            foreach (string name in new[] { "pending.json", "active.json" })
                try { RemovePointerIfMatches(name, key); } catch (Exception cleanup) when (Recoverable(cleanup)) { }
            try { rollback(); } catch (Exception failure) when (Recoverable(failure)) { }
            return false;
        }
    }

    // Applied updates leave their predecessors in versions/. Entries the
    // pointers still reference are kept; older unreferenced ones are re-downloadable
    // and removed. Recently written entries survive so concurrent app instances
    // of different builds never race the prune.
    internal void PruneStaleVersions()
    {
        try
        {
            var keep = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string pointer in new[] { "active.json", "pending.json", "failed.json" })
                try { keep.Add(ReadPointer(pointer)); } catch (Exception error) when (Recoverable(error)) { }
            DateTime cutoff = DateTime.UtcNow.AddHours(-1);
            foreach (string directory in Directory.EnumerateDirectories(UpdateFiles.Child(cache, "versions")))
            {
                try
                {
                    if (keep.Contains(Path.GetFileName(directory)) || Directory.GetLastWriteTimeUtc(directory) >= cutoff) continue;
                    UpdateFiles.RemoveOwnedDirectory(cache, directory);
                }
                catch (Exception error) when (Recoverable(error)) { }
            }
            foreach (string directory in Directory.EnumerateDirectories(cache))
            {
                try
                {
                    string name = Path.GetFileName(directory);
                    if (!(name.StartsWith(".invalid-", StringComparison.Ordinal) || name.StartsWith(".stage-", StringComparison.Ordinal)) ||
                        Directory.GetLastWriteTimeUtc(directory) >= cutoff) continue;
                    UpdateFiles.RemoveOwnedDirectory(cache, directory);
                }
                catch (Exception error) when (Recoverable(error)) { }
            }
        }
        catch (Exception error) when (Recoverable(error)) { }
    }

    public static bool TryDispatch(string[] args)
    {
        if (args.Contains("--skip-update") || args.Any(argument => argument.StartsWith("--", StringComparison.Ordinal) && argument is not ("--installation-root" or "--installation-executable"))) return false;
        try
        {
            var updater = new DesktopUpdater();
            // A normal close may have left a staged release for the next launch.
            if (updater.ReadyToRestart) return updater.ApplyOnExit();
            string key = updater.ReadPointer("active.json");
            if (updater.Rejected(key)) return false;
            var release = updater.Verify(key);
            if (Version.Parse(release.Version) <= Version.Parse(CurrentVersion)) return false;
            updater.stagedKey = key;
            return updater.ApplyOnExit();
        }
        catch (Exception error) when (Recoverable(error)) { return false; }
    }

    public static void MarkReady(string[] args)
    {
        int at = Array.IndexOf(args, "--update-receipt");
        if (at < 0 || at + 1 >= args.Length) return;
        try
        {
            string cache = CacheFor(InstallationRoot);
            string receipt = UpdateFiles.Child(cache, Path.GetRelativePath(cache, args[at + 1]));
            if (!Regex.IsMatch(Path.GetFileName(receipt), @"\A\.ready-[a-f0-9]{32}\.json\z")) return;
            using var process = Process.GetCurrentProcess();
            UpdateFiles.AtomicJson(receipt, new { version = CurrentVersion, pid = Environment.ProcessId,
                processStart = process.StartTime.ToUniversalTime().Ticks });
        }
        catch (Exception error) when (Recoverable(error)) { }
    }
}
