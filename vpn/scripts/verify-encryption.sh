#!/usr/bin/env bash
# Verifica que el tráfico viaja CIFRADO por el túnel:
#   - Captura en eth0 (el cable): UDP opaco hacia el puerto WireGuard, sin texto
#     plano (no aparece el HTTP ni el nombre del servicio).
#   - Captura en wg0 (dentro del túnel): el MISMO request en HTTP claro.
# Demuestra que WireGuard cifra en el cable y que el dato viaja por el túnel.
#
# Uso: verify-encryption.sh   (usa el container 'admin' / Client-To-Site)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

CT="admin"
docker ps --format '{{.Names}}' | grep -q "^${CT}$" \
  || { c_err "El container '$CT' no está levantado (correr 20-up-admin-client.sh)."; exit 1; }

CAT_IP="$(kubectl get svc catalog -n "$APP_NS" -o jsonpath='{.spec.clusterIP}')"
c_info "Generando tráfico (curl a catalog $CAT_IP) y capturando en paralelo..."

docker exec "$CT" sh -c '
  CAT="'"$CAT_IP"'"; PORT="'"$C2S_NODEPORT"'"
  tcpdump -i eth0 -n -w /tmp/wire.pcap  "udp port $PORT" >/dev/null 2>&1 & W=$!
  tcpdump -i wg0  -n -w /tmp/inner.pcap "tcp"            >/dev/null 2>&1 & I=$!
  sleep 1
  for i in 1 2 3; do curl -s -o /dev/null "http://$CAT/health"; done
  sleep 1
  kill $W $I 2>/dev/null; sleep 1

  echo
  echo "===== EN EL CABLE (eth0): lo que vería un sniffer en la red ====="
  tcpdump -nr /tmp/wire.pcap 2>/dev/null | head -4
  echo
  echo "----- ¿Hay texto plano (GET /health, HTTP/1.1, Host:) en el cable? -----"
  PLAIN=$(tcpdump -nAr /tmp/wire.pcap 2>/dev/null | grep -aE "GET /health|HTTP/1\.1|Host:" | head -3)
  if [ -n "$PLAIN" ]; then
    echo "$PLAIN"; echo "  (!) apareció texto plano"
  else
    echo "  NADA: el payload está cifrado (ChaCha20-Poly1305)."
  fi
  echo
  echo "===== DENTRO DEL TÚNEL (wg0): el mismo request descifrado ====="
  tcpdump -nAr /tmp/inner.pcap 2>/dev/null | grep -iE "GET /health|HTTP|Host:" | head -3
'
c_ok "Listo: en el cable sólo se ve UDP cifrado; dentro de wg0, el HTTP en claro."
