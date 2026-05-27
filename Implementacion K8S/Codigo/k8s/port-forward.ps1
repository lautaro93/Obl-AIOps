# port-forward.ps1
# Levanta todos los port-forwards con puertos fijos en background
#
# Uso:
#   .\port-forward.ps1          -> inicia todos los forwards
#   .\port-forward.ps1 -Stop    -> detiene todos los forwards
#   .\port-forward.ps1 -Status  -> muestra estado de los jobs

param(
    [switch]$Stop,
    [switch]$Status
)

$jobPrefix = "pharmago-pf"

function Stop-Forwards {
    $jobs = Get-Job | Where-Object { $_.Name -like "$jobPrefix-*" }
    if ($jobs.Count -eq 0) {
        Write-Host "No hay port-forwards activos." -ForegroundColor Yellow
    } else {
        $jobs | Stop-Job
        $jobs | Remove-Job
        Write-Host "Port-forwards detenidos." -ForegroundColor Green
    }
    exit 0
}

function Show-Status {
    $jobs = Get-Job | Where-Object { $_.Name -like "$jobPrefix-*" }
    if ($jobs.Count -eq 0) {
        Write-Host "No hay port-forwards activos." -ForegroundColor Yellow
    } else {
        Write-Host "`nEstado de port-forwards:" -ForegroundColor Cyan
        $jobs | Format-Table Name, State, HasMoreData -AutoSize
    }
    exit 0
}

if ($Stop)   { Stop-Forwards }
if ($Status) { Show-Status }

# Si ya hay jobs corriendo, limpiamos primero
$existing = Get-Job | Where-Object { $_.Name -like "$jobPrefix-*" }
if ($existing.Count -gt 0) {
    Write-Host "Limpiando port-forwards anteriores..." -ForegroundColor Yellow
    $existing | Stop-Job
    $existing | Remove-Job
}

Write-Host ""
Write-Host "=== Iniciando port-forwards (puertos fijos) ===" -ForegroundColor Cyan
Write-Host ""

$forwards = @(
    @{ Name = "ui";               LocalPort = 4200;  RemotePort = 80;   Svc = "pharmago-ui" },
    @{ Name = "api-gateway";      LocalPort = 5000;  RemotePort = 80;   Svc = "pharmago-api-gateway" },
    @{ Name = "users-service";    LocalPort = 5001;  RemotePort = 80;   Svc = "pharmago-users-service" },
    @{ Name = "pharmacy-service"; LocalPort = 5002;  RemotePort = 80;   Svc = "pharmago-pharmacy-service" },
    @{ Name = "db";               LocalPort = 11433; RemotePort = 1433; Svc = "pharmago-db" },
    @{ Name = "prometheus";       LocalPort = 9090;  RemotePort = 9090; Svc = "prometheus" },
    @{ Name = "grafana";          LocalPort = 3000;  RemotePort = 3000; Svc = "grafana" },
    @{ Name = "kibana";           LocalPort = 5601;  RemotePort = 5601; Svc = "kibana" },
    @{ Name = "elasticsearch";    LocalPort = 9200;  RemotePort = 9200; Svc = "elasticsearch" }
)

foreach ($fwd in $forwards) {
    $jobName = "$jobPrefix-$($fwd.Name)"
    $svc     = $fwd.Svc
    $local   = $fwd.LocalPort
    $remote  = $fwd.RemotePort

    Start-Job -Name $jobName -ScriptBlock {
        param($svc, $local, $remote)
        kubectl port-forward "svc/$svc" "${local}:${remote}" -n pharmago 2>&1
    } -ArgumentList $svc, $local, $remote | Out-Null
}

# Esperamos un momento para que los forwards establezcan conexión
Start-Sleep -Seconds 3

Write-Host "  Frontend       ->  http://127.0.0.1:4200" -ForegroundColor White
Write-Host "  API Gateway    ->  http://127.0.0.1:5000" -ForegroundColor Green
Write-Host "  Users Service  ->  http://127.0.0.1:5001" -ForegroundColor White
Write-Host "  Pharmacy Svc   ->  http://127.0.0.1:5002" -ForegroundColor White
Write-Host "  SQL Server     ->  127.0.0.1,11433  (sa / Str0ngP@ssword!)" -ForegroundColor White
Write-Host "  Prometheus     ->  http://127.0.0.1:9090" -ForegroundColor White
Write-Host "  Grafana        ->  http://127.0.0.1:3000  (admin/admin)" -ForegroundColor White
Write-Host "  Kibana         ->  http://127.0.0.1:5601" -ForegroundColor White
Write-Host "  Elasticsearch  ->  http://127.0.0.1:9200" -ForegroundColor White
Write-Host ""
Write-Host "Para detener:  .\port-forward.ps1 -Stop" -ForegroundColor Yellow
Write-Host "Para estado:   .\port-forward.ps1 -Status" -ForegroundColor Yellow
Write-Host ""

# Verificamos que el api-gateway respondió (el más importante para el test de rate-limit)
Write-Host "Verificando API Gateway..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:5000/metrics" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    Write-Host "  API Gateway OK (HTTP $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "  API Gateway aun no responde - esperá unos segundos y reintentá" -ForegroundColor Yellow
    Write-Host "  (Normal si los pods recién arrancaron)" -ForegroundColor Yellow
}

Write-Host ""
