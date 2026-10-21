using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Sunshine Harmony USB Patch Setup")]
[assembly: AssemblyProduct("Sunshine Harmony USB")]
[assembly: AssemblyVersion("0.5.9.3")]
[assembly: AssemblyFileVersion("0.5.9.3")]

internal static class Setup {
    private const string PayloadHash = "78af881ac5e72b98f607a8720b3e8d0aafb34ef4401292ca6c333e186469f182";
    private static string Extract(string destination) {
        using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")) {
            if (payload == null) throw new InvalidDataException("Installer payload is missing.");
            using (MemoryStream data = new MemoryStream()) {
                payload.CopyTo(data);
                data.Position = 0;
                using (SHA256 sha = SHA256.Create()) {
                    string actual = BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "").ToLowerInvariant();
                    if (actual != PayloadHash) throw new InvalidDataException("Installer payload verification failed.");
                }
                data.Position = 0;
                Directory.CreateDirectory(destination);
                string root = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                using (ZipArchive zip = new ZipArchive(data, ZipArchiveMode.Read)) {
                    foreach (ZipArchiveEntry entry in zip.Entries) {
                        string target = Path.GetFullPath(Path.Combine(root, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
                        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Unsafe archive path.");
                        if (entry.FullName.EndsWith("/")) { Directory.CreateDirectory(target); continue; }
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        using (Stream input = entry.Open())
                        using (FileStream output = new FileStream(target, FileMode.CreateNew, FileAccess.Write)) input.CopyTo(output);
                    }
                }
            }
        }
        string package = Path.Combine(destination, "Sunshine-Harmony-USB");
        if (!File.Exists(Path.Combine(package, "Install.ps1")) || !File.Exists(Path.Combine(package, "manifest.json")))
            throw new InvalidDataException("Installer package is incomplete.");
        return package;
    }

    [STAThread]
    private static int Main(string[] args) {
        bool extractOnly = args.Length == 2 && args[0] == "--extract-only";
        try {
            if (!extractOnly) {
                Application.EnableVisualStyles();
                if (MessageBox.Show("安装 Sunshine 鸿蒙 USB / 虚拟显示器增强补丁 0.5.9+usb.3。\n\n要求已安装 Sunshine 基地版 GUI 0.5.9 系列，路径 C:\\Program Files\\Sunshine。USB 串流另需 Python、官方 HDC、Channel 和 Moonlight。\n\n安装会请求管理员授权，并备份原面板。是否继续？", "Sunshine 鸿蒙 USB 补丁", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return 2;
            }
            string destination = extractOnly ? args[1] : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sunshine-Harmony-USB", "Packages", "0.5.9-usb.3", Guid.NewGuid().ToString("N"));
            string package = Extract(destination);
            if (extractOnly) return 0;
            string script = Path.Combine(package, "Install.ps1");
            ProcessStartInfo start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"));
            start.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";
            start.WorkingDirectory = package;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            using (Process child = Process.Start(start)) {
                child.WaitForExit();
                if (child.ExitCode != 0) {
                    string errorPath = Path.Combine(package, "installation-error.txt");
                    string details = File.Exists(errorPath) ? File.ReadAllText(errorPath, Encoding.UTF8) : "管理员授权被取消，或安装脚本未能完成。";
                    if (details.Length > 1800) details = details.Substring(0, 1800);
                    throw new InvalidOperationException(details + "\n\n安装文件保留在：" + package);
                }
            }
            MessageBox.Show("安装完成。\n\n请在 Sunshine 设备中心使用鸿蒙数据线模式。安装本身不会切换传输模式。\n\n恢复原面板时，可运行以下目录中的 Restore.ps1 或“恢复原版面板.bat”：\n" + package, "Sunshine 鸿蒙 USB 补丁", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        } catch (Exception error) {
            if (extractOnly) { Console.Error.WriteLine(error.Message); return 1; }
            MessageBox.Show(error.Message, "Sunshine 补丁安装未完成", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
