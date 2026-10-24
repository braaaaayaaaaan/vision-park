
$ErrorActionPreference = "Stop"

# Resolve project paths
$MobileDir = $PSScriptRoot
$ProjectRoot = Split-Path $MobileDir -Parent

# Start FastAPI from project root
Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-Command",
    "Set-Location '$ProjectRoot'; uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000"
)

# Set up ADB reverse
adb reverse tcp:8000 tcp:8000

if ($LASTEXITCODE -ne 0) {
    Write-Error "ADB reverse failed. Check your Android connection."
    exit 1
}

# Start Flutter from mobile directory
Set-Location $MobileDir

flutter run --debug --dart-define-from-file=env/development.json
