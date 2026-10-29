[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [switch] $Run,
    [string] $PythonExe
)

$ErrorActionPreference = 'Stop'
$taskName = 'OpenRC GitHub Analytics'
$scriptPath = (Get-Item -LiteralPath $PSCommandPath).FullName
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$collector = Join-Path $PSScriptRoot 'github_history.py'
$powershellExe = (Get-Item -LiteralPath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')).FullName

function Test-FullyQualifiedPath([string] $Path) {
    return -not [string]::IsNullOrWhiteSpace($Path) -and
        $Path -match '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+[\\/])'
}

function Test-AbsoluteExecutable([string] $Path) {
    return (Test-FullyQualifiedPath $Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)
}

function Get-AccountSid([string] $Name) {
    if ($Name -match '^S-\d(-\d+)+$') {
        return ([Security.Principal.SecurityIdentifier]::new($Name)).Value
    }
    $account = [Security.Principal.NTAccount]::new($Name)
    return ($account.Translate([Security.Principal.SecurityIdentifier])).Value
}

function Assert-OwnedTask($Task, [string] $UserSid, [string] $ArgumentPrefix) {
    $actions = @($Task.Actions)
    if ($actions.Count -ne 1 -or
        -not [string]::Equals([string] $actions[0].Execute, $powershellExe, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string] $actions[0].WorkingDirectory, $repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Existing task '$taskName' has a different action or working directory; it was not changed."
    }
    $arguments = [string] $actions[0].Arguments
    if (-not $arguments.StartsWith($ArgumentPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $arguments.EndsWith('"')) {
        throw "Existing task '$taskName' has different arguments; it was not changed."
    }
    $oldPython = $arguments.Substring($ArgumentPrefix.Length, $arguments.Length - $ArgumentPrefix.Length - 1)
    if ($oldPython.Contains('"') -or -not (Test-FullyQualifiedPath $oldPython)) {
        throw "Existing task '$taskName' does not have the expected Python argument; it was not changed."
    }
    try {
        $ownerSid = Get-AccountSid ([string] $Task.Principal.UserId)
    } catch {
        throw "Existing task '$taskName' has an unrecognized principal; it was not changed."
    }
    if ($ownerSid -ne $UserSid) {
        throw "Existing task '$taskName' belongs to another user; it was not changed."
    }
}

if ($Run) {
    if ($WhatIfPreference) {
        Write-Host 'Would run the collector using the supplied Python executable.'
        return
    }
    $outputDir = Join-Path $env:LOCALAPPDATA 'OpenRCsimulator\analytics'
    $logPath = Join-Path $outputDir 'last-run.log'
    $started = [DateTime]::UtcNow.ToString('o')
    $exitCode = 1
    $stdout = ''
    $stderr = ''
    try {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        if (-not (Test-AbsoluteExecutable $PythonExe)) {
            throw 'The configured Python executable no longer exists or is not an absolute path. Reinstall the task.'
        }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $PythonExe
        $start.Arguments = '-u "{0}" collect --output-dir "{1}"' -f $collector, $outputDir
        $start.WorkingDirectory = $repoRoot
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        try {
            if (-not $process.Start()) { throw 'Could not start Python.' }
            $outTask = $process.StandardOutput.ReadToEndAsync()
            $errTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $stdout = $outTask.GetAwaiter().GetResult()
            $stderr = $errTask.GetAwaiter().GetResult()
            $exitCode = $process.ExitCode
        } finally {
            $process.Dispose()
        }
    } catch {
        $stderr = $_.Exception.Message
        $exitCode = 1
    }
    try {
        $finished = [DateTime]::UtcNow.ToString('o')
        $contents = @("Started UTC: $started", "Finished UTC: $finished", "Exit code: $exitCode", '',
            'stdout:', $stdout, 'stderr:', $stderr) -join [Environment]::NewLine
        [IO.File]::WriteAllText($logPath, $contents, [Text.UTF8Encoding]::new($false))
    } catch {
        Write-Error "Could not write the task log: $($_.Exception.Message)" -ErrorAction Continue
        exit 1
    }
    exit $exitCode
}

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $pythonCommand = Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $pythonOutput = @(& $pythonCommand.Source -c 'import sys; print(sys.executable)')
    if ($LASTEXITCODE -ne 0 -or $pythonOutput.Count -ne 1) {
        throw 'Could not discover the Python executable. Supply -PythonExe with an absolute path.'
    }
    $PythonExe = $pythonOutput[0].Trim()
}
if (-not (Test-AbsoluteExecutable $PythonExe)) {
    throw 'PythonExe must be the absolute path of an existing Python executable.'
}
$PythonExe = (Get-Item -LiteralPath $PythonExe).FullName
if (-not (Test-Path -LiteralPath $collector -PathType Leaf)) {
    throw 'The GitHub analytics collector is missing from this checkout.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentUser = $identity.Name
$userSid = $identity.User.Value
$argumentPrefix = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Run -PythonExe "' -f $scriptPath
$arguments = $argumentPrefix + $PythonExe + '"'
$existing = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -eq $taskName })
if ($existing.Count -gt 1) { throw "More than one task named '$taskName' exists in the root task folder." }
if ($existing.Count -eq 1) { Assert-OwnedTask $existing[0] $userSid $argumentPrefix }

$action = New-ScheduledTaskAction -Execute $powershellExe -Argument $arguments -WorkingDirectory $repoRoot
$daily = New-ScheduledTaskTrigger -Daily -At ([DateTime]::Today.AddHours(19).AddMinutes(10))
$logon = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
$zone = Get-TimeZone
Write-Host "Task: $taskName (current user: $currentUser; interactive, limited)"
Write-Host "Daily trigger: 19:10 local Windows time ($($zone.Id)); also at this user's logon."
Write-Host "Collector: $collector"
Write-Host "Python: $PythonExe"
Write-Host "Data and last-run.log: $env:LOCALAPPDATA\OpenRCsimulator\analytics"

if ($PSCmdlet.ShouldProcess($taskName, 'Create or update this user-owned analytics task')) {
    $register = @{
        TaskName = $taskName; TaskPath = '\'; Action = $action; Trigger = @($daily, $logon)
        Principal = $principal; Settings = $settings
        Description = 'OpenRC local GitHub traffic and release counter collection'
    }
    if ($existing.Count -eq 1) {
        $current = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        Assert-OwnedTask $current $userSid $argumentPrefix
        $register.Force = $true
    }
    Register-ScheduledTask @register | Out-Null
    Write-Host 'Task registered.'
}
