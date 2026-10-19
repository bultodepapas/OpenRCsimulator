# TRA-02: change startup capture resolution in an isolated project, never app/project.godot.
$ErrorActionPreference = 'Stop'
$trailerRepository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$trailerRuntime = Join-Path $trailerRepository 'tmp/trailer/runtime'
$trailerApp = Join-Path $trailerRuntime 'app'
New-Item -ItemType Directory -Force -Path $trailerApp | Out-Null
foreach ($trailerEntry in (Get-ChildItem -LiteralPath (Join-Path $trailerRepository 'app') -Force)) {
    $trailerTarget = Join-Path $trailerApp $trailerEntry.Name
    if ($trailerEntry.PSIsContainer) {
        if (-not (Test-Path -LiteralPath $trailerTarget)) {
            New-Item -ItemType Junction -Path $trailerTarget -Target $trailerEntry.FullName | Out-Null
        }
    } elseif ($trailerEntry.Name -ne 'project.godot') {
        Copy-Item -LiteralPath $trailerEntry.FullName -Destination $trailerTarget
    }
}
$trailerConfig = [IO.File]::ReadAllText((Join-Path $trailerRepository 'app/project.godot'))
$trailerConfig = $trailerConfig.Replace('viewport_width=1280','viewport_width=1920').Replace('viewport_height=720','viewport_height=1080')
[IO.File]::WriteAllText((Join-Path $trailerApp 'project.godot'), $trailerConfig)
foreach ($trailerName in @('tools','assets','research','docs')) {
    $trailerOriginal = Join-Path $trailerRepository $trailerName
    $trailerAlias = Join-Path $trailerRuntime $trailerName
    if ((Test-Path -LiteralPath $trailerOriginal) -and -not (Test-Path -LiteralPath $trailerAlias)) {
        New-Item -ItemType Junction -Path $trailerAlias -Target $trailerOriginal | Out-Null
    }
}
Write-Output $trailerApp
