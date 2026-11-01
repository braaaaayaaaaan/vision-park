[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$Avd = 'Medium_Phone',
    [string]$SdkPath = "$env:LOCALAPPDATA\Android\Sdk"
)

$ErrorActionPreference = 'Stop'
$emulatorPath = Join-Path $SdkPath 'emulator\emulator.exe'
$adbPath = Join-Path $SdkPath 'platform-tools\adb.exe'
foreach ($toolPath in @($emulatorPath, $adbPath)) {
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Android tool missing: $toolPath. Supply -SdkPath with your Android SDK directory."
    }
}
if (Get-Process -Name 'emulator', 'qemu-system-x86_64' -ErrorAction SilentlyContinue) {
    throw 'Close the existing emulator before using the demo launcher. It will not restart an active device.'
}

$logDir = Join-Path $PSScriptRoot 'build\emulator-demo'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$stdoutLog = Join-Path $logDir "$stamp-stdout.log"
$stderrLog = Join-Path $logDir "$stamp-stderr.log"
# Bypass Quick Boot and the host GPU driver; retain the AVD's installed apps/data.
Start-Process -FilePath $emulatorPath -ArgumentList @(
    '-avd', $Avd, '-port', '5554', '-no-snapshot',
    '-gpu', 'software', '-feature', '-Vulkan', '-memory', '3072', '-cores', '4'
) -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

Write-Host "Cold booting $Avd (software graphics, 3 GB RAM). Logs: $logDir"
$deadline = (Get-Date).AddMinutes(3)
$booted = $false
while ((Get-Date) -lt $deadline) {
    try {
        $bootState = & $adbPath -s emulator-5554 shell getprop sys.boot_completed 2>$null
    }
    catch {
        # Windows PowerShell can raise native stderr while ADB is still offline.
        $bootState = ''
    }
    if ($LASTEXITCODE -eq 0 -and "$bootState".Trim() -eq '1') {
        $booted = $true
        break
    }
    Start-Sleep -Seconds 3
}
if (-not $booted) {
    throw "Android did not finish booting within 3 minutes. Check $stdoutLog and $stderrLog."
}

# Forward this project's local FastAPI port after every emulator restart.
& $adbPath -s emulator-5554 reverse tcp:8000 tcp:8000
if ($LASTEXITCODE -ne 0) { throw 'Android booted, but forwarding backend port 8000 failed.' }
$installedApp = & $adbPath -s emulator-5554 shell pm path com.example.visionpark_mobile
if ($LASTEXITCODE -eq 0 -and $installedApp -match '^package:') {
    & $adbPath -s emulator-5554 shell am start -W -n com.example.visionpark_mobile/.MainActivity
    if ($LASTEXITCODE -ne 0) { throw 'Android booted, but launching Vision Park failed.' }
}
else {
    Write-Host 'Vision Park is not installed. Run Flutter with your usual environment configuration.'
}
Write-Host 'Emulator ready: emulator-5554. Keep your FastAPI backend running on port 8000.'
