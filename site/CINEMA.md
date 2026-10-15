# Cinema assets

WEB-03 produces a still and a silent looping studio shot of the catalog Jensen Das Ugly Stik 60. Both use the native `res://render/airplane.gd` builder for `jensen-das-ugly-stik-60`; the aircraft geometry and materials are unchanged. This is a studio presentation, not gameplay or flight validation.

The render uses the site's `#101820` background, a perspective three-quarter view, and warm key, cool fill, and blue rim lights. The poster is 1600×1000 WebP. The MP4 is 1280×800 H.264, 24 fps, 12 seconds, with no audio. Its camera follows a phase-shifted cosine orbit around world Y, with a ±12° yaw around the 40° base azimuth. The first video frame matches the poster angle and the loop returns to that angle without a duplicated endpoint.

`assets/cinema/cinema.json` records the Godot engine and renderer, camera and lights, source-file SHA-256 values, source-tree digest, encoder settings, and output sizes and hashes. The committed poster is 45,754 bytes; the MP4 is 730,574 bytes. The captured MP4 is under 1 MB.

## Rebuild

Use Pillow 12.3.0 and FFmpeg with `libx264`. The checked render used Godot 4.7.2 stable, the Compatibility renderer, and FFmpeg 9.0.2 essentials build from [the Windows builds linked by FFmpeg](https://ffmpeg.org/download.html#build-windows). Its archive SHA-256 was `4705843ccaaf54257c16ad90f3e952ece33c17df964ecf7bfdbb0f49c7171077`.

From the repository root in PowerShell:

```powershell
$godot = Join-Path $PWD '.tools\Godot_v4.7.2-stable_win64_console.exe'
$script = (Resolve-Path 'site/capture_cinema.gd').Path
$render = Join-Path $env:TEMP 'openrc-cinema'
New-Item -ItemType Directory -Path $render -Force | Out-Null

foreach ($captureMode in @('poster', 'video')) {
    $stdout = Join-Path $render "godot-$captureMode.stdout.log"
    $stderr = Join-Path $render "godot-$captureMode.stderr.log"
    $arguments = @('--path', 'app', '--script', $script, '--', "--mode=$captureMode", "--out-dir=$render")
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($process.ExitCode -ne 0) { throw "Godot cinema capture failed for $captureMode; see $stderr" }
}

python site/package_cinema.py --capture-dir $render --ffmpeg 'C:\path\to\ffmpeg.exe'
```

Omit `--ffmpeg` when FFmpeg is on `PATH`. The capture frames and logs stay in the temporary directory; the package script writes only `site/assets/cinema/` and checks frame dimensions, frame count, duration, codec, and silent audio state before writing the provenance manifest. Pass `--webm` to also create an optional VP9 fallback.
