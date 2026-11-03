#requires -Version 5.1
<#
.SYNOPSIS
    Start the existing VisionPark development applications from any directory.
.DESCRIPTION
    Run .\start-visionpark.ps1 and choose emulator, phone, or web only.
    If script execution is restricted, allow this invocation only:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-visionpark.ps1
    Uses root/venv, web-app, and mobile/env/development.json unchanged.
    Backend/Admin get visible consoles; Flutter owns this console's input.
    Flutter: r = reload, R = restart, q = quit. VS Code: Debug > Attach to
    Flutter Process, when available, or attach using Flutter's VM Service URI.
    Stop each service with Ctrl+C in its own labelled console. Quitting Flutter
    leaves Backend/Admin running for reuse. No processes are killed by this script.
    -Service is an internal entry point for the two service consoles.
#>
[CmdletBinding()]
param(
    [ValidateSet('Backend', 'Admin')]
    [string]$Service
)

$script:ProjectRoot = $PSScriptRoot
$script:LauncherPath = $PSCommandPath
$script:Python = Join-Path $PSScriptRoot 'venv\Scripts\python.exe'
$script:WebDir = Join-Path $PSScriptRoot 'web-app'
$script:MobileDir = Join-Path $PSScriptRoot 'mobile'
$script:DefinesPath = Join-Path $script:MobileDir 'env\development.json'
$script:AvdName = 'Medium_Phone'

function Require-Command([string]$Name) {
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { throw "Missing $Name. Make the existing installation available on PATH, then retry. Nothing was installed." }
    return $command.Source
}

function Assert-DevelopmentDefines {
    if (-not (Test-Path -LiteralPath $script:DefinesPath -PathType Leaf)) {
        throw 'Missing mobile/env/development.json, used by mobile/dev.ps1. Restore your existing development Dart defines before using a mobile mode. No credentials were generated or changed.'
    }
    # Never include a JSON parser exception: it can contain credential values.
    try { $defines = Get-Content -LiteralPath $script:DefinesPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Cannot read mobile/env/development.json as JSON (contents suppressed). Check the existing development configuration.' }
    if ([string]::IsNullOrWhiteSpace($defines.SUPABASE_URL) -or
        [string]::IsNullOrWhiteSpace($defines.SUPABASE_PUBLISHABLE_KEY)) {
        throw 'The existing development JSON needs SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY. No fallback or UAT configuration will be used.'
    }
    if ($defines.FASTAPI_BASE_URL -ne 'http://127.0.0.1:8000') {
        throw 'The existing development JSON must target the expected local backend on port 8000. Resolve the configuration explicitly before retrying; the launcher will not edit it.'
    }
}

function Test-ServiceOwner([int]$ProcessId, [string]$Kind) {
    # Follow reload/npm children to an identifiable project command. A port or
    # process name alone is not proof. Never print arbitrary command lines.
    $currentId = $ProcessId
    $childCreated = $null
    for ($depth = 0; $depth -lt 10 -and $currentId -gt 0; $depth++) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$currentId" -ErrorAction Stop
        if (-not $process) { return $false }
        if ($childCreated -and $process.CreationDate -gt $childCreated) { return $false }
        $commandLine = [string]$process.CommandLine
        if ($Kind -eq 'Backend') {
            $isProjectPython = $process.ExecutablePath -eq $script:Python -or
                $process.ExecutablePath -eq (Join-Path $script:ProjectRoot 'venv\Scripts\uvicorn.exe')
            if ($isProjectPython -and $commandLine -match '(?:^|[\s"])backend\.main:app(?:[\s"]|$)' -and
                $commandLine -match '(?:^|\s)--reload(?:\s|$)' -and
                $commandLine -notmatch '--(?:env-file|app-dir)\b') { return $true }
        }
        else {
            if ($process.Name -eq 'node.exe' -and $commandLine -match '(?:^|[\s"])dev(?:[\s"]|$)') {
                $nextCli = Join-Path $script:WebDir 'node_modules\next\dist\bin\next'
                foreach ($token in [regex]::Matches($commandLine, '"[^"]*"|\S+')) {
                    $argumentPath = $token.Value.Trim('"')
                    if (-not [System.IO.Path]::IsPathRooted($argumentPath)) { continue }
                    # npm commonly invokes .bin\..\next; resolve that path before
                    # comparing it with this project's CLI, never a sibling UAT.
                    try { $canonicalPath = [System.IO.Path]::GetFullPath($argumentPath) }
                    catch { continue }
                    if ($canonicalPath -eq $nextCli) { return $true }
                }
            }
        }
        $childCreated = $process.CreationDate
        $currentId = [int]$process.ParentProcessId
    }
    return $false
}

