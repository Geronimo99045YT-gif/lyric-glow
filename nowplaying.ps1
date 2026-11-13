# Lyric Glow helper: prints what Windows says is playing (title/artist/position) as one JSON line per second.
# Reads the same "media controls" info as the volume flyout. Local only, nothing is sent anywhere.
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) { $m = $asTask.MakeGenericMethod($type); $t = $m.Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
$mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
$limit = if ($args.Count) { [int]$args[0] } else { -1 }
$n = 0
while ($limit -lt 0 -or $n -lt $limit) {
  $n++
  $out = @{ playing = $false }
  try {
    $s = $mgr.GetCurrentSession()
    if ($s) {
      $p = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
      $tl = $s.GetTimelineProperties(); $pb = $s.GetPlaybackInfo()
      $isP = ($pb.PlaybackStatus -eq 'Playing')
      $dur = $tl.EndTime.TotalSeconds - $tl.StartTime.TotalSeconds
      $pos = $tl.Position.TotalSeconds
      $age = ([DateTimeOffset]::Now - $tl.LastUpdatedTime).TotalSeconds
      if ($isP) { $pos += $age }
      # some apps (browsers) don't report a usable timeline: mark position unknown
      if ($dur -le 0 -or $age -lt 0 -or $age -gt ($dur + 5) -or $pos -gt ($dur + 5)) { $pos = -1 }
      $out = @{ ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds(); title = $p.Title; artist = $p.Artist; album = $p.AlbumTitle; playing = $isP; pos = [math]::Round($pos, 2); dur = [math]::Round($dur, 2); app = $s.SourceAppUserModelId }
    }
  } catch {}
  [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress)); [Console]::Out.Flush()
  Start-Sleep -Milliseconds 1000
}
