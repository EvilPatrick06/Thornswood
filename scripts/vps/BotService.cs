// BotService.cs
//
// The Windows service that keeps the Thornswood bot running on the VPS
// (issue #465). Install-Bot.ps1 builds it there with the .NET Framework's own
// csc (Bot-Service.ps1, Build-ThornswoodBotHost) and registers it as the
// service ThornswoodBot, running as NT SERVICE\ThornswoodBot.
//
// WHAT IT REPLACES. The bot ran as SYSTEM, the account that holds every
// secret on the box, under run.ps1: a PowerShell loop in a scheduled task that
// started python through cmd's >> redirection. Nothing could stop it by name:
// stopping the task left python running, so every script that restarted the
// bot killed python by its command line. The log only rolled between runs,
// because cmd held bot.log open for as long as python ran.
//
// WHAT IT DOES.
//   Runs python bot.py in the bot's folder, with the settings in bot.env.json
//   as its environment. Python is named in host.json beside this program, by
//   its full path, so the service does not depend on the PATH it was booted
//   with.
//   Writes python's output to bot.log itself, byte for byte, in the bot's
//   data folder (data under the bot's folder unless host.json names another,
//   issue #1104), and rolls it by
//   size while the bot runs: at 4 MB bot.log becomes bot.log.1, what was .1
//   becomes .2, five kept. The same rule as Roll-Log.ps1 and the site's log.
//   And by age (#2166): bot.log is rolled once its first line is 30 days old,
//   and a rolled copy is deleted once its last write is 59 days old, checked
//   once an hour and at each write, so no line of it reaches 90 days.
//   Nothing re-encodes the text on the way, which is what went wrong when
//   run.ps1 piped it through PowerShell before 16 September.
//   Starts python again when it exits: 15 seconds after a run that lasted,
//   longer after quick ones, and after three quick exits in a row it stops
//   and says why in bot.log, the same line run.ps1 wrote. The watchdog
//   (Watch-Services.ps1) then starts the service again by its name, at most
//   three times an hour.
//   Puts python in a job object, so stopping the service stops python and
//   anything python started, and nothing is left holding the token.
//   Writes each exit and each give-up to the Application event log, under the
//   source ThornswoodBot, when that source is registered (Install-Bot does).
//
// .NET Framework 4 and C# 5, the same compiler as the launcher, so it builds
// on any Windows Server with nothing installed.
//
//   ThornswoodBotService.exe             as the service
//   ThornswoodBotService.exe --console   in the foreground, until a line or
//                                        the end arrives on standard input;
//                                        tests\test-bot-service.ps1 runs it so

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace Thornswood
{
    // host.json beside the program, written by Install-Bot. Only root and
    // python are ever set on the VPS; the rest are there so a test can run the
    // same rules in seconds rather than minutes.
    public class BotSettings
    {
        public string Root;
        // Where bot.log and the bot's records go (issue #1104): the one
        // folder the service's account may write. python is told it in
        // THORNSWOOD_BOT_DATA. data under Root unless host.json says.
        public string Data;
        public string Python;
        public string Script = "bot.py";
        public int FastSeconds = 30;
        public int PauseSeconds = 15;
        public long MaxBytes = 4L * 1024 * 1024;
        public int Keep = 5;
        public int RetrySeconds = 30;
        // By age (#2166): the live file rolls once its first line is this
        // old, a rolled copy goes once its last write is that old, looked at
        // every AgeCheckSeconds. Settable in host.json for a test only.
        public double LiveSeconds = 30 * 86400;
        public double CopySeconds = 59 * 86400;
        public double AgeCheckSeconds = 3600;
        public string Problem = "";

        public static BotSettings Load(string exeDir)
        {
            BotSettings s = new BotSettings();
            // The program sits in <bot folder>\service, so the bot's folder is
            // one up unless host.json says otherwise.
            s.Root = Path.GetDirectoryName(exeDir.TrimEnd('\\', '/'));
            string file = Path.Combine(exeDir, "host.json");
            try
            {
                IDictionary d = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(file)) as IDictionary;
                if (d == null) { s.Problem = file + " does not hold a JSON object"; return s; }
                if (d.Contains("root")) s.Root = Convert.ToString(d["root"], CultureInfo.InvariantCulture);
                if (d.Contains("data")) s.Data = Convert.ToString(d["data"], CultureInfo.InvariantCulture);
                if (d.Contains("python")) s.Python = Convert.ToString(d["python"], CultureInfo.InvariantCulture);
                if (d.Contains("script")) s.Script = Convert.ToString(d["script"], CultureInfo.InvariantCulture);
                if (d.Contains("fastSeconds")) s.FastSeconds = Convert.ToInt32(d["fastSeconds"], CultureInfo.InvariantCulture);
                if (d.Contains("pauseSeconds")) s.PauseSeconds = Convert.ToInt32(d["pauseSeconds"], CultureInfo.InvariantCulture);
                if (d.Contains("maxBytes")) s.MaxBytes = Convert.ToInt64(d["maxBytes"], CultureInfo.InvariantCulture);
                if (d.Contains("keep")) s.Keep = Convert.ToInt32(d["keep"], CultureInfo.InvariantCulture);
                if (d.Contains("retrySeconds")) s.RetrySeconds = Convert.ToInt32(d["retrySeconds"], CultureInfo.InvariantCulture);
                if (d.Contains("liveSeconds")) s.LiveSeconds = Convert.ToDouble(d["liveSeconds"], CultureInfo.InvariantCulture);
                if (d.Contains("copySeconds")) s.CopySeconds = Convert.ToDouble(d["copySeconds"], CultureInfo.InvariantCulture);
                if (d.Contains("ageCheckSeconds")) s.AgeCheckSeconds = Convert.ToDouble(d["ageCheckSeconds"], CultureInfo.InvariantCulture);
            }
            catch (Exception e) { s.Problem = "cannot read " + file + ": " + e.Message; }
            if (String.IsNullOrEmpty(s.Data)) s.Data = Path.Combine(s.Root, "data");
            if (s.Keep < 1) s.Keep = 1;
            if (s.Problem == "" && String.IsNullOrEmpty(s.Python)) s.Problem = file + " names no python";
            return s;
        }
    }

    // bot.log, written by this program and rolled by size while the bot runs.
    // Opened so that anybody may read it, and rename or delete it, at the same
    // time: Show-BotLog.ps1 and Install-Bot's read-back open it while the bot
    // writes. A reader that did not allow deleting holds the rename up, so a
    // roll that cannot happen is left for RetrySeconds, and the older files are
    // not moved round a file that cannot move, which is Roll-Log's rule too.
    //
    // BY AGE (#2166). python's lines carry no time this program can trust, so
    // the age of the live file is when it was begun: its creation time, set
    // to now whenever an empty file is opened, because Windows hands a file
    // made again under a name renamed a moment ago the old file's creation
    // time (file tunnelling) and the roll would then think the new file as
    // old as the last. Begun is never later than the first line, so the
    // file rolls no later than its first line is liveSeconds old. A rolled
    // copy goes once its last write is copySeconds old; a rename keeps that
    // time, so .1 to .5 age by when each stopped being written.
    public class RollingLog : IDisposable
    {
        readonly object sync = new object();
        readonly string path;
        readonly long maxBytes;
        readonly int keep;
        readonly int retrySeconds;
        double liveSeconds;
        double copySeconds;
        FileStream stream;
        DateTime begun = DateTime.UtcNow;
        DateTime nextTry = DateTime.MinValue;
        bool saidHeld;
        Timer ager;

        public RollingLog(string path, long maxBytes, int keep, int retrySeconds)
        {
            this.path = path;
            this.maxBytes = maxBytes;
            this.keep = keep;
            this.retrySeconds = retrySeconds;
            Open();
        }

        public string Path { get { return path; } }

        // Turns the age rule on: once now, then every checkSeconds.
        public void AgeBy(double liveSeconds, double copySeconds, double checkSeconds)
        {
            lock (sync)
            {
                this.liveSeconds = liveSeconds;
                this.copySeconds = copySeconds;
            }
            Age();
            long every = (long)(Math.Max(1, checkSeconds) * 1000);
            ager = new Timer(delegate (object o) { Age(); }, null, every, every);
        }

        void Open()
        {
            stream = new FileStream(path, FileMode.Append, FileAccess.Write,
                FileShare.ReadWrite | FileShare.Delete, 4096, FileOptions.None);
            begun = DateTime.UtcNow;
            try
            {
                if (stream.Length == 0) File.SetCreationTimeUtc(path, begun);
                else begun = File.GetCreationTimeUtc(path);
            }
            catch (Exception) { }
        }

        bool Old()
        {
            return liveSeconds > 0 && stream != null && stream.Length > 0 &&
                (DateTime.UtcNow - begun).TotalSeconds >= liveSeconds;
        }

        public void Write(byte[] data, int count)
        {
            lock (sync)
            {
                if (stream == null) return;
                stream.Write(data, 0, count);
                stream.Flush();
                if ((stream.Length >= maxBytes || Old()) && DateTime.UtcNow >= nextTry) Roll();
            }
        }

        // The hourly pass: rolled copies past copySeconds deleted, and the
        // live file rolled once it is old. Each delete that fails is a line
        // in bot.log, tried again on the next pass.
        public void Age()
        {
            lock (sync)
            {
                if (stream == null || copySeconds <= 0) return;
                List<string> said = new List<string>();
                int gone = 0;
                for (int i = 1; i <= keep; i++)
                {
                    string f = path + "." + i;
                    try
                    {
                        if (!File.Exists(f)) continue;
                        if ((DateTime.UtcNow - File.GetLastWriteTimeUtc(f)).TotalSeconds < copySeconds) continue;
                        File.Delete(f);
                        gone++;
                    }
                    catch (Exception e) { said.Add("[run] could not delete " + System.IO.Path.GetFileName(f) + " by age: " + e.Message + ". Trying again within the hour."); }
                }
                if (gone > 0) said.Insert(0, "[run] by age: " + gone + " rolled bot.log cop" + (gone == 1 ? "y" : "ies") + " past " + (copySeconds / 86400).ToString("0.##", CultureInfo.InvariantCulture) + " days deleted");
                foreach (string l in said)
                {
                    byte[] b = new UTF8Encoding(false).GetBytes(l + "\r\n");
                    stream.Write(b, 0, b.Length);
                }
                stream.Flush();
                if (Old() && DateTime.UtcNow >= nextTry) Roll();
            }
        }

        public void Line(string text)
        {
            byte[] b = new UTF8Encoding(false).GetBytes(text + "\r\n");
            Write(b, b.Length);
        }

        // At start, a log already past the line is rolled before anything is
        // written, so each start after a long quiet run has a file of its own.
        public void RollIfFull()
        {
            lock (sync)
            {
                if (stream != null && stream.Length >= maxBytes) Roll();
            }
        }

        void Roll()
        {
            stream.Dispose();
            stream = null;
            bool held = false;
            try
            {
                // Asked first, the way Roll-Log.ps1 asks: held means leave
                // every file where it is.
                using (FileStream probe = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { }
            }
            catch (IOException) { held = true; }
            catch (UnauthorizedAccessException) { held = true; }
            string why = "";
            if (!held)
            {
                try
                {
                    string oldest = path + "." + keep;
                    if (File.Exists(oldest)) File.Delete(oldest);
                    for (int i = keep - 1; i >= 1; i--)
                    {
                        string a = path + "." + i;
                        if (File.Exists(a)) File.Move(a, path + "." + (i + 1));
                    }
                    File.Move(path, path + ".1");
                    saidHeld = false;
                }
                catch (Exception e) { why = e.Message; }
            }
            Open();
            if (held || why != "")
            {
                nextTry = DateTime.UtcNow.AddSeconds(retrySeconds);
                if (!saidHeld)
                {
                    saidHeld = true;
                    string m = held ? "something else has it open" : why;
                    byte[] b = new UTF8Encoding(false).GetBytes("[run] bot.log is past " + maxBytes + " bytes or its first line is past its days, and could not be rolled yet, " + m + ". Trying again in " + retrySeconds + " seconds.\r\n");
                    stream.Write(b, 0, b.Length);
                    stream.Flush();
                }
            }
        }

        public void Dispose()
        {
            if (ager != null) { ager.Dispose(); ager = null; }
            lock (sync)
            {
                if (stream != null) stream.Dispose();
                stream = null;
            }
        }
    }

    // A job object that ends everything in it when it is closed or ended.
    public class KillJob : IDisposable
    {
        [StructLayout(LayoutKind.Sequential)]
        struct BasicLimits
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct IoCounters
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct ExtendedLimits
        {
            public BasicLimits Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        const int ExtendedLimitInformation = 9;
        const uint KillOnJobClose = 0x2000;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimits info, int length);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr handle);

        IntPtr handle;

        public KillJob()
        {
            handle = CreateJobObject(IntPtr.Zero, null);
            if (handle == IntPtr.Zero) return;
            ExtendedLimits info = new ExtendedLimits();
            info.Basic.LimitFlags = KillOnJobClose;
            if (!SetInformationJobObject(handle, ExtendedLimitInformation, ref info, Marshal.SizeOf(typeof(ExtendedLimits))))
            {
                CloseHandle(handle);
                handle = IntPtr.Zero;
            }
        }

        // False when the process could not be put in the job; then only the
        // process itself can be stopped, not anything it started.
        public bool Add(Process p)
        {
            return handle != IntPtr.Zero && AssignProcessToJobObject(handle, p.Handle);
        }

        public void End()
        {
            if (handle != IntPtr.Zero) TerminateJobObject(handle, 1);
        }

        public void Dispose()
        {
            if (handle != IntPtr.Zero) CloseHandle(handle);
            handle = IntPtr.Zero;
        }
    }

    // The loop run.ps1 was, with a stop that works.
    public class BotRunner
    {
        readonly BotSettings s;
        readonly RollingLog log;
        readonly ManualResetEvent stopping = new ManualResetEvent(false);
        readonly object procSync = new object();
        Process current;
        KillJob job;

        // Where a line for the Windows event log goes: text, type, event id.
        public Action<string, EventLogEntryType, int> Event = delegate { };

        public BotRunner(BotSettings s, RollingLog log)
        {
            this.s = s;
            this.log = log;
        }

        public RollingLog Log { get { return log; } }

        static string Me()
        {
            try { return WindowsIdentity.GetCurrent().Name; }
            catch (Exception e) { return "an account this could not name (" + e.Message + ")"; }
        }

        // bot.env.json as a table, or null and why not.
        Dictionary<string, string> ReadEnv(string file, out string why)
        {
            why = "";
            try
            {
                IDictionary d = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(file)) as IDictionary;
                if (d == null) { why = "it does not hold a JSON object"; return null; }
                Dictionary<string, string> env = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (DictionaryEntry e in d)
                {
                    if (e.Value == null) continue;
                    env[Convert.ToString(e.Key, CultureInfo.InvariantCulture)] = Convert.ToString(e.Value, CultureInfo.InvariantCulture);
                }
                return env;
            }
            catch (Exception e) { why = e.Message; return null; }
        }

        // 0 once stopped or given up, 1 when it could not start the bot at all.
        public int Run()
        {
            string envFile = Path.Combine(s.Root, "bot.env.json");
            log.RollIfFull();
            log.Line("[run] the Thornswood Bot service started, running as " + Me());
            if (s.Problem != "")
            {
                log.Line("[run] " + s.Problem + ". Not starting the bot. Install-Bot.ps1 writes that file.");
                Event("The bot was not started: " + s.Problem + ".", EventLogEntryType.Error, 3);
                return 1;
            }
            int fastRuns = 0;
            while (!stopping.WaitOne(0))
            {
                // Read every start, so a new token or setting needs a restart
                // and nothing more.
                string why;
                Dictionary<string, string> env = ReadEnv(envFile, out why);
                if (env == null)
                {
                    log.Line("[run] cannot read " + envFile + ": " + why);
                    log.Line("[run] running as " + Me());
                    Event("The bot was not started: it cannot read " + envFile + ". " + why, EventLogEntryType.Error, 3);
                    return 1;
                }
                string token;
                if (!env.TryGetValue("DISCORD_TOKEN", out token) || token.Trim() == "")
                {
                    log.Line("[run] bot.env.json has no DISCORD_TOKEN in it");
                    Event("The bot was not started: bot.env.json has no DISCORD_TOKEN in it.", EventLogEntryType.Error, 3);
                    return 1;
                }

                Stopwatch clock = Stopwatch.StartNew();
                int code = RunOnce(env);
                if (stopping.WaitOne(0)) break;
                double took = clock.Elapsed.TotalSeconds;
                if (took < s.FastSeconds) fastRuns++; else fastRuns = 0;
                if (fastRuns >= 3)
                {
                    // Word for word what run.ps1 wrote, which Install-Bot,
                    // Write-BotToken and Show-BotLog look for.
                    log.Line("[run] the bot stopped within " + s.FastSeconds + " seconds three times running, the last time with exit code " + code + ". Not starting it again. The reason is in the lines above.");
                    Event("The bot stopped within " + s.FastSeconds + " seconds three times running, the last time with exit code " + code + ". The service has stopped. The reason is in bot.log.", EventLogEntryType.Error, 3);
                    return 0;
                }
                int pause = s.PauseSeconds * (1 << fastRuns);
                log.Line("[run] the bot exited with code " + code + " after " + Math.Round(took) + " seconds. Starting it again in " + pause + " seconds.");
                Event("The bot exited with code " + code + " after " + Math.Round(took) + " seconds. The service starts it again in " + pause + " seconds.", EventLogEntryType.Warning, 2);
                if (stopping.WaitOne(pause * 1000)) break;
            }
            return 0;
        }

        static string Quote(string a)
        {
            return "\"" + a.Replace("\"", "\\\"") + "\"";
        }

        // One run of python, to its exit. Its exit code, or -1 when it did not
        // start at all.
        int RunOnce(Dictionary<string, string> env)
        {
            ProcessStartInfo psi = new ProcessStartInfo(s.Python, Quote(Path.Combine(s.Root, s.Script)));
            psi.WorkingDirectory = s.Root;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            foreach (KeyValuePair<string, string> kv in env) psi.EnvironmentVariables[kv.Key] = kv.Value;
            psi.EnvironmentVariables["THORNSWOOD_BOT_DATA"] = s.Data;
            if (String.IsNullOrEmpty(psi.EnvironmentVariables["PYTHONIOENCODING"])) psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            // The libraries Install-Bot put beside the code. The swap puts this folder
            // back with the code, so a rollback runs the old versions.
            psi.EnvironmentVariables["PYTHONPATH"] = Path.Combine(s.Root, "py-libs");
            // Python's own folders first, then the machine's PATH as it is
            // now rather than as it was when the box booted.
            string pyDir = Path.GetDirectoryName(s.Python);
            string machine = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.Machine) ?? "";
            psi.EnvironmentVariables["PATH"] = pyDir + ";" + Path.Combine(pyDir, "Scripts") + ";" + machine;

            Process p = new Process();
            p.StartInfo = psi;
            KillJob j = new KillJob();
            lock (procSync)
            {
                if (stopping.WaitOne(0)) { j.Dispose(); return 0; }
                try { p.Start(); }
                catch (Exception e)
                {
                    j.Dispose();
                    log.Line("[run] could not start " + s.Python + ": " + e.Message);
                    return -1;
                }
                if (!j.Add(p)) log.Line("[run] python could not be put in a job, so stopping the service stops python but not anything python started");
                current = p;
                job = j;
            }
            log.Line("[run] started the bot, pid " + p.Id + ", with " + s.Python);
            try { p.StandardInput.Close(); }
            catch (Exception e) { log.Line("[run] could not close python's standard input: " + e.Message); }
            Thread o = Pump(p.StandardOutput.BaseStream);
            Thread r = Pump(p.StandardError.BaseStream);
            p.WaitForExit();
            // A child of python's could hold the pipes open after python has
            // gone; ending the job ends it, so the pumps finish.
            lock (procSync) { j.End(); }
            o.Join(10000);
            r.Join(10000);
            int code = p.ExitCode;
            lock (procSync)
            {
                current = null;
                job = null;
                j.Dispose();
            }
            p.Dispose();
            return code;
        }

        Thread Pump(Stream from)
        {
            Thread t = new Thread(delegate ()
            {
                byte[] buf = new byte[8192];
                try
                {
                    int n;
                    while ((n = from.Read(buf, 0, buf.Length)) > 0) log.Write(buf, n);
                }
                catch (Exception e) { log.Line("[run] stopped reading python's output: " + e.Message); }
            });
            t.IsBackground = true;
            t.Start();
            return t;
        }

        // Ends python and everything it started, and the loop with it.
        public void Stop()
        {
            stopping.Set();
            lock (procSync)
            {
                if (job != null) job.End();
                if (current != null)
                {
                    try { if (!current.HasExited) current.Kill(); }
                    catch (Exception e) { log.Line("[run] could not stop python: " + e.Message); }
                }
            }
        }
    }

    public class BotService : ServiceBase
    {
        public const string Name = "ThornswoodBot";
        readonly BotRunner runner;
        Thread worker;
        volatile bool windowsStopped;

        public BotService(BotRunner runner)
        {
            this.runner = runner;
            ServiceName = Name;
            CanStop = true;
            CanShutdown = true;
            AutoLog = true;
        }

        protected override void OnStart(string[] args)
        {
            worker = new Thread(Work);
            worker.IsBackground = true;
            worker.Start();
        }

        void Work()
        {
            runner.Run();
            if (windowsStopped) return;
            // The bot gave up by itself: the service says so by stopping,
            // from a thread of its own, because Stop waits for this one.
            Thread t = new Thread(delegate ()
            {
                try { Stop(); }
                catch (Exception e) { runner.Log.Line("[run] the service could not stop itself: " + e.Message); }
            });
            t.Start();
        }

        protected override void OnStop()
        {
            windowsStopped = true;
            RequestAdditionalTime(30000);
            runner.Stop();
            if (worker != null && worker != Thread.CurrentThread) worker.Join(25000);
            runner.Log.Line("[run] stopped by Windows");
        }

        protected override void OnShutdown()
        {
            OnStop();
        }
    }

    public static class Program
    {
        public static int Main(string[] args)
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            BotSettings s = BotSettings.Load(exeDir);
            bool console = Array.IndexOf(args, "--console") >= 0;
            // Made here when it is missing, which only a run by hand meets:
            // Install-Bot makes it and grants the account Modify on it.
            try { Directory.CreateDirectory(s.Data); } catch (Exception) { }
            RollingLog log = new RollingLog(Path.Combine(s.Data, "bot.log"), s.MaxBytes, s.Keep, s.RetrySeconds);
            log.AgeBy(s.LiveSeconds, s.CopySeconds, s.AgeCheckSeconds);
            BotRunner runner = new BotRunner(s, log);
            if (console)
            {
                runner.Event = delegate (string m, EventLogEntryType t, int id) { Console.WriteLine("event " + id + " " + t + ": " + m); };
                Thread stopper = new Thread(delegate ()
                {
                    Console.In.ReadLine();
                    runner.Stop();
                });
                stopper.IsBackground = true;
                stopper.Start();
                int rc = runner.Run();
                log.Line("[run] stopped");
                log.Dispose();
                return rc;
            }
            bool saidNoEvents = false;
            runner.Event = delegate (string m, EventLogEntryType t, int id)
            {
                // Only once Install-Bot has registered the source; a service
                // account cannot register one itself. Said once, not per exit.
                try { EventLog.WriteEntry(BotService.Name, m, t, id); }
                catch (Exception e)
                {
                    if (!saidNoEvents) log.Line("[run] could not write to the event log, so exits are in this file only: " + e.Message);
                    saidNoEvents = true;
                }
            };
            ServiceBase.Run(new BotService(runner));
            log.Dispose();
            return 0;
        }
    }
}
