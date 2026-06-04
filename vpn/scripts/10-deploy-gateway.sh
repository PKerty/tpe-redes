#!/usr/bin/env bash
# Despliega el gateway WireGuard en el cluster (namespace vpn-system).
# Renderiza wg0.conf (Site-To-Site) y wg1.conf (Client-To-Site) desde las claves,
# los publica como Secret, carga la imagen en Kind y aplica los manifiestos.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ensure_image
ensure_wg_module
require_keys

c_info "Cargando imagen $IMAGE en el cluster Kind '$CLUSTER'..."
kind load docker-image "$IMAGE" --name "$CLUSTER"

c_info "Creando namespace, Secret y ConfigMap..."
kubectl apply -f "$VPN_DIR/gateway/namespace.yaml"

update_gateway_secret   # render wg0.conf + wg1.conf desde las claves -> Secret

kubectl create configmap wg-gateway-entrypoint -n "$VPN_NS" \
  --from-file=entrypoint.sh="$VPN_DIR/gateway/entrypoint.sh" \
  --dry-run=client -o yaml | kubectl apply -f -

c_info "Aplicando Deployment + Service (NodePort)..."
kubectl apply -f "$VPN_DIR/gateway/gateway.yaml"

# Forzar recarga si el Secret/ConfigMap cambió.
kubectl rollout restart deployment/wg-gateway -n "$VPN_NS" >/dev/null 2>&1 || true
c_info "Esperando que el gateway esté listo..."
kubectl rollout status deployment/wg-gateway -n "$VPN_NS" --timeout=120s

NODE_IP="$(node_ip)"
c_ok "Gateway desplegado."
echo
echo "  Endpoint del nodo Kind : ${NODE_IP}"
echo "  Site-To-Site (wg0)     : ${NODE_IP}:${S2S_NODEPORT}/udp   pubkey: $(key_pub gw-s2s)"
echo "  Client-To-Site (wg1)   : ${NODE_IP}:${C2S_NODEPORT}/udp   pubkey: $(key_pub gw-c2s)"
echo
echo "  Logs:  kubectl logs -n ${VPN_NS} deploy/wg-gateway"
