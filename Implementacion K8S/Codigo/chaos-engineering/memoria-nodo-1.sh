#!/bin/sh
# Mueve la metrica "Memoria usada %" del NODO con un pod de chaos SIN limites de RAM.
# Con suficiente memoria tambien dispara la alerta "Memoria del nodo alta" (>85%).
# Uso: ./memoria-nodo-1.sh [MB] [segundos]
#   MB: cuanta RAM reservar (el nodo tiene ~15 GB). 4000 ~ +25%, 11000 ~ >85%.
#   OJO: no te pases del total disponible o el nodo hace OOM y mata otros pods.
MB="${1:-4000}"
SECS="${2:-300}"

echo "Pod de chaos: reservando ${MB}MB de RAM por ${SECS}s. Mira 'Memoria usada %' del nodo."
echo "  (para disparar la alerta >85% usa ~11000 MB, con cuidado de no pasar el total)"
kubectl run chaos-mem-nodo --image=polinux/stress --restart=Never -n pharmago --rm -i -- \
  stress --vm 1 --vm-bytes "${MB}M" --vm-hold --timeout "${SECS}s"
echo "Listo. El pod de chaos se elimino."