[CmdletBinding()]
param(
	[switch]$PreflightOnly,
	[ValidateRange(1, 9)]
	[int]$Repetitions = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$enginePath = Join-Path $repoRoot ".tools\Godot_v4.7.2-stable_win64_console.exe"
$probeSource = Join-Path $PSScriptRoot "cost_probe.gd"
$baseCommit = "22b3e4825ec97289b76666ca9e942eaa7a8f703d"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
	throw "Pinned Godot engine not found: $enginePath"
}
if (-not (Test-Path -LiteralPath $probeSource -PathType Leaf)) {
	throw "Cost probe not found: $probeSource"
}
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
	throw "git.exe is required to archive the fixed baseline commit."
}
if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
	throw "tar.exe is required to extract the fixed baseline source archive."
}

$runId = [Guid]::NewGuid().ToString("N")
$workRoot = Join-Path $repoRoot ".tools\controller-input-cost\$runId"
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$archiveRoot = Join-Path $workRoot "baseline-archive"
New-Item -ItemType Directory -Path $archiveRoot | Out-Null
$baselineTar = Join-Path $workRoot "baseline.tar"

& git.exe -C $repoRoot archive --format=tar "--output=$baselineTar" $baseCommit "app/input/rc_input.gd" "app/input/smoke_aux.gd"
if ($LASTEXITCODE -ne 0) {
	throw "Could not archive baseline source at $baseCommit."
}
& tar.exe -xf $baselineTar -C $archiveRoot
if ($LASTEXITCODE -ne 0) {
	throw "Could not extract the baseline source archive."
}

$sourceHashes = [ordered]@{
	baseline = [ordered]@{}
	current = [ordered]@{}
}

function New-ProbeResourceRoot {
	param(
		[Parameter(Mandatory = $true)][string]$Variant,
		[Parameter(Mandatory = $true)][string]$Root,
		[Parameter(Mandatory = $true)][string[]]$InputSources
	)

	$inputRoot = Join-Path $Root "input"
	New-Item -ItemType Directory -Path $inputRoot -Force | Out-Null
	$projectText = @"
config_version=5

[application]
config/name="OpenRC controller input cost probe"

[rendering]
renderer/rendering_method="gl_compatibility"
"@
	[System.IO.File]::WriteAllText((Join-Path $Root "project.godot"), $projectText, $utf8NoBom)
	Copy-Item -LiteralPath $probeSource -Destination (Join-Path $Root "cost_probe.gd")

	foreach ($source in $InputSources) {
		if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
			throw "Required $Variant probe input source not found: $source"
		}
		$destination = Join-Path $inputRoot (Split-Path -Leaf $source)
		Copy-Item -LiteralPath $source -Destination $destination
		$sourceHashes[$Variant][(Split-Path -Leaf $source)] = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
	}
	$sourceHashes[$Variant]["cost_probe.gd"] = (Get-FileHash -LiteralPath $probeSource -Algorithm SHA256).Hash.ToLowerInvariant()
}

$baselineRoot = Join-Path $workRoot "baseline"
$currentRoot = Join-Path $workRoot "current"
$baselineSources = @(
	(Join-Path $archiveRoot "app\input\rc_input.gd"),
	(Join-Path $archiveRoot "app\input\smoke_aux.gd")
)
$currentSources = @(
	(Join-Path $repoRoot "app\input\rc_input.gd"),
	(Join-Path $repoRoot "app\input\smoke_aux.gd"),
	(Join-Path $repoRoot "app\input\controller_profile.gd"),
	(Join-Path $repoRoot "app\input\controller_actions.gd")
)
New-ProbeResourceRoot -Variant "baseline" -Root $baselineRoot -InputSources $baselineSources
New-ProbeResourceRoot -Variant "current" -Root $currentRoot -InputSources $currentSources

$headOutput = & git.exe -C $repoRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) {
	throw "Could not read the current repository HEAD."
}
$currentHead = ([string]$headOutput).Trim()

