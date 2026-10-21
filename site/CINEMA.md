# Cinema assets

WEB-03/04 package studio renders of native catalog aircraft. Captures call `Builder.build()` from `res://render/airplane.gd`; model geometry and authored materials remain unchanged. The renders are visual source studies, not gameplay or flight validation.

The earlier Jensen Das Ugly Stik cinema capture is no longer shipped on the website: its generated poster and MP4 were removed after the Jet became the opening aircraft. Its capture settings and source/output hashes remain in `assets/cinema/cinema.json`, and the capture pipeline can reproduce it. The Ventage Jet uses catalog id `sebart-avanti-s-a200-p100rx` and has a separate manifest at `assets/cinema/jet-cinema.json`.

## Ventage Jet render

The Jet poster is 1600×1000 WebP. Its silent MP4 is 1280×800 H.264 at 24 fps for 12 seconds; the camera makes a smooth ±9° yaw around a 42° base azimuth. Godot renders both with the exact `#101820` background and a restrained warm key, cool fill, and blue rim. Lossy WebP and H.264 encoding can shift decoded pixel values slightly. The centered native model is framed in a front three-quarter view. The Jet’s cockpit, wing, and tail detail stills are 1280×800 WebP captures of the same geometry.

`assets/cinema/jet-views.json` gives each still’s camera target in meters and model-viewer orbit `[theta, phi, radius]` in degrees/meters, plus its field of view. Targets use the visible-bounds-centered coordinates shared with the exported web GLB. The Godot capture converts azimuth `a` and elevation `e` using `theta = 180 - a` and `phi = 90 - e`. The matching camera records are also in `jet-cinema.json`.

The Jet capture uses the native catalog builder, model registry/importer, Avanti-S model and geometry generator, aircraft catalog/model records, and `app/assets/aircraft/avanti-s-a200/avanti_s.glb`. `jet-cinema.json` records SHA-256 values for these sources, the capture/package scripts, the encoder, and every generated asset. No aerodynamic or flight-performance claim is inferred from these images.

## Rebuild

Use the pinned Godot 4.7.2 Compatibility renderer, Pillow 12.3.0, and FFmpeg with `libx264`. The checked FFmpeg is version 9.0.2 essentials build from [the Windows builds linked by FFmpeg](https://ffmpeg.org/download.html#build-windows); its archive SHA-256 is `4705843ccaaf54257c16ad90f3e952ece33c17df964ecf7bfdbb0f49c7171077`.

From the repository root in PowerShell, capture the Jet poster, orbit frames, and detail stills, then package them:

```powershell
$godot = Join-Path $PWD '.tools\Godot_v4.7.2-stable_win64_console.exe'
$script = (Resolve-Path 'site/capture_cinema.gd').Path
$render = Join-Path $env:TEMP 'openrc-cinema-jet'
New-Item -ItemType Directory -Path $render -Force | Out-Null

foreach ($captureMode in @('poster', 'video', 'details')) {
    $stdout = Join-Path $render "godot-$captureMode.stdout.log"
    $stderr = Join-Path $render "godot-$captureMode.stderr.log"
    $arguments = @('--path', 'app', '--script', $script, '--', '--aircraft=jet', "--mode=$captureMode", "--out-dir=$render")
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($process.ExitCode -ne 0) { throw "Godot cinema capture failed for $captureMode; see $stderr" }
}

python site/package_cinema.py --aircraft jet --capture-dir $render --ffmpeg 'C:\path\to\ffmpeg.exe'
```

For the legacy Stik assets, use the same commands with `--aircraft=stik` and `--aircraft stik`, and capture `poster` plus `video`. Omit `--ffmpeg` when FFmpeg is on `PATH`. Captures and logs stay in the temporary directory. The package script checks dimensions, frame count, duration, codec, and silent audio state before writing the aircraft-specific assets and provenance manifest. Pass `--webm` for an optional VP9 fallback.
