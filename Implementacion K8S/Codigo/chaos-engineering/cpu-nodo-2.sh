#!/bin/sh
# Mueve la metrica "CPU %" del NODO con un pod de chaos SIN limites de CPU.
# (Los microservicios estan capados a 500m, por eso NO mueven el nodo; este pod no.)
# Con suficientes cores tambien dispara la alerta "CPU del nodo alta" (>80%).
# Uso: ./cpu-nodo-2.sh [cores] [segundos]
#   cores: cuantos nucleos saturar (el nodo tiene 12). 8 ~ 67%, 11 ~ 90%.
CORES="${1:-8}"
SECS="${2:-300}"

echo "Pod de chaos: stress --cpu $CORES por ${SECS}s. Mira 'CPU %' del nodo en Grafana."
echo "  (para disparar la alerta >80%, usa ~11 cores y manten >5 min por el pending)"
kubectl run chaos-cpu-nodo --image=polinux/stress --restart=Never -n pharmago --rm -i -- \
  stress --cpu "$CORES" --timeout "${SECS}s"
echo "Listo. El pod de chaos se elimino."