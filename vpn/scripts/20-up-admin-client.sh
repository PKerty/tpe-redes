#!/usr/bin/env bash
# Escenario Client-To-Site: levanta el "laptop admin" como container WireGuard,
# establece el túnel contra wg1 del gateway y prepara kubectl apuntando al API
# server POR EL TÚNEL (https://10.96.0.1). Deja el container vivo para la demo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ensure_image
require_keys

NODE_IP="$(node_ip)"
[ -n "$NODE_IP" ] || { c_err "No encuentro la IP del nodo Kind. ¿Está el cluster '$CLUSTER' levantado?"; exit 1; }

ADMIN_PRIV="$(key_priv admin)"
GW_PUB="$(key_pub gw-c2s)"

c_info "Recreando container 'admin' en la red kind..."
docker rm -f admin >/dev/null 2>&1 || true
docker run -d --name admin --network kind \
  --cap-add NET_ADMIN \
  "$IMAGE" sleep infinity >/dev/null

c_info "Escribiendo configuración WireGuard del admin (wg0)..."
docker exec admin sh -c "mkdir -p /etc/wireguard && cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${C2S_ADMIN_IP}/24
PrivateKey = ${ADMIN_PRIV}

[Peer]
PublicKey = ${GW_PUB}
Endpoint = ${NODE_IP}:${C2S_NODEPORT}
# Mínimo privilegio: sólo estas subredes del cluster cruzan el túnel.
AllowedIPs = ${C2S_SUBNET}, ${SVC_CIDR}, ${POD_CIDR}
PersistentKeepalive = 25
EOF"

c_info "Levantando túnel..."
docker exec admin wg-quick up wg0

c_info "Preparando kubeconfig (server -> https://${APISERVER_IP}:443 por el túnel)..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
kind get kubeconfig --name "$CLUSTER" > "$TMP/admin.kubeconfig"
sed -i -E "s#server: https://127\\.0\\.0\\.1:[0-9]+#server: https://${APISERVER_IP}:443#" "$TMP/admin.kubeconfig"
docker cp "$TMP/admin.kubeconfig" admin:/root/admin.kubeconfig >/dev/null

c_ok "Cliente admin conectado."
echo
echo "  Túnel:   ${C2S_ADMIN_IP}  <->  ${C2S_GW_IP} (gateway wg1)"
echo "  Probar:  docker exec admin wg show"
echo "           docker exec admin kubectl --kubeconfig /root/admin.kubeconfig get nodes"
echo "           docker exec admin ping -c2 ${C2S_GW_IP}"
