#!/bin/sh
# Demo de los 6 experimentos de caos (duraciones cortas), con pausa para observar Grafana.
# Para DISPARAR una alerta (no solo ver el panel) corre el script numerado con su duracion larga.
# Uso: ./run-all.sh
DIR=$(dirname "$0")

pause() {
  echo ""
  echo ">>> $1"
  echo "    (observa Grafana y presiona Enter para continuar)"
  read _
}

pause "1) Inyeccion de requests";                          sh "$DIR/inyeccion-requests.sh" 500
pause "2) Sobrecarga de CPU (pod) -> alerta (4)";          sh "$DIR/cpu-throttling-pod-4.sh" pharmago-api-gateway 60
pause "3) Sobrecarga de memoria (pod) -> alerta (5)";      sh "$DIR/memoria-pod-5.sh" pharmago-api-gateway 200
pause "4) Sobrecarga de storage -> alerta (3)";            sh "$DIR/disco-3.sh" pharmago-api-gateway 300
pause "5) Interrupcion de trafico de red";                sh "$DIR/interrupcion-red.sh" pharmago-users-service 30
pause "6) Desconexion de componente interno";             sh "$DIR/desconexion-componente.sh" pharmago-users-service 30

echo ""
echo "Demo terminada."
echo "Las metricas de NODO (alertas 1 y 2) se prueban aparte:"
echo "  sh cpu-nodo-2.sh 11 360       # dispara alerta (2) CPU del nodo alta"
echo "  sh memoria-nodo-1.sh 11000 360  # dispara alerta (1) Memoria del nodo alta"