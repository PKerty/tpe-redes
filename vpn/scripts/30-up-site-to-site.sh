#!/usr/bin/env bash
# Escenario Site-To-Site: "red corporativa" que consume servicios del cluster
# SIN instalar WireGuard en el equipo final.
#
#   corp-pc (172.20.0.50, SIN WG)  --ruta estática-->  corp-gateway (172.20.0.1, WG)
#        --túnel wg0--> gateway del cluster --> services/pods
#
# El corp-gateway está además en la red 'kind' para alcanzar el NodePort UDP.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ensure_image
require_keys

NODE_IP="$(node_ip)"
[ -n "$NODE_IP" ] || { c_err "No encuentro la IP del nodo Kind. ¿Está el cluster '$CLUSTER'?"; exit 1; }

CORP_PRIV="$(key_priv corp)"
GW_PUB="$(key_pub gw-s2s)"

c_info "Creando red corporativa '$CORP_NET' ($CORP_SUBNET)..."
# Teardown de corridas previas (los containers deben irse antes que la red).
docker rm -f corp-gateway corp-pc >/dev/null 2>&1 || true
# El gateway del bridge docker se mueve a .254 para liberar .1 para corp-gateway.
docker network rm "$CORP_NET" >/dev/null 2>&1 || true
docker network create --subnet "$CORP_SUBNET" --gateway "$CORP_BRIDGE_GW" "$CORP_NET" >/dev/null

# --- corp-gateway: con WireGuard, en corp-net y en kind ---
c_info "Levantando corp-gateway ($CORP_GW_IP) con WireGuard..."
docker rm -f corp-gateway >/dev/null 2>&1 || true
docker run -d --name corp-gateway --network "$CORP_NET" --ip "$CORP_GW_IP" \
  --cap-add NET_ADMIN --sysctl net.ipv4.ip_forward=1 \
  "$IMAGE" sleep infinity >/dev/null
docker network connect kind corp-gateway      # 2da interfaz para llegar al NodePort

docker exec corp-gateway sh -c "mkdir -p /etc/wireguard && cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${S2S_CORP_IP}/30
PrivateKey = ${CORP_PRIV}

[Peer]
PublicKey = ${GW_PUB}
Endpoint = ${NODE_IP}:${S2S_NODEPORT}
# Sólo el tráfico al cluster cruza el túnel (el resto sigue su ruta normal).
AllowedIPs = ${S2S_SUBNET}, ${SVC_CIDR}, ${POD_CIDR}
PersistentKeepalive = 25
EOF"
docker exec corp-gateway wg-quick up wg0
# ip_forward ya viene de --sysctl; aseguramos el FORWARD entre corp-net y wg0.
docker exec corp-gateway iptables -A FORWARD -j ACCEPT

# --- corp-pc: SIN WireGuard, sólo ruta estática hacia el cluster ---
c_info "Levantando corp-pc ($CORP_PC_IP) SIN WireGuard..."
docker rm -f corp-pc >/dev/null 2>&1 || true
docker run -d --name corp-pc --network "$CORP_NET" --ip "$CORP_PC_IP" \
  --cap-add NET_ADMIN "$IMAGE" sleep infinity >/dev/null
# En producción estas rutas las empuja el router corporativo / DHCP.
docker exec corp-pc sh -c "ip route add ${SVC_CIDR} via ${CORP_GW_IP} && ip route add ${POD_CIDR} via ${CORP_GW_IP}"

c_ok "Red corporativa lista."
echo
echo "  corp-pc ${CORP_PC_IP} (SIN WireGuard)  ->  corp-gateway ${CORP_GW_IP}  ->  túnel wg0  ->  cluster"
echo "  Probar:  docker exec corp-pc wg show            # vacío: corp-pc NO tiene WireGuard"
echo "           docker exec corp-gateway wg show       # túnel del gateway corporativo"
CAT_IP=$(kubectl get svc catalog -n "$APP_NS" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo '<catalog-ip>')
echo "           docker exec corp-pc curl -s -o /dev/null -w '%{http_code}\\n' http://${CAT_IP}/health"
