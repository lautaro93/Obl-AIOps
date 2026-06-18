#!/bin/sh
# Chaos: interrumpe el trafico de red de un componente con una NetworkPolicy deny-all.
# Uso: ./interrupcion-red.sh [deployment] [segundos]
#
# NOTA: requiere un CNI que aplique NetworkPolicies. En minikube:
#   minikube start --cni=calico
# Si el CNI no las enforce, la policy se crea pero no corta trafico; en ese caso
# usar component-disconnect.sh como experimento de interrupcion equivalente.
DEPLOY="${1:-pharmago-users-service}"
SECS="${2:-30}"
NS="pharmago"
POL="chaos-netcut-$DEPLOY"

POD=$(kubectl get pod -n "$NS" -l app="$DEPLOY" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
  echo "Error: no hay pods con app=$DEPLOY en el namespace $NS."
  exit 1
fi

echo "Interrumpiendo la red de app=$DEPLOY (${SECS}s)..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: $POL
  namespace: $NS
spec:
  podSelector:
    matchLabels:
      app: $DEPLOY
  policyTypes:
    - Ingress
    - Egress
EOF

sleep "$SECS"

echo "Restaurando la red..."
kubectl delete networkpolicy "$POL" -n "$NS"
echo "Red restaurada."