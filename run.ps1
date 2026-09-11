Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " KHOI CHAY TOAN BO HE THONG PRM393 (PowerShell)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

$root = $PSScriptRoot

Write-Host "[1/3] Khoi dong Dart Shelf Backend (Port 8080)..." -ForegroundColor Yellow
Start-Process cmd -ArgumentList "/k", "cd /d `"$root\backend`" && dart run bin/server.dart"

Start-Sleep -Seconds 2

Write-Host "[2/3] Khoi dong Next.js Student Web (Port 3000)..." -ForegroundColor Yellow
Start-Process cmd -ArgumentList "/k", "cd /d `"$root\apps\web`" && npm run dev"

Start-Sleep -Seconds 2

Write-Host "[3/3] Khoi dong Flutter Desktop Windows App..." -ForegroundColor Yellow
Start-Process cmd -ArgumentList "/k", "cd /d `"$root\apps\desktop`" && flutter run -d windows"

Write-Host "========================================================" -ForegroundColor Green
Write-Host " DA KHOI CHAY 3 UNG DUNG TRONG CAC CUA SO RIENG BIET!" -ForegroundColor Green
Write-Host " - Dart Backend:  http://localhost:8080" -ForegroundColor White
Write-Host " - Student Web:   http://localhost:3000/checkin" -ForegroundColor White
Write-Host " - Desktop App:   Cua so Windows Native" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Green
