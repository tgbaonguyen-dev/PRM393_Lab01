<#
.SYNOPSIS
    Script khoi chay he thong PRM393 Lab 01 (Backend, Web, Flutter Desktop).
.DESCRIPTION
    Tu dong mo cac cua so PowerShell rieng biet cho tung service.
.PARAMETER All
    Chay ca 3 thanh phan: Backend, Web va Desktop (Mac dinh).
.PARAMETER Backend
    Chi khoi chay Backend Dart Shelf API (Port 8080).
.PARAMETER Web
    Chi khoi chay Student Web Checkin Next.js (Port 3000).
.PARAMETER Desktop
    Chi khoi chay Flutter Desktop Windows App.
.PARAMETER NoDesktop
    Chi khoi chay Backend va Web (bo qua Desktop).
#>

param(
    [switch]$All,
    [switch]$Backend,
    [switch]$Web,
    [switch]$Desktop,
    [switch]$NoDesktop
)

$rootDir = $PSScriptRoot
if (-not $rootDir) {
    $rootDir = Get-Location
}

if (-not $Backend -and -not $Web -and -not $Desktop -and -not $NoDesktop) {
    $All = $true
}

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "   PRM393 ATTENDANCE SYSTEM - LAUNCHER" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Thu muc goc: $rootDir" -ForegroundColor DarkGray

$rootEnv = Join-Path $rootDir ".env.local"
$webEnv = Join-Path $rootDir "apps\web\.env.local"

if (-not (Test-Path $rootEnv)) {
    Write-Host "[!] Canh bao: Khong tim thay $rootEnv. Dang copy tu .env.example..." -ForegroundColor Yellow
    $exampleEnv = Join-Path $rootDir ".env.example"
    if (Test-Path $exampleEnv) {
        Copy-Item $exampleEnv $rootEnv
    }
}

if (-not (Test-Path $webEnv)) {
    Write-Host "[!] Canh bao: Khong tim thay $webEnv. Dang copy tu .env.example..." -ForegroundColor Yellow
    $webExample = Join-Path $rootDir "apps\web\.env.example"
    if (Test-Path $webExample) {
        Copy-Item $webExample $webEnv
    }
}

function Start-ServiceWindow {
    param(
        [string]$Title,
        [string]$WorkingDir,
        [string]$Command,
        [ConsoleColor]$Color = [ConsoleColor]::Green
    )

    Write-Host "[+] Dang khoi dong: $Title" -ForegroundColor $Color
    $cmd = "`$host.UI.RawUI.WindowTitle = '$Title'; Set-Location -LiteralPath '$WorkingDir'; Write-Host '==================================================' -ForegroundColor Cyan; Write-Host '  $Title' -ForegroundColor Yellow; Write-Host '  Lenh: $Command' -ForegroundColor DarkGray; Write-Host '==================================================' -ForegroundColor Cyan; $Command"

    Start-Process powershell.exe -WorkingDirectory $WorkingDir -ArgumentList "-NoExit", "-Command", $cmd
}

if ($All -or $Backend -or $NoDesktop) {
    $backendDir = Join-Path $rootDir "backend"
    Start-ServiceWindow -Title "[PRM393] Backend Dart Shelf API (Port 8080)" -WorkingDir $backendDir -Command "dart run bin/server.dart" -Color Cyan
}

if ($All -or $Web -or $NoDesktop) {
    $webDir = Join-Path $rootDir "apps\web"
    Start-ServiceWindow -Title "[PRM393] Student Web Check-in (Port 3000)" -WorkingDir $webDir -Command "npm run dev" -Color Green
}

if (($All -or $Desktop) -and -not $NoDesktop) {
    $desktopDir = Join-Path $rootDir "apps\desktop"
    Start-ServiceWindow -Title "[PRM393] Flutter Desktop Application (Windows)" -WorkingDir $desktopDir -Command "flutter run -d windows" -Color Magenta
}

Write-Host ""
Write-Host "[V] Da gui lenh khoi chay cac dich vu thanh cong!" -ForegroundColor Green
Write-Host "Dia chi dich vu:" -ForegroundColor Yellow
if ($All -or $Backend -or $NoDesktop) {
    Write-Host "   * Backend API : http://localhost:8080" -ForegroundColor Cyan
}
if ($All -or $Web -or $NoDesktop) {
    Write-Host "   * Web Check-in: http://localhost:3000/checkin" -ForegroundColor Green
}
if (($All -or $Desktop) -and -not $NoDesktop) {
    Write-Host "   * Desktop App : Ứng dung Flutter Windows dang khoi dong..." -ForegroundColor Magenta
}
Write-Host "========================================================" -ForegroundColor Cyan