function Invoke-CostProbe {
	param(
		[Parameter(Mandatory = $true)][string]$Variant,
		[Parameter(Mandatory = $true)][string]$ResourceRoot,
		[Parameter(Mandatory = $true)][int]$Repetition,
		[Parameter(Mandatory = $true)][string]$LogRoot,
		[switch]$IsPreflight
	)

	$scriptPath = Join-Path $ResourceRoot "cost_probe.gd"
	$arguments = @("--headless", "--path", $ResourceRoot, "--script", $scriptPath, "--", "--variant=$Variant")
	if ($IsPreflight) {
		$arguments += "--preflight-only"
	}
	$outputLines = @(& $enginePath @arguments 2>&1 | ForEach-Object { [string]$_ })
	$exitCode = $LASTEXITCODE
	$logName = if ($IsPreflight) { "$Variant-preflight.log" } else { "$Variant-rep$Repetition.log" }
	$logPath = Join-Path $LogRoot $logName
	[System.IO.File]::WriteAllLines($logPath, [string[]]$outputLines, $utf8NoBom)
	if ($exitCode -ne 0) {
		throw "$Variant probe exited $exitCode; inspect $logPath"
	}

	$resultLines = @($outputLines | Where-Object { $_.StartsWith("F6_INPUT_COST_RESULT ") })
	if ($resultLines.Count -ne 1) {
		throw "$Variant probe did not emit exactly one result record; inspect $logPath"
	}
	$resultJson = $resultLines[0].Substring("F6_INPUT_COST_RESULT ".Length)
	$result = ConvertFrom-Json -InputObject $resultJson
	if ($result.engine.string -ne "4.7.2-stable (official)") {
		throw "Unexpected engine build in $($logPath): $($result.engine.string)"
	}
	if ($result.variant -ne $Variant) {
		throw "Probe reported variant '$($result.variant)' while running '$Variant'."
	}
	if ([bool]$result.preflight_only -ne [bool]$IsPreflight) {
		throw "Probe preflight mode did not match runner mode; inspect $logPath"
	}
	if (-not $IsPreflight -and ([int]$result.measured_ticks -ne 12000 -or [int]$result.batch_count -ne 5)) {
		throw "Unexpected measured sample count in $logPath."
	}

	return [pscustomobject]@{
		variant = $Variant
		repetition = $Repetition
		log = $logName
		measurement = $result
	}
}

function Assert-ComparableInputs {
	param([object]$Baseline, [object]$Current)

	if ($Baseline.engine.string -ne $Current.engine.string -or $Baseline.engine.hash -ne $Current.engine.hash) {
		throw "Baseline and current probes used different Godot builds."
	}
	if ($Baseline.tick_hz -ne $Current.tick_hz -or $Baseline.dt_s -ne $Current.dt_s) {
		throw "Baseline and current probes used different fixed-tick intervals."
	}
	if (($Baseline.sample_axes_0_to_3 -join ",") -ne ($Current.sample_axes_0_to_3 -join ",")) {
		throw "Baseline and current probes used different axis samples."
	}
	if (($Baseline.event_axes -join ",") -ne ($Current.event_axes -join ",")) {
		throw "Baseline and current probes sent different event axes."
	}
	if ($Baseline.device.kind -ne $Current.device.kind -or $Baseline.device.known -ne $Current.device.known) {
		throw "Baseline and current probes used different synthetic device classifications."
	}
	foreach ($channel in @("roll", "pitch", "yaw", "throttle")) {
		if ([Math]::Abs([double]$Baseline.last_command.$channel - [double]$Current.last_command.$channel) -gt 0.000001) {
			throw "Baseline and current probes produced different $channel commands for the same synthetic input."
		}
	}
}

if ($PreflightOnly) {
	$baselinePreflight = Invoke-CostProbe -Variant "baseline" -ResourceRoot $baselineRoot -Repetition 1 -LogRoot $workRoot -IsPreflight
	$currentPreflight = Invoke-CostProbe -Variant "current" -ResourceRoot $currentRoot -Repetition 1 -LogRoot $workRoot -IsPreflight
	Assert-ComparableInputs -Baseline $baselinePreflight.measurement -Current $currentPreflight.measurement
	Write-Host "Preflight passed for baseline $baseCommit and current RcInput with Godot $($currentPreflight.measurement.engine.string)."
	Write-Host "Synthetic command: $($currentPreflight.measurement.last_command | ConvertTo-Json -Compress)"
	Write-Host "Ignored snapshots and preflight logs: $workRoot"
	exit 0
}

