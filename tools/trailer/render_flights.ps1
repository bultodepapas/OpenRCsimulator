# TRA-04: capture the non-crash hero shots through the real fixed-wing session.
$ErrorActionPreference = 'Stop'
$trailerRepository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location -LiteralPath $trailerRepository
$trailerGodot = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
$trailerScript = (Resolve-Path 'tools/trailer/capture_flight.gd').Path
$trailerShots = @(
    @{Id='jet-pass'; Aircraft='sebart-avanti-s-a200-p100rx'; Seconds=4},
    @{Id='stik-bank'; Aircraft='jensen-das-ugly-stik-60'; Seconds=4},
    @{Id='mustang-pass'; Aircraft='p51d-mustang-120'; Seconds=3},
    @{Id='timber-pass'; Aircraft='turbo-lumber-evolution'; Seconds=3},
    @{Id='wind'; Aircraft='jensen-das-ugly-stik-60'; Seconds=4},
    @{Id='controls'; Aircraft='jensen-das-ugly-stik-60'; Seconds=4}
)
foreach ($trailerShot in $trailerShots) {
    $trailerOut = Join-Path $trailerRepository ('tmp/trailer/flight/' + $trailerShot.Id)
    New-Item -ItemType Directory -Force -Path $trailerOut | Out-Null
    $trailerMovie = Join-Path $trailerOut ($trailerShot.Id + '.avi')
    $trailerArguments = @('--path', 'tmp/trailer/runtime/app', '--windowed', '--resolution', '1920x1080', '--disable-vsync', '--fixed-fps', '60', '--write-movie', $trailerMovie, '--script', $trailerScript, '--', "--out-dir=$trailerOut", '--movie-only', "--movie-file=$trailerMovie", "--aircraft=$($trailerShot.Aircraft)", "--shot=$($trailerShot.Id)", "--seconds=$($trailerShot.Seconds)")
    if ($trailerShot.Id -eq 'wind') {
        $trailerArguments += @('--wind-speed=4', '--wind-from=130', '--gust-speed=5', '--gust-up=1.5', '--gust-duration=2', '--gust-period=6', '--gust-delay=0.5')
    }
    $trailerProcess = Start-Process -FilePath $trailerGodot -ArgumentList $trailerArguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput "$trailerOut/stdout.log" -RedirectStandardError "$trailerOut/stderr.log"
    if ($trailerProcess.ExitCode -ne 0) { throw "Capture failed: $($trailerShot.Id)" }
    $trailerEvidence = Get-Content -Raw -LiteralPath "$trailerOut/manifest.json" | ConvertFrom-Json
    if (-not $trailerEvidence.complete) { throw "Incomplete capture: $($trailerShot.Id)" }
    Write-Output "CAPTURE_COMPLETE $($trailerShot.Id)"
}