function Get-ServicePortState([int]$Port, [string]$Kind) {
    # Enumerating listeners avoids treating a failed port query as a free port.
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object LocalPort -eq $Port)
    if ($listeners.Count -eq 0) { return 'Free' }
    foreach ($ownerId in @($listeners.OwningProcess | Sort-Object -Unique)) {
        if (-not (Test-ServiceOwner -ProcessId $ownerId -Kind $Kind)) {
            throw "Port $Port is occupied by an unverified process (PID $ownerId). Inspect it in Task Manager or its terminal and resolve the conflict manually. Nothing was stopped."
        }
    }
    if (-not ($listeners | Where-Object LocalAddress -in @('127.0.0.1', '0.0.0.0', '::', '::1'))) {
        throw "The identified $Kind on port $Port is not listening on loopback. Check its terminal before retrying."
    }
    return 'Running'
}

function Invoke-ServiceConsole([string]$Kind) {
    $port = if ($Kind -eq 'Backend') { 8000 } else { 3000 }
    $Host.UI.RawUI.WindowTitle = "VisionPark - $Kind ($port)"
    # Check again inside the child console, closing the ordinary startup race.
    if ((Get-ServicePortState -Port $port -Kind $Kind) -eq 'Running') {
        Write-Host "$Kind is already running on port $port; this console can be closed."
        return
    }
    Write-Host "VisionPark $Kind - stop with Ctrl+C in this console."
    $location = if ($Kind -eq 'Backend') { $script:ProjectRoot } else { $script:WebDir }
    Push-Location -LiteralPath $location
    try {
        if ($Kind -eq 'Backend') {
            # Calling the venv interpreter directly needs no activation or policy change.
            & $script:Python -m uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
        }
        else { & (Require-Command 'npm.cmd') run dev -- --port 3000 }
        if ($LASTEXITCODE -ne 0) { throw "$Kind exited with code $LASTEXITCODE. Review this console's logs, fix the reported issue, then rerun the launcher." }
    }
    finally { Pop-Location }
}

function Start-DevelopmentServices {
    if (-not (Test-Path -LiteralPath $script:Python -PathType Leaf)) {
        throw 'The existing venv/Scripts/python.exe is missing. Restore the project virtual environment first; the launcher does not install dependencies.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $script:WebDir 'node_modules\next\dist\bin\next') -PathType Leaf)) {
        throw 'The existing web-app Next.js installation is missing. Set up the normal project dependencies separately, then retry.'
    }
    $null = Require-Command 'npm.cmd'
    $console = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $console)) { $console = Require-Command 'pwsh.exe' }
    # Preflight both ports before starting either service.
    $states = @{}
    foreach ($kind in @('Backend', 'Admin')) {
        $port = if ($kind -eq 'Backend') { 8000 } else { 3000 }
        $states[$kind] = Get-ServicePortState -Port $port -Kind $kind
    }
    foreach ($kind in @('Backend', 'Admin')) {
        $port = if ($kind -eq 'Backend') { 8000 } else { 3000 }
        if ($states[$kind] -eq 'Running') {
            Write-Host "Reusing the identified VisionPark $kind on port $port."
            continue
        }
        Write-Host "Starting $kind on port $port in its own terminal..."
        # Allow this child script for this process only; never change a saved policy.
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -Service {1}' -f $script:LauncherPath, $kind
        $consoleProcess = Start-Process -FilePath $console -ArgumentList $arguments -WorkingDirectory $script:ProjectRoot -WindowStyle Normal -PassThru
        $deadline = (Get-Date).AddSeconds(90)
        $ready = $false
        do {
            if ((Get-ServicePortState -Port $port -Kind $kind) -eq 'Running') { $ready = $true; break }
            if ($consoleProcess.HasExited) { break }
            Start-Sleep -Seconds 1
        } while ((Get-Date) -lt $deadline)
        if (-not $ready) { throw "$kind did not open port $port within 90 seconds. Check its labelled console. Services already started remain available; use Ctrl+C in their consoles to stop them." }
    }
    Write-Host "`nBackend:   http://127.0.0.1:8000"
    Write-Host 'Admin Web: http://localhost:3000'
    Write-Host 'Stop each service with Ctrl+C in its own console. Existing services are never stopped automatically.'
}

function Find-Adb {
    $command = Get-Command adb.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk")) {
        if ([string]::IsNullOrWhiteSpace($sdk)) { continue }
        $candidate = Join-Path $sdk 'platform-tools\adb.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'ADB was not found. Put the existing Android SDK platform-tools on PATH or set ANDROID_HOME in this terminal, then retry.'
}

