# Cambia el trafico del Service demo-service entre blue y green (Blue-Green deployment)
# Uso: .\switch-traffic.ps1 blue   |   .\switch-traffic.ps1 green

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("blue", "green")]
    [string]$Target
)

$ns = "pharmago"
$svc = "demo-service"

Write-Host "Cambiando '$svc' para que apunte a '$Target'..." -ForegroundColor Cyan

# El patch del selector del Service es la operacion de despliegue seguro:
# el trafico se redirige de forma atomica, solo a pods que ya estan Ready.
# Se escribe a un archivo temporal porque PowerShell mangle las comillas del
# JSON al pasarlo inline a kubectl; --patch-file evita ese problema.
$patch = '{"spec":{"selector":{"app":"demo","version":"' + $Target + '"}}}'
$tmp = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmp -Value $patch -Encoding ascii
try {
    kubectl patch service $svc -n $ns --patch-file $tmp
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error al hacer el patch del Service." -ForegroundColor Red
        exit 1
    }
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host "`nSelector actual:" -ForegroundColor Yellow
kubectl get svc $svc -n $ns -o jsonpath='{.spec.selector}'
Write-Host ""

Write-Host "`nEndpoints (IPs de los pods que reciben trafico ahora):" -ForegroundColor Yellow
kubectl get endpoints $svc -n $ns

Write-Host "`nListo. Trafico dirigido a '$Target'." -ForegroundColor Green
