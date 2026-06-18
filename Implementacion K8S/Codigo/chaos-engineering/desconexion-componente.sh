#!/bin/sh
# Chaos: desconecta un componente interno escalando su deployment a 0 replicas,
# y lo reconecta despues (demuestra tambien la recuperacion del servicio).
# Uso: ./desconexion-componente.sh [deployment] [segundos]
DEPLOY="${1:-pharmago-users-service}"
SECS="${2:-30}"
NS="pharmago"

ORIG=$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)
if [ -z "$ORIG" ]; then
  echo "Error: el deployment $DEPLOY no existe en el namespace $NS."
  exit 1
fi

echo "Desconectando $DEPLOY (replicas $ORIG -> 0) por ${SECS}s..."
kubectl scale deploy "$DEPLOY" -n "$NS" --replicas=0
sleep "$SECS"

echo "Reconectando $DEPLOY (replicas 0 -> $ORIG)..."
kubectl scale deploy "$DEPLOY" -n "$NS" --replicas="$ORIG"
kubectl rollout status deploy "$DEPLOY" -n "$NS"
echo "Componente reconectado."