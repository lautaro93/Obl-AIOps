#!/bin/sh
# Dispara la alerta "CPU throttling de pod" generando CPU sostenida en un pod
# con limits.cpu=500m: el cgroup lo frena y rate(container_cpu_cfs_throttled_seconds_total) sube > 1.
#
# IMPORTANTE: la alerta tiene un pending period de 5m, asi que hay que sostener
# la carga al menos ~6 minutos para que pase de Pending a Firing.
#
# Uso: ./cpu-throttling-pod-4.sh [deployment] [segundos]
DEPLOY="${1:-pharmago-api-gateway}"
SECS="${2:-360}"

POD=$(kubectl get pod -n pharmago -l app="$DEPLOY" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
  echo "Error: no hay pods con app=$DEPLOY en el namespace pharmago."
  exit 1
fi

echo "Generando throttling en $POD (limits.cpu=500m) por ${SECS}s (~$((SECS/60)) min)..."
echo "Mira en Grafana: Alerting -> 'CPU throttling de pod'."
echo "  Pending ~5m -> luego Firing. No cortes antes de los 6 min."

# 8 loops compiten por 0.5 core -> throttling sostenido. Se matan al terminar
# para no dejar procesos huerfanos pegando la CPU del pod.
kubectl exec -n pharmago "$POD" -- sh -c '
pids=""
i=0
while [ $i -lt 8 ]; do (while :; do :; done) & pids="$pids $!"; i=$((i+1)); done
sleep '"$SECS"'
kill $pids 2>/dev/null
'

echo "Listo. La carga termino. La alerta vuelve a Normal tras unos minutos."