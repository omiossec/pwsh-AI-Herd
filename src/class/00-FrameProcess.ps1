<#
    Child process wrapper (compiled C#).

    The reader callbacks run on .NET thread-pool threads. PowerShell script blocks cannot run
    there (no runspace), so the pipe reading is kept entirely in C# and hands lines over to the
    UI thread through a thread-safe queue.

    The type name is checked first: Add-Type cannot define the same type twice in one session,
    so re-importing the module must not try to compile it again.
#>
if (-not ('FrameHost.FrameProcess' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;

namespace FrameHost
{
    public sealed class FrameProcess : IDisposable
    {
        private readonly Process _process;

        public ConcurrentQueue<string> Output { get; } = new ConcurrentQueue<string>();

        public FrameProcess(string fileName, string arguments)
        {
            _process = new Process();
            _process.StartInfo.FileName               = fileName;
            _process.StartInfo.Arguments              = arguments ?? string.Empty;
            _process.StartInfo.UseShellExecute        = false;
            _process.StartInfo.CreateNoWindow         = true;
            _process.StartInfo.RedirectStandardOutput = true;
            _process.StartInfo.RedirectStandardError  = true;
            _process.StartInfo.RedirectStandardInput  = true;

            _process.OutputDataReceived += (s, e) => { if (e.Data != null) { Output.Enqueue(e.Data); } };
            _process.ErrorDataReceived  += (s, e) => { if (e.Data != null) { Output.Enqueue("! " + e.Data); } };

            _process.Start();
            _process.BeginOutputReadLine();
            _process.BeginErrorReadLine();
        }

        public int  Id        { get { return _process.Id; } }
        public bool HasExited { get { return _process.HasExited; } }
        public int  ExitCode  { get { return _process.ExitCode; } }

        public void SendLine(string line)
        {
            if (!_process.HasExited)
            {
                _process.StandardInput.WriteLine(line);
                _process.StandardInput.Flush();
            }
        }

        public void Stop()
        {
            try
            {
                if (!_process.HasExited) { _process.Kill(entireProcessTree: true); }
            }
            catch (InvalidOperationException) { /* process already gone between the check and the kill */ }
        }

        public void Dispose()
        {
            Stop();
            _process.Dispose();
        }
    }
}
'@
}
