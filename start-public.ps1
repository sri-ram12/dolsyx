# DOLSYX - Start App (Fast Dev Mode) + Public Tunnel
# This script starts the backend and frontend in dev mode, and exposes port 4000 via SSH tunnel.

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  DOLSYX - Starting Fast Dev Mode & Tunnel" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Kill any existing processes on ports 4000, 3000, 3001
Write-Host "[1/3] Cleaning up old port bindings..." -ForegroundColor Yellow
try {
    $ports = @(3000, 3001, 4000)
    foreach ($port in $ports) {
        $procIds = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess
        if ($procIds) {
            foreach ($procId in $procIds) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            }
        }
    }
} catch {}
Start-Sleep -Seconds 2

# Start Backend on port 4000
Write-Host "[2/3] Starting Express Backend (port 4000)..." -ForegroundColor Yellow
$backendDir = Join-Path $PSScriptRoot "backend"
$backendCmd = "cd `"$backendDir`"; `$env:PORT='4000'; npm run dev"
$backend = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", $backendCmd -PassThru
Write-Host "  Backend PID: $($backend.Id)" -ForegroundColor Green

# Start Frontend on port 3000
Write-Host "      Starting Next.js Frontend (port 3000)..." -ForegroundColor Yellow
$frontendDir = Join-Path $PSScriptRoot "frontend"
$frontendCmd = "cd `"$frontendDir`"; npm run dev"
$frontend = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", $frontendCmd -PassThru
Write-Host "  Frontend PID: $($frontend.Id)" -ForegroundColor Green

# Wait for servers to initialize
Write-Host "  Waiting for dev servers to boot up..." -ForegroundColor Yellow
Start-Sleep -Seconds 12

# Open SSH Tunnel using localhost.run (free, no signup, no password)
Write-Host ""
Write-Host "[3/3] Exposing server publicly via localhost.run tunnel..." -ForegroundColor Yellow
Write-Host "  ===========================================================" -ForegroundColor Green
Write-Host "  Your public HTTPS URL will appear in the window below!" -ForegroundColor Green
Write-Host "  FREE - No signup, no password required!" -ForegroundColor Green
Write-Host "  ===========================================================" -ForegroundColor Green
Write-Host ""

# Cloudflare Tunnel via npx
$tunnelCmd = "Write-Host 'DOLSYX Public Tunnel via Cloudflare - port 4000' -ForegroundColor Cyan; Write-Host 'Your public URL will appear below (.trycloudflare.com):' -ForegroundColor Yellow; Write-Host ''; npx -y cloudflared tunnel --url http://localhost:4000"
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", $tunnelCmd -WindowStyle Normal

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  App is running in fast development mode!" -ForegroundColor Green
Write-Host "  Local URL:  http://localhost:4000" -ForegroundColor Green
Write-Host "  Public URL: Check the newly opened tunnel terminal." -ForegroundColor Magenta
Write-Host "==================================================" -ForegroundColor Cyan

