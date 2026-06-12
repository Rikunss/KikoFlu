# Konfigurasi
$package = "com.meteor.kikoeruflutter"
$output = "C:\Users\023 OFF~1\Desktop\kikoflu_debug.log"
Write-Host "=== KikoFlu Log Capture ===" -ForegroundColor Cyan
Write-Host "Package: $package"
# Connect wireless (ganti IP sesuai device)
Write-Host "`nConnecting to wireless device..." -ForegroundColor Yellow
adb connect 192.168.18.7:41213 | Out-Null
# Cek device
$devices = adb devices
if ($devices -notmatch "device$") {
    Write-Host "ERROR: No device connected!" -ForegroundColor Red
    exit 1
}
# Bersihkan log
Write-Host "Clearing old logs..." -ForegroundColor Yellow
adb logcat -c
# Ambil PID
Write-Host "Getting PID for $package..." -ForegroundColor Yellow
$pidOutput = adb shell pidof $package 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pidOutput)) {
    # Fallback: cari via ps
    $psOutput = adb shell ps -A 2>&1 | Select-String [regex]::Escape($package)
    if ($psOutput) {
        $parts = $psOutput -split '\s+'
        $pid = $parts[1]
    } else {
        Write-Host "ERROR: App not running! Launch the app first." -ForegroundColor Red
        exit 1
    }
} else {
    $pid = $pidOutput.Trim()
}
Write-Host "PID: $pid" -ForegroundColor Green
Write-Host "`nStarting capture... (Ctrl+C to stop)" -ForegroundColor Cyan
Write-Host "Output: $output`n" -ForegroundColor Gray
# Start capture
adb logcat -v threadtime --pid=$pid 2>&1 | Tee-Object -FilePath $output