#!/usr/bin/env bash
# PC externo: Alpine SIN WireGuard en la red 'kind' (misma red que el admin).
# Demuestra que fuera de la VPN no se alcanzan los servicios internos del cluster.
#   - Puede acceder a localhost:80 (Ingress, usuario normal).
#   - NO puede alcanzar ClusterIP (10.96.0.0/16) ni pods (10.244.0.0/16).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

c_info "Levantando external-pc (Alpine SIN WireGuard) en la red kind..."
docker rm -f external-pc >/dev/null 2>&1 || true
docker run -d --name external-pc --network kind \
  alpine:3.20 sleep infinity >/dev/null

c_info "Instalando curl en external-pc..."
docker exec external-pc apk add --no-cache curl >/dev/null 2>&1

NODE_IP=$(node_ip)
CAT_IP=$(kubectl get svc catalog -n "$APP_NS" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo '<catalog-ip>')

c_ok "PC externo listo."
echo
echo "  external-pc (SIN WireGuard, SIN VPN) en la red kind."
echo "  Probar:  docker exec external-pc wg show                    # command not found"
echo "           docker exec external-pc curl -s http://$NODE_IP/   # 200 (Ingress, usuario normal)"
echo "           docker exec external-pc curl -s http://$CAT_IP/health  # timeout (sin ruta al ClusterIP)"
