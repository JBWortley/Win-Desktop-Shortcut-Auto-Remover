using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

internal static class Cleaner
{
    internal static readonly string DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DesktopIconCleaner");

    [STAThread]
    private static int Main(string[] args)
    {
        string reportPath = Path.Combine(DataDirectory, "Logs", "last-run.json");
        bool preview = true; // An accidental double-click is harmless.
        string testRoot = null;
        try
        {
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--run": preview = false; break;
                    case "--preview": preview = true; break;
                    case "--test-root": testRoot = Path.GetFullPath(args[++i]); break;
                    case "--report": reportPath = Path.GetFullPath(args[++i]); break;
                    default: throw new ArgumentException("Unknown argument: " + args[i]);
                }
            }
            using (Mutex mutex = new Mutex(false, "Local\\DesktopIconCleaner-" + System.Security.Principal.WindowsIdentity.GetCurrent().User.Value))
            {
                bool acquired;
                try { acquired = mutex.WaitOne(0); }
                catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) return 0;
                try { return Run(preview, testRoot, reportPath); }
                finally { mutex.ReleaseMutex(); }
            }
        }
        catch (Exception ex)
        {
            try { WriteReport(reportPath, new { FinishedUtc = DateTime.UtcNow.ToString("o"), FatalError = ex.ToString() }); }
            catch { /* Never display an error dialog in unattended operation. */ }
            return 1;
        }
    }

    internal static bool Eligible(string path)
    {
        FileAttributes attributes = File.GetAttributes(path);
        if ((attributes & FileAttributes.ReparsePoint) != 0) return false;
        if ((attributes & FileAttributes.Directory) == 0)
        {
            string extension = Path.GetExtension(path);
            return extension.Equals(".lnk", StringComparison.OrdinalIgnoreCase) || extension.Equals(".url", StringComparison.OrdinalIgnoreCase);
        }
        if (!Path.GetFileName(path).Equals("New Folder", StringComparison.OrdinalIgnoreCase)) return false;
        // Includes hidden/system entries. Failure to enumerate is NOT treated as empty.
        using (IEnumerator<string> children = Directory.EnumerateFileSystemEntries(path).GetEnumerator())
            return !children.MoveNext();
    }

    private static int Run(bool preview, string testRoot, string reportPath)
    {
        DateTime started = DateTime.UtcNow;
        List<object> results = new List<object>();
        int recycled = 0, candidates = 0, failed = 0, inspected = 0;
        string[] roots = testRoot == null ? new string[] {
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory)
        } : new string[] { testRoot };
        HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        WriteReport(reportPath, new { StartedUtc = started.ToString("o"), State = "Running", Preview = preview });
        foreach (string rawRoot in roots)
        {
            if (String.IsNullOrWhiteSpace(rawRoot)) continue;
            string root = Path.GetFullPath(rawRoot);
            if (!seen.Add(root)) continue;
            try
            {
                // Recycle Bin support must be local and predictable.
                if (root.StartsWith(@"\\", StringComparison.Ordinal) || new DriveInfo(Path.GetPathRoot(root)).DriveType != DriveType.Fixed)
                    throw new IOException("Skipping desktop on a non-local fixed drive: " + root);
                if ((File.GetAttributes(root) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Skipping reparse-point desktop: " + root);
                foreach (string path in Directory.GetFileSystemEntries(root))
                {
                    inspected++;
                    try
                    {
                        if (!Eligible(path)) continue;
                        candidates++;
                        if (preview) results.Add(new { Path = path, Status = "WouldRecycle" });
                        else
                        {
                            string recycledPath = Recycler.Recycle(path);
                            recycled++;
                            results.Add(new { Path = path, Status = "Recycled", RecyclePath = recycledPath });
                        }
                    }
                    catch (Exception ex)
                    {
                        failed++;
                        results.Add(new { Path = path, Status = "Failed", Error = ex.Message });
                    }
                }
            }
            catch (Exception ex)
            {
                failed++;
                results.Add(new { Path = root, Status = "Failed", Error = ex.Message });
            }
        }
        var report = new { StartedUtc = started.ToString("o"), FinishedUtc = DateTime.UtcNow.ToString("o"), Preview = preview,
            Inspected = inspected, Candidates = candidates, Recycled = recycled, Failed = failed, Items = results };
        WriteReport(reportPath, report);
        string history = Path.Combine(Path.GetDirectoryName(reportPath), "history.jsonl");
        if (File.Exists(history) && new FileInfo(history).Length > 1024 * 1024)
        {
            string previous = history + ".1";
            if (File.Exists(previous)) File.Delete(previous);
            File.Move(history, previous);
        }
        File.AppendAllText(history, new JavaScriptSerializer().Serialize(report) + Environment.NewLine, Encoding.UTF8);
        return failed == 0 ? 0 : 1;
    }

    private static void WriteReport(string path, object value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        string temporary = path + ".tmp";
        File.WriteAllText(temporary, new JavaScriptSerializer().Serialize(value), Encoding.UTF8);
        // AV/indexers can briefly hold a just-written report open on Windows.
        for (int attempt = 0; ; attempt++)
        {
            try
            {
                if (File.Exists(path)) File.Replace(temporary, path, null);
                else File.Move(temporary, path);
                break;
            }
            catch (IOException) { if (attempt >= 9) throw; Thread.Sleep(100); }
        }
    }
}
