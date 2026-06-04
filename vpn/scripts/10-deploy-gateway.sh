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

GW_S2S_PRIV="$(key_priv gw-s2s)"
GW_C2S_PRIV="$(key_priv gw-c2s)"
CORP_PUB="$(key_pub corp)"
ADMIN_PUB="$(key_pub admin)"

c_info "Cargando imagen $IMAGE en el cluster Kind '$CLUSTER'..."
kind load docker-image "$IMAGE" --name "$CLUSTER"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- wg0: Site-To-Site (peer = gateway corporativo) ---
cat > "$TMP/wg0.conf" <<EOF
[Interface]
Address = ${S2S_GW_IP}/30
ListenPort = ${S2S_LISTEN}
PrivateKey = ${GW_S2S_PRIV}

[Peer]
# Gateway de la red corporativa
PublicKey = ${CORP_PUB}
AllowedIPs = ${S2S_CORP_IP}/32, ${CORP_SUBNET}
EOF

# --- wg1: Client-To-Site (peer = admin remoto) ---
cat > "$TMP/wg1.conf" <<EOF
[Interface]
Address = ${C2S_GW_IP}/24
ListenPort = ${C2S_LISTEN}
PrivateKey = ${GW_C2S_PRIV}

[Peer]
# Admin remoto (mínimo privilegio: sólo su IP de túnel)
PublicKey = ${ADMIN_PUB}
AllowedIPs = ${C2S_ADMIN_IP}/32
EOF

c_info "Creando namespace, Secret y ConfigMap..."
kubectl apply -f "$VPN_DIR/gateway/namespace.yaml"

kubectl create secret generic wg-gateway-conf -n "$VPN_NS" \
  --from-file=wg0.conf="$TMP/wg0.conf" \
  --from-file=wg1.conf="$TMP/wg1.conf" \
  --dry-run=client -o yaml | kubectl apply -f -

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