function Invoke-Adb([string[]]$Arguments, [int]$TimeoutSeconds = 12) {
    # Probes must not hang indefinitely on an offline device. Pairing is handled
    # separately in the foreground so ADB can prompt for its pairing code.
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $script:Adb
    $info.Arguments = ($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $probe = New-Object System.Diagnostics.Process
    $probe.StartInfo = $info
    try {
        $null = $probe.Start()
        $stdout = $probe.StandardOutput.ReadToEndAsync()
        $stderr = $probe.StandardError.ReadToEndAsync()
        if (-not $probe.WaitForExit($TimeoutSeconds * 1000)) {
            # Only this short-lived client is killed, never the ADB server/device.
            $probe.Kill()
            $probe.WaitForExit()
            return [pscustomobject]@{ Code = -1; Output = ''; Error = 'ADB request timed out.' }
        }
        return [pscustomobject]@{ Code = $probe.ExitCode; Output = $stdout.Result.Trim(); Error = $stderr.Result.Trim() }
    }
    finally { $probe.Dispose() }
}

function Get-AdbDevices {
    $result = Invoke-Adb -Arguments @('devices', '-l')
    if ($result.Code -ne 0) { throw 'ADB could not list devices. Run adb devices in your normal terminal and check SDK/user permissions. No server restart was attempted.' }
    foreach ($line in ($result.Output -split '\r?\n')) {
        if ($line -match '^(\S+)\s+(device|offline|unauthorized|no permissions)\b(.*)$') {
            [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2]; Details = $Matches[3].Trim() }
        }
    }
}

function Find-RunningEmulator {
    foreach ($device in @(Get-AdbDevices | Where-Object Serial -like 'emulator-*')) {
        if ($device.State -ne 'device') { continue }
        $name = Invoke-Adb -Arguments @('-s', $device.Serial, 'emu', 'avd', 'name')
        if ($name.Code -eq 0 -and ($name.Output -split '\r?\n')[0].Trim() -eq $script:AvdName) { $device }
    }
}

