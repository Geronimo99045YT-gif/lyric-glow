# Lyric Glow helper: prints what Windows says is playing (title/artist/position) as one JSON line per second,
# and carries out play/pause/next/previous when the app drops a command into %TEMP%\lyricglow_cmd.txt.
# Reads the same "media controls" info as the volume flyout. Local only, nothing is sent anywhere.
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) { $m = $asTask.MakeGenericMethod($type); $t = $m.Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
$mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
$cmdFile = Join-Path $env:TEMP 'lyricglow_cmd.txt'
$limit = if ($args.Count) { [int]$args[0] } else { -1 }
$n = 0
$tick = 0
$emit = $true
while ($limit -lt 0 -or $n -lt $limit) {
  # commands are checked every 250 ms so buttons feel instant
  if (Test-Path $cmdFile) {
    $c = (Get-Content $cmdFile -Raw).Trim(); Remove-Item $cmdFile -Force
    try {
      $s = $mgr.GetCurrentSession()
      if ($s) {
        switch ($c) {
          'playpause' { [void](Await ($s.TryTogglePlayPauseAsync()) ([bool])) }
          'play'      { [void](Await ($s.TryPlayAsync()) ([bool])) }
          'pause'     { [void](Await ($s.TryPauseAsync()) ([bool])) }
          'next'      { [void](Await ($s.TrySkipNextAsync()) ([bool])) }
          'prev'      { [void](Await ($s.TrySkipPreviousAsync()) ([bool])) }
        }
      }
    } catch {}
    $emit = $true; Start-Sleep -Milliseconds 150 # give the player a moment, then report the new state straight away
  }
  if ($emit -or $tick -ge 4) {
    $tick = 0; $emit = $false; $n++
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
  }
  $tick++
  Start-Sleep -Milliseconds 250
}
