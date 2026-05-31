# Despliega el demo Blue-Green (blue + green + service) en el namespace pharmago
# Uso: .\apply.ps1

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ns = "pharmago"

Write-Host "=== Aplicando demo Blue-Green ===" -ForegroundColor Green
kubectl apply -f "$dir\deployment-blue.yaml" -f "$dir\deployment-green.yaml" -f "$dir\service.yaml"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error aplicando los manifiestos." -ForegroundColor Red
    exit 1
}

Write-Host "`nEsperando a que blue y green esten Ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l "app=demo,version=blue"  -n $ns --timeout=120s
kubectl wait --for=condition=ready pod -l "app=demo,version=green" -n $ns --timeout=120s

Write-Host "`nEstado de los pods:" -ForegroundColor Yellow
kubectl get pods -n $ns -l app=demo -o wide

Write-Host "`nService:" -ForegroundColor Yellow
kubectl get svc demo-service -n $ns

$sel = kubectl get svc demo-service -n $ns -o jsonpath='{.spec.selector.version}'
Write-Host "`nService apuntando actualmente a: $sel" -ForegroundColor Cyan
Write-Host "Para cambiar el trafico:  .\switch-traffic.ps1 green   (o blue)" -ForegroundColor Gray