function Get-EmulatorSerial {
    $matches = @(Find-RunningEmulator)
    if ($matches.Count -gt 1) { throw 'More than one Medium_Phone instance is running. Select/close an instance in Android Device Manager, then retry.' }
    if ($matches.Count -eq 0) {
        $emulatorDevices = @(Get-AdbDevices | Where-Object Serial -like 'emulator-*')
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match '^(emulator|qemu-system-.+)\.exe$' })
        $targetPattern = '(?:-avd\s+"?' + [regex]::Escape($script:AvdName) + '(?:"|\s|$)|@' + [regex]::Escape($script:AvdName) + '(?:"|\s|$))'
        $alreadyStarting = @($processes | Where-Object { $_.CommandLine -match $targetPattern }).Count -gt 0
        $unidentified = @($emulatorDevices | Where-Object State -ne 'device').Count -gt 0
        # If ADB cannot identify an instance, never guess and start a duplicate.
        if (-not $alreadyStarting -and ($unidentified -or ($processes.Count -gt 0 -and $emulatorDevices.Count -eq 0))) {
            throw 'An emulator is starting or offline and cannot be safely identified. Wait for Android Device Manager to show it online; unlock it and retry. You may reconnect that specific serial with adb -s <serial> reconnect. No emulator was launched or reset.'
        }
        if ($alreadyStarting) { Write-Host 'Medium_Phone is already starting; waiting for it without launching another instance...' }
        else {
            # Also refuse an online emulator whose AVD name query failed.
            foreach ($device in $emulatorDevices) {
                $name = Invoke-Adb -Arguments @('-s', $device.Serial, 'emu', 'avd', 'name')
                $avd = ($name.Output -split '\r?\n')[0].Trim()
                if ($name.Code -ne 0 -or [string]::IsNullOrWhiteSpace($avd) -or $avd -eq 'OK') {
                    throw 'An existing emulator could not report its AVD name. Check Android Device Manager before retrying; no duplicate was launched.'
                }
            }
            Write-Host 'Launching the existing Medium_Phone AVD...'
            & $script:Flutter emulators --launch $script:AvdName
            if ($LASTEXITCODE -ne 0) { throw 'Flutter could not launch Medium_Phone. Check flutter emulators and Android Device Manager. No AVD settings or data were changed.' }
        }
    }
    Write-Host 'Waiting for Medium_Phone to finish booting and its package manager to respond (up to 3 minutes)...'
    $deadline = (Get-Date).AddMinutes(3)
    do {
        $matches = @(Find-RunningEmulator)
        if ($matches.Count -gt 1) { throw 'Multiple Medium_Phone instances appeared. Resolve the ambiguity in Android Device Manager, then retry.' }
        if ($matches.Count -eq 1) {
            $serial = $matches[0].Serial
            $boot = Invoke-Adb -Arguments @('-s', $serial, 'shell', 'getprop', 'sys.boot_completed')
            if ($boot.Code -eq 0 -and $boot.Output -eq '1') {
                $packages = Invoke-Adb -Arguments @('-s', $serial, 'shell', 'pm', 'path', 'android')
                if ($packages.Code -eq 0 -and $packages.Output -match '^package:') { return $serial }
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw 'Medium_Phone did not become responsive within 3 minutes. Check its screen in Android Device Manager, unlock it, and retry. If ADB shows offline, reconnect only that serial. No data was deleted or reset.'
}

function Get-PhysicalDevices {
    foreach ($device in @(Get-AdbDevices)) {
        if ($device.Serial -like 'emulator-*' -or $device.State -ne 'device') { continue }
        # A TCP-connected emulator can have an IP serial instead of emulator-N.
        $qemu = Invoke-Adb -Arguments @('-s', $device.Serial, 'shell', 'getprop', 'ro.kernel.qemu')
        if ($qemu.Code -eq 0 -and $qemu.Output -ne '1') { $device }
    }
}

function Read-AdbAddress([string]$Prompt) {
    while ($true) {
        $address = (Read-Host $Prompt).Trim()
        if (-not $address) { throw 'Wireless connection cancelled. Backend/Admin remain available in their consoles.' }
        $endpointMatch = [regex]::Match($address, '^(?<host>\d{1,3}(?:\.\d{1,3}){3}|\[[0-9A-Fa-f:]+\]):(?<port>\d{1,5})$')
        $ip = $null
        if ($endpointMatch.Success -and [System.Net.IPAddress]::TryParse($endpointMatch.Groups['host'].Value.Trim('[', ']'), [ref]$ip) -and
            [int]$endpointMatch.Groups['port'].Value -ge 1 -and [int]$endpointMatch.Groups['port'].Value -le 65535) { return $address }
        Write-Host 'Enter the current IP:port shown by Android, for example <phone-IP>:<port> (IPv6: [address]:port).'
    }
}

function Get-PhoneSerial {
    $devices = @(Get-PhysicalDevices)
    if ($devices.Count -eq 1) { return $devices[0].Serial }
    if ($devices.Count -gt 1) {
        Write-Host 'Select the physical Android device:'
        for ($index = 0; $index -lt $devices.Count; $index++) {
            Write-Host ('[{0}] {1} {2}' -f ($index + 1), $devices[$index].Serial, $devices[$index].Details)
        }
        while ($true) {
            $selection = Read-Host 'Device number (blank to cancel)'
            if (-not $selection) { throw 'Device selection cancelled. Backend/Admin remain available.' }
            $number = 0
            if ([int]::TryParse($selection, [ref]$number) -and $number -ge 1 -and $number -le $devices.Count) { return $devices[$number - 1].Serial }
            Write-Host 'Choose one of the listed device numbers.'
        }
    }
    foreach ($device in @(Get-AdbDevices | Where-Object Serial -notlike 'emulator-*')) {
        Write-Host ("ADB reports {0}: {1}. Unlock the phone and approve debugging; check Wi-Fi if offline." -f $device.Serial, $device.State)
    }
    Write-Host "`nNo authorised, online physical phone was found."
    Write-Host 'On the phone: enable Developer options > Wireless debugging. Keep the phone and PC on the same trusted Wi-Fi.'
    Write-Host 'First use the IP address & port on the main Wireless debugging screen. Pairing is offered only if connecting fails.'
    $address = Read-AdbAddress 'Current connection IP:port (blank to cancel)'
    $connection = Invoke-Adb -Arguments @('connect', $address) -TimeoutSeconds 20
    if ($connection.Code -ne 0 -or $connection.Output -notmatch '(?:already )?connected to') {
        Write-Host 'Connection failed. Check the address, Wi-Fi, and Wireless debugging. Pair only if this PC is not already paired.'
        if ((Read-Host 'Pair this PC now? [y/N]') -notmatch '^(?i:y|yes)$') { throw 'Phone not connected. Correct the connection address or authorise the PC, then rerun the launcher.' }
        Write-Host 'Open Wireless debugging > Pair device with pairing code. Its pairing port differs from the connection port.'
        $pairAddress = Read-AdbAddress 'Current pairing IP:port (blank to cancel)'
        # ADB securely prompts for the code itself; it is never stored in a script or argument.
        & $script:Adb pair $pairAddress
        if ($LASTEXITCODE -ne 0) { throw 'ADB pairing failed. Check the current pairing address/code on the phone and retry.' }
        $address = Read-AdbAddress 'Return to the main Wireless debugging screen; current connection IP:port'
        $connection = Invoke-Adb -Arguments @('connect', $address) -TimeoutSeconds 20
        if ($connection.Code -ne 0 -or $connection.Output -notmatch '(?:already )?connected to') { throw 'Pairing completed but connection failed. Recheck the connection IP:port on the main Wireless debugging screen and retry.' }
    }
    Write-Host 'Waiting for the selected phone to become authorised and responsive (up to 45 seconds)...'
    $deadline = (Get-Date).AddSeconds(45)
    do {
        $selected = @(Get-PhysicalDevices | Where-Object Serial -eq $address)
        if ($selected.Count -eq 1) { return $selected[0].Serial }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw 'The selected phone did not become authorised and online. Unlock it, accept debugging authorisation, check Wi-Fi and the current connection port, then retry. Run adb devices -l for status.'
}

function Set-BackendReverse([string]$Serial) {
    $online = Invoke-Adb -Arguments @('-s', $Serial, 'get-state')
    if ($online.Code -ne 0 -or $online.Output -ne 'device') { throw "Selected device $Serial is no longer online/authorised. Reconnect it and retry." }
    $reverse = Invoke-Adb -Arguments @('-s', $Serial, 'reverse', 'tcp:8000', 'tcp:8000')
    if ($reverse.Code -ne 0) { throw "ADB reverse failed for $Serial. Check its connection and run adb -s $Serial reverse tcp:8000 tcp:8000 in your terminal." }
    $rules = Invoke-Adb -Arguments @('-s', $Serial, 'reverse', '--list')
    if ($rules.Code -ne 0 -or $rules.Output -notmatch '(?m)^\S+\s+tcp:8000\s+tcp:8000\s*$') { throw "Port forwarding could not be verified for $Serial. Reconnect the device and retry." }
    Write-Host "Verified $Serial : device port 8000 -> local port 8000."
}

function Invoke-VisionParkLauncher {
    Write-Host '========================================'
    Write-Host '         VISIONPARK DEV LAUNCHER'
    Write-Host '========================================'
    Write-Host "`nSelect development mode:`n"
    Write-Host '[1] Android Emulator (Medium_Phone)'
    Write-Host '[2] Physical Android Phone (Wireless ADB)'
    Write-Host '[3] Backend + Admin Web Only'
    Write-Host "[4] Exit`n"
    do { $choice = Read-Host 'Enter your choice' } while ($choice -notin @('1', '2', '3', '4'))
    if ($choice -eq '4') { return }
    if ($choice -ne '3') {
        Assert-DevelopmentDefines
        $script:Flutter = Require-Command 'flutter.bat'
        $script:Adb = Find-Adb
    }
    Start-DevelopmentServices
    if ($choice -eq '3') { return }
    $serial = if ($choice -eq '1') { Get-EmulatorSerial } else { Get-PhoneSerial }
    Write-Host "Selected Android device: $serial"
    Set-BackendReverse -Serial $serial
    Write-Host "`nStarting interactive Flutter debug session. r = hot reload; R = hot restart; q = quit."
    Write-Host 'Use the VM Service URI printed by Flutter to attach a debugger, or VS Code: Attach to Flutter Process.'
    Write-Host 'Quitting Flutter leaves Backend/Admin running. Stop them with Ctrl+C in their own consoles.'
    $flutterArguments = @('run', '-d', $serial, '--debug', '--no-pub',
        '--dart-define-from-file=env/development.json', '--dart-define=FASTAPI_BASE_URL=http://127.0.0.1:8000')
    # No piping, redirection, jobs, or detached process: Flutter inherits stdin
    # and the console, retaining its normal VM Service and r/R/q commands.
    Push-Location -LiteralPath $script:MobileDir
    try {
        & $script:Flutter @flutterArguments
        if ($LASTEXITCODE -ne 0) { throw "Flutter exited with code $LASTEXITCODE. Review its logs above. Backend/Admin are still available in their consoles." }
    }
    finally { Pop-Location }
}

# Dot-sourcing defines functions for non-destructive verification only.
if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    try {
        if ($Service) { Invoke-ServiceConsole -Kind $Service }
        else { Invoke-VisionParkLauncher }
    }
    catch {
        Write-Host ("VisionPark launcher: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Services already running were left in place. Check their consoles; Ctrl+C stops a service in its own console.'
        exit 1
    }
}