$outputBase = Join-Path $PSScriptRoot "cost\runs"
New-Item -ItemType Directory -Path $outputBase -Force | Out-Null
$outputDir = Join-Path $outputBase ((Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ") + "-$runId")
New-Item -ItemType Directory -Path $outputDir | Out-Null

$runRecords = [System.Collections.Generic.List[object]]::new()
for ($repetition = 1; $repetition -le $Repetitions; $repetition++) {
	$order = if ($repetition % 2 -eq 1) { @("baseline", "current") } else { @("current", "baseline") }
	foreach ($variant in $order) {
		$resourceRoot = if ($variant -eq "baseline") { $baselineRoot } else { $currentRoot }
		$record = Invoke-CostProbe -Variant $variant -ResourceRoot $resourceRoot -Repetition $repetition -LogRoot $outputDir
		$runRecords.Add($record)
	}
	$pair = @($runRecords | Where-Object { $_.repetition -eq $repetition })
	$pairBaseline = $pair | Where-Object { $_.variant -eq "baseline" } | Select-Object -ExpandProperty measurement
	$pairCurrent = $pair | Where-Object { $_.variant -eq "current" } | Select-Object -ExpandProperty measurement
	Assert-ComparableInputs -Baseline $pairBaseline -Current $pairCurrent
}

function Get-Median {
	param([double[]]$Values)
	$sorted = @($Values | Sort-Object)
	if ($sorted.Count -eq 0) {
		return 0.0
	}
	$middle = [int][Math]::Floor($sorted.Count / 2)
	if ($sorted.Count % 2 -eq 1) {
		return [double]$sorted[$middle]
	}
	return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function Get-Range {
	param([double[]]$Values)
	$sorted = @($Values | Sort-Object)
	return [ordered]@{
		min = [double]$sorted[0]
		max = [double]$sorted[$sorted.Count - 1]
	}
}

$metricNames = @("event_callbacks", "poll_plus_command", "event_to_command")
$variantSummaries = [ordered]@{}
foreach ($variant in @("baseline", "current")) {
	$variantRuns = @($runRecords | Where-Object { $_.variant -eq $variant })
	$variantMetrics = [ordered]@{}
	foreach ($metricName in $metricNames) {
		$metricRuns = @($variantRuns | ForEach-Object { $_.measurement.measurements.$metricName })
		$medians = @($metricRuns | ForEach-Object { [double]$_.median_us })
		$p95s = @($metricRuns | ForEach-Object { [double]$_.p95_us })
		$budgetPcts = @($metricRuns | ForEach-Object { [double]$_.p95_budget_percent })
		$variantMetrics[$metricName] = [ordered]@{
			median_of_run_medians_us = Get-Median -Values $medians
			median_of_run_p95_us = Get-Median -Values $p95s
			p95_budget_percent = Get-Median -Values $budgetPcts
			run_median_range_us = Get-Range -Values $medians
			run_p95_range_us = Get-Range -Values $p95s
			samples_per_run = [int]$metricRuns[0].samples
		}
	}
	$variantSummaries[$variant] = $variantMetrics
}

$deltas = [ordered]@{}
foreach ($metricName in $metricNames) {
	$baselineMetric = $variantSummaries.baseline[$metricName]
	$currentMetric = $variantSummaries.current[$metricName]
	$deltaP95 = [double]$currentMetric.median_of_run_p95_us - [double]$baselineMetric.median_of_run_p95_us
	$deltas[$metricName] = [ordered]@{
		median_us = [double]$currentMetric.median_of_run_medians_us - [double]$baselineMetric.median_of_run_medians_us
		p95_us = $deltaP95
		p95_budget_percent = 100.0 * $deltaP95 / (1000000.0 / 240.0)
	}
}

$publicRuns = @($runRecords | ForEach-Object {
	[ordered]@{
		variant = $_.variant
		repetition = $_.repetition
		log = $_.log
		measurement = $_.measurement
	}
})
$resultMeta = $publicRuns[0].measurement
$summary = [ordered]@{
	format = "openrc-controller-input-cost-comparison v1"
	created_utc = (Get-Date).ToUniversalTime().ToString("o")
	baseline_commit = $baseCommit
	current_head = $currentHead
	engine = $resultMeta.engine
	os = $resultMeta.os
	processor = $resultMeta.processor
	tick_hz = $resultMeta.tick_hz
	dt_s = $resultMeta.dt_s
	tick_budget_us = $resultMeta.tick_budget_us
	repetitions_per_variant = $Repetitions
	source_sha256 = $sourceHashes
	measurement_scope = $resultMeta.measurement_scope
	timing_note = $resultMeta.timing_note
	read_button_semantics = $resultMeta.read_button_semantics
	variant_summaries = $variantSummaries
	current_minus_baseline = $deltas
	runs = $publicRuns
}

$summaryJson = $summary | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText((Join-Path $outputDir "summary.json"), $summaryJson + [Environment]::NewLine, $utf8NoBom)
$runsJson = [ordered]@{
	format = "openrc-controller-input-cost-runs v1"
	baseline_commit = $baseCommit
	current_head = $currentHead
	source_sha256 = $sourceHashes
	runs = $publicRuns
} | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText((Join-Path $outputDir "runs.json"), $runsJson + [Environment]::NewLine, $utf8NoBom)

Write-Host "Cost probe completed. Godot $($resultMeta.engine.string), $($resultMeta.os), $($resultMeta.processor)."
Write-Host "Baseline commit: $baseCommit"
Write-Host "Summary: $(Join-Path $outputDir 'summary.json')"
$deltas.event_to_command | ConvertTo-Json -Compress | Write-Host
