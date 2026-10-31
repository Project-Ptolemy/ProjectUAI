using System.IO.Compression;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProjectUai.Bridge;

// Distribution is one EXE. Only verified embedded data is expanded, automatically,
// into an owned user cache; nothing is written beside the downloaded executable.
internal static class EmbeddedPayload
{
    private static readonly object Gate = new();
    private const int Limit = 24 << 20;
    internal static string Prepare()
    {
        lock (Gate)
        {
            using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("ProjectUai.Payload.zip")
                ?? throw new IOException("This app was built without its bridge files. Download the complete desktop executable.");
            if (resource.Length > Limit) throw new IOException("The embedded bridge package is too large.");
            using var memory = new MemoryStream(); resource.CopyTo(memory);
            byte[] bytes = memory.ToArray();
            string cache = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ProjectUAI", "desktop-payload");
            string root = UpdateFiles.Child(cache, UpdateFiles.Hash(bytes));
            UpdateFiles.NoLinks(root);
            using var archive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read);
            if (archive.Entries.Count is < 2 or > 256) throw new IOException("Invalid embedded bridge inventory.");
            var manifestEntry = archive.GetEntry("manifest.json") ?? throw new IOException("The embedded bridge inventory is missing.");
            if (manifestEntry.Length > 128 << 10) throw new IOException("The embedded bridge inventory is too large.");
            using var manifestStream = manifestEntry.Open(); using var manifestBytes = new MemoryStream();
            byte[] manifestBuffer = new byte[8192];
            for (int count; (count = manifestStream.Read(manifestBuffer, 0, manifestBuffer.Length)) != 0;)
            {
                if (manifestBytes.Length + count > 128 << 10) throw new IOException("The embedded bridge inventory is too large.");
                manifestBytes.Write(manifestBuffer, 0, count);
            }
            using var manifest = JsonDocument.Parse(manifestBytes.ToArray());
            var inventory = manifest.RootElement.GetProperty("files").EnumerateArray().ToArray();
            var files = new Dictionary<string, (long Bytes, string Hash)>(StringComparer.OrdinalIgnoreCase);
            long total = 0;
            foreach (var file in inventory)
            {
                string name = file.GetProperty("path").GetString()!;
                if (!ValidPath(name) || !files.TryAdd(name, (file.GetProperty("bytes").GetInt64(), file.GetProperty("sha256").GetString()!)))
                    throw new IOException("Invalid embedded bridge file path.");
                var item = files[name]; total += item.Bytes;
                if (item.Bytes < 0 || item.Bytes > Limit || total > Limit) throw new IOException("Embedded bridge files are too large.");
            }
            foreach (string name in new[] { "bridge/server.js", "bridge/environment.js", "bridge/inference.js", "bridge/kilo.js", "bridge/kilo-tor.js", "bridge/kilo-proxy.js", "bridge/opencode.js", "bridge/cline.js", "bridge/support.js", "bridge/mcp.js", "bridge/mcp-stdio.js", "bridge/picture-store.js", "bridge/launcher.js", "bridge/release.js", "bridge/updater.js", "bridge/supervisor.js", "bridge/web/index.html", "client/uai.lua",
                "bridge/vaults.js", "bridge/vault-paths.js", "bridge/vault-notes.js", "bridge/vault-storage.js", "bridge/vault-search.js", "bridge/vault-errors.js",
                "bridge/web/vault-client.js", "bridge/web/vaults.js", "bridge/web/vaults.css" })
                if (!files.ContainsKey(name)) throw new IOException("The embedded package is incomplete.");
            if (Directory.Exists(root))
            {
                try { Verify(root, files); Prune(cache, root); return root; }
                catch (IOException)
                {
                    // Preserve a changed cache for diagnosis and create a verified copy.
                    string invalid = UpdateFiles.Child(cache, ".invalid-" + Guid.NewGuid().ToString("N"));
                    UpdateFiles.NoLinks(invalid); Directory.Move(root, invalid);
                }
            }
            Directory.CreateDirectory(cache);
            string stage = UpdateFiles.Child(cache, ".stage-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(stage);
            try
            {
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var entry in archive.Entries)
                {
                    // Windows archivers store hierarchy with backslashes; the
                    // inventory always uses forward slashes. Normalize before
                    // comparing so either spelling resolves to the same file.
                    string name = entry.FullName.Replace('\\', '/');
                    if (name.EndsWith('/')) continue;
                    if (name == "manifest.json") continue;
                    if (!seen.Add(name) || !files.TryGetValue(name, out var expected) || entry.Length != expected.Bytes)
                        throw new IOException("The embedded bridge archive does not match its inventory.");
                    string target = UpdateFiles.Child(stage, name);
                    Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                    using var source = entry.Open(); using var output = new FileStream(target, FileMode.CreateNew);
                    byte[] buffer = new byte[65536]; long written = 0;
                    for (int count; (count = source.Read(buffer, 0, buffer.Length)) != 0;)
                    {
                        written += count;
                        if (written > expected.Bytes) throw new IOException("The embedded bridge file exceeds its declared size.");
                        output.Write(buffer, 0, count);
                    }
                }
                if (seen.Count != files.Count) throw new IOException("The embedded bridge archive is incomplete.");
                Verify(stage, files); Directory.Move(stage, root);
                Prune(cache, root); return root;
            }
            finally { UpdateFiles.RemoveOwnedDirectory(cache, stage); }
        }
    }
    // Each build extracts to its own hash-named folder; predecessors otherwise
    // accumulate forever. Recently written folders may belong to another
    // installed build that is still running, so only older ones are removed.
    private static void Prune(string cache, string keep)
    {
        try
        {
            foreach (string directory in Directory.EnumerateDirectories(cache))
            {
                try
                {
                    if (string.Equals(directory, keep, StringComparison.OrdinalIgnoreCase) ||
                        Directory.GetLastWriteTimeUtc(directory) >= DateTime.UtcNow.AddHours(-1)) continue;
                    UpdateFiles.RemoveOwnedDirectory(cache, directory);
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    private static bool ValidPath(string name) => name.Length is > 0 and < 180 && !name.Contains('\\') &&
        name.Split('/').All(part => part.Length > 0 && part != "." && part != ".." && part.IndexOfAny(Path.GetInvalidFileNameChars()) < 0 && !part.EndsWith('.') && !part.EndsWith(' ')
            && !Regex.IsMatch(part, @"\A(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|\z)", RegexOptions.IgnoreCase)) &&
        (name.StartsWith("bridge/", StringComparison.Ordinal) || name.StartsWith("licenses/", StringComparison.Ordinal) || name == "client/uai.lua" || name == "START-HERE.txt");
    private static void Verify(string root, Dictionary<string, (long Bytes, string Hash)> files)
    {
        foreach (var file in files) UpdateFiles.VerifyFile(UpdateFiles.Child(root, file.Key), file.Value.Bytes, file.Value.Hash);
        void Walk(string folder)
        {
            foreach (string file in Directory.EnumerateFileSystemEntries(folder))
            {
                UpdateFiles.NoLinks(file);
                if (Directory.Exists(file)) Walk(file);
                else if (!files.ContainsKey(Path.GetRelativePath(root, file).Replace('\\', '/')))
                    throw new IOException("Unexpected file in the embedded bridge cache.");
            }
        }
        Walk(root);
    }
}
