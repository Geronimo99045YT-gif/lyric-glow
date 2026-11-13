# Lyric Glow helper: per-app audio.
#   appaudio.ps1 list               -> JSON list of apps that have an audio session on the default output device
#   appaudio.ps1 capture <pid>      -> captures ONLY that app's audio (Windows "process loopback", Win10 2004+/Win11)
#                                      and prints one JSON line per ~30ms: {"b":[64 spectrum values 0-255]}
# Local only; nothing is recorded or sent anywhere, the audio is analysed into 64 numbers and thrown away.
param([string]$Mode = 'list', [int]$TargetPid = 0)
$ErrorActionPreference = 'Stop'

$src = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace LG {
  [ComImport, Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IActivateAudioInterfaceCompletionHandler { [PreserveSig] int ActivateCompleted(IActivateAudioInterfaceAsyncOperation op); }

  [ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IActivateAudioInterfaceAsyncOperation { [PreserveSig] int GetActivateResult(out int hr, [MarshalAs(UnmanagedType.IUnknown)] out object iface); }

  [ComImport, Guid("94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAgileObject { }

  [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioClient {
    [PreserveSig] int Initialize(int shareMode, int streamFlags, long hnsBufferDuration, long hnsPeriodicity, IntPtr pFormat, IntPtr sessionGuid);
    [PreserveSig] int GetBufferSize(out uint n);
    [PreserveSig] int GetStreamLatency(out long l);
    [PreserveSig] int GetCurrentPadding(out uint p);
    [PreserveSig] int IsFormatSupported(int shareMode, IntPtr fmt, out IntPtr closest);
    [PreserveSig] int GetMixFormat(out IntPtr fmt);
    [PreserveSig] int GetDevicePeriod(out long def, out long min);
    [PreserveSig] int Start();
    [PreserveSig] int Stop();
    [PreserveSig] int Reset();
    [PreserveSig] int SetEventHandle(IntPtr h);
    [PreserveSig] int GetService(ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object svc);
  }

  [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioCaptureClient {
    [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devPos, out ulong qpc);
    [PreserveSig] int ReleaseBuffer(uint frames);
    [PreserveSig] int GetNextPacketSize(out uint frames);
  }

  [ClassInterface(ClassInterfaceType.None)]
  class Handler : IActivateAudioInterfaceCompletionHandler, IAgileObject {
    public ManualResetEvent Done = new ManualResetEvent(false);
    public IActivateAudioInterfaceAsyncOperation Op;
    public int ActivateCompleted(IActivateAudioInterfaceAsyncOperation op) { Op = op; Done.Set(); return 0; }
  }

  static class Native {
    [DllImport("Mmdevapi.dll", ExactSpelling = true, PreserveSig = false)]
    public static extern void ActivateAudioInterfaceAsync([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid riid, IntPtr activationParams,
      IActivateAudioInterfaceCompletionHandler handler, out IActivateAudioInterfaceAsyncOperation op);
  }

  public static class Cap {
    const int N = 1024;
    public static void Run(uint pid) {
      Guid iidClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
      // PROPVARIANT (VT_BLOB) -> AUDIOCLIENT_ACTIVATION_PARAMS { type=PROCESS_LOOPBACK(1), pid, mode=INCLUDE_TARGET_PROCESS_TREE(0) }
      IntPtr prm = Marshal.AllocHGlobal(12);
      Marshal.WriteInt32(prm, 0, 1); Marshal.WriteInt32(prm, 4, (int)pid); Marshal.WriteInt32(prm, 8, 0);
      IntPtr pv = Marshal.AllocHGlobal(24);
      for (int i = 0; i < 24; i += 8) Marshal.WriteInt64(pv, i, 0);
      Marshal.WriteInt16(pv, 0, 65); Marshal.WriteInt32(pv, 8, 12); Marshal.WriteIntPtr(pv, 16, prm);

      Handler h = new Handler(); IActivateAudioInterfaceAsyncOperation op;
      Native.ActivateAudioInterfaceAsync("VAD\\Process_Loopback", ref iidClient, pv, h, out op);
      if (!h.Done.WaitOne(8000)) throw new Exception("activation timed out");
      int hr; object o; h.Op.GetActivateResult(out hr, out o);
      if (hr != 0) throw new Exception("activation failed 0x" + hr.ToString("X"));
      IAudioClient client = (IAudioClient)o;

      // 16-bit stereo 44.1k PCM
      IntPtr fmt = Marshal.AllocHGlobal(18);
      Marshal.WriteInt16(fmt, 0, 1); Marshal.WriteInt16(fmt, 2, 2); Marshal.WriteInt32(fmt, 4, 44100);
      Marshal.WriteInt32(fmt, 8, 176400); Marshal.WriteInt16(fmt, 12, 4); Marshal.WriteInt16(fmt, 14, 16); Marshal.WriteInt16(fmt, 16, 0);
      // try the stream-flag combinations that different Windows builds accept (LOOPBACK 0x20000, EVENTCALLBACK 0x40000, NOPERSIST 0x80000)
      int[] tries = new int[] { 0x00020000 | 0x00040000 | 0x00080000, 0x00020000 | 0x00040000, 0x00020000 | 0x00080000, 0x00020000,
        unchecked((int)0x80000000) | 0x08000000 | 0x00020000 | 0x00040000, unchecked((int)0x80000000) | 0x08000000 | 0x00020000 };
      int r = -1, used = 0; string tried = "";
      foreach (int fl in tries) {
        r = client.Initialize(0, fl, 200000, 0, fmt, IntPtr.Zero);
        tried += fl.ToString("X") + "=" + r.ToString("X") + " ";
        if (r == 0) { used = fl; break; }
      }
      if (r != 0) throw new Exception("Initialize failed for every flag combo: " + tried);
      AutoResetEvent evt = new AutoResetEvent(false);
      if ((used & 0x00040000) != 0) {
        r = client.SetEventHandle(evt.SafeWaitHandle.DangerousGetHandle());
        if (r != 0) throw new Exception("SetEventHandle failed 0x" + r.ToString("X"));
      }
      Guid iidCap = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"); object co;
      r = client.GetService(ref iidCap, out co);
      if (r != 0) throw new Exception("GetService failed 0x" + r.ToString("X"));
      IAudioCaptureClient cap = (IAudioCaptureClient)co;
      r = client.Start();
      if (r != 0) throw new Exception("Start failed 0x" + r.ToString("X"));

      float[] ring = new float[N]; int w = 0, since = 0;
      double[] re = new double[N], im = new double[N], win = new double[N];
      for (int i = 0; i < N; i++) win[i] = 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (N - 1));
      int[] edge = new int[65];
      for (int i = 0; i <= 64; i++) edge[i] = (int)Math.Pow(400.0, i / 64.0);
      double[] bands = new double[64];
      DateTime lastEmit = DateTime.UtcNow;

      while (true) {
        evt.WaitOne(60);
        uint pk;
        while (cap.GetNextPacketSize(out pk) == 0 && pk > 0) {
          IntPtr data; uint frames, flags; ulong dp, qpc;
          if (cap.GetBuffer(out data, out frames, out flags, out dp, out qpc) != 0) break;
          bool silent = (flags & 2) != 0;
          for (uint f = 0; f < frames; f++) {
            float s = 0;
            if (!silent) {
              short l = Marshal.ReadInt16(data, (int)f * 4), rr = Marshal.ReadInt16(data, (int)f * 4 + 2);
              s = (l + rr) / 65536f;
            }
            ring[w] = s; w = (w + 1) & (N - 1); since++;
            if (since >= 1470) { since = 0; Analyse(ring, w, re, im, win, edge, bands); Emit(bands); lastEmit = DateTime.UtcNow; }
          }
          cap.ReleaseBuffer(frames);
        }
        if ((DateTime.UtcNow - lastEmit).TotalMilliseconds > 70) { // nothing playing: let the bars fall
          for (int i = 0; i < 64; i++) bands[i] *= 0.8;
          Emit(bands); lastEmit = DateTime.UtcNow;
        }
      }
    }

    static void Analyse(float[] ring, int w, double[] re, double[] im, double[] win, int[] edge, double[] bands) {
      for (int i = 0; i < N; i++) { re[i] = ring[(w + i) & (N - 1)] * win[i]; im[i] = 0; }
      for (int i = 1, j = 0; i < N; i++) { // bit reversal
        int bit = N >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit;
        if (i < j) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
      }
      for (int len = 2; len <= N; len <<= 1) {
        double ang = -2 * Math.PI / len, wr = Math.Cos(ang), wi = Math.Sin(ang);
        for (int i = 0; i < N; i += len) {
          double cr = 1, ci = 0;
          for (int k = 0; k < len / 2; k++) {
            int a = i + k, b = i + k + len / 2;
            double xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
            re[b] = re[a] - xr; im[b] = im[a] - xi; re[a] += xr; im[a] += xi;
            double nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr;
          }
        }
      }
      for (int b = 0; b < 64; b++) {
        int lo = Math.Max(1, edge[b]), hi = Math.Max(lo + 1, edge[b + 1]); double m = 0;
        for (int k = lo; k < hi && k < N / 2; k++) { double mag = Math.Sqrt(re[k] * re[k] + im[k] * im[k]); if (mag > m) m = mag; }
        double db = 20 * Math.Log10(m / (N / 4.0) + 1e-7), v = (db + 100) / 70; // same dB window Web Audio uses
        if (v < 0) v = 0; if (v > 1) v = 1;
        bands[b] = bands[b] * 0.45 + v * 255 * 0.55;
      }
    }

    static void Emit(double[] bands) {
      StringBuilder sb = new StringBuilder("{\"b\":[");
      for (int i = 0; i < 64; i++) { if (i > 0) sb.Append(','); sb.Append((int)bands[i]); }
      sb.Append("]}");
      Console.Out.WriteLine(sb.ToString()); Console.Out.Flush();
    }
  }

  // ---- list apps that currently have an audio session on the default output device ----
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCom { }
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IntPtr devs);
    [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, [MarshalAs(UnmanagedType.IUnknown)] out object dev);
  }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
  [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionManager2 {
    [PreserveSig] int GetAudioSessionControl(IntPtr a, int b, out IntPtr c);
    [PreserveSig] int GetSimpleAudioVolume(IntPtr a, int b, out IntPtr c);
    [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator e);
  }
  [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionEnumerator {
    [PreserveSig] int GetCount(out int n);
    [PreserveSig] int GetSession(int i, [MarshalAs(UnmanagedType.IUnknown)] out object s);
  }
  [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionControl2 {
    [PreserveSig] int GetState(out int s);
    [PreserveSig] int GetDisplayName(out IntPtr n);
    [PreserveSig] int SetDisplayName(IntPtr n, ref Guid c);
    [PreserveSig] int GetIconPath(out IntPtr p);
    [PreserveSig] int SetIconPath(IntPtr p, ref Guid c);
    [PreserveSig] int GetGroupingParam(out Guid g);
    [PreserveSig] int SetGroupingParam(ref Guid g, ref Guid c);
    [PreserveSig] int RegisterAudioSessionNotification(IntPtr n);
    [PreserveSig] int UnregisterAudioSessionNotification(IntPtr n);
    [PreserveSig] int GetSessionIdentifier(out IntPtr id);
    [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
    [PreserveSig] int GetProcessId(out uint pid);
    [PreserveSig] int IsSystemSoundsSession();
    [PreserveSig] int SetDuckingPreferences(bool opt);
  }

  public static class Sessions {
    public static string List() {
      StringBuilder sb = new StringBuilder();
      IMMDeviceEnumerator en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
      object dev; if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0) return "";
      Guid iid = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"); object mgr;
      if (((IMMDevice)dev).Activate(ref iid, 23, IntPtr.Zero, out mgr) != 0) return "";
      IAudioSessionEnumerator se; ((IAudioSessionManager2)mgr).GetSessionEnumerator(out se);
      int n; se.GetCount(out n);
      for (int i = 0; i < n; i++) {
        object s; if (se.GetSession(i, out s) != 0) continue;
        IAudioSessionControl2 c = (IAudioSessionControl2)s; uint pid; int state;
        if (c.GetProcessId(out pid) != 0 || pid == 0) continue;
        c.GetState(out state);
        if (state == 2) continue; // expired
        sb.Append(pid).Append('|').Append(state).Append('\n');
      }
      return sb.ToString();
    }
  }
}
'@

Add-Type -TypeDefinition $src -Language CSharp

if ($Mode -eq 'list') {
  $rows = @()
  foreach ($line in ([LG.Sessions]::List() -split "`n")) {
    if (-not $line.Trim()) { continue }
    $p = $line.Trim().Split('|')
    $proc = Get-Process -Id ([int]$p[0]) -ErrorAction SilentlyContinue
    if ($proc) { $rows += [pscustomobject]@{ pid = [int]$p[0]; name = $proc.ProcessName; active = ([int]$p[1] -eq 1) } }
  }
  ConvertTo-Json -InputObject @($rows) -Compress
} elseif ($Mode -eq 'capture') {
  [LG.Cap]::Run([uint32]$TargetPid)
}
