#!/usr/bin/env bash
# Entrypoint del pod gateway WireGuard del cluster.
# - Levanta wg0 (Site-To-Site) y wg1 (Client-To-Site) desde /etc/wireguard.
# - Habilita IP forwarding y NAT (MASQUERADE) de las subredes túnel hacia los
#   CIDRs del cluster, para que el tráfico de los peers alcance services y pods.
set -euo pipefail

: "${C2S_SUBNET:?}"; : "${S2S_SUBNET:?}"; : "${SVC_CIDR:?}"; : "${POD_CIDR:?}"

# ip_forward lo habilita el initContainer 'enable-forwarding' (en un pod
# /proc/sys/net es read-only con sólo NET_ADMIN). Acá sólo verificamos.
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
  echo "[gateway] ADVERTENCIA: ip_forward != 1 (¿corrió el initContainer?)"
fi

echo "[gateway] levantando interfaces WireGuard"
wg-quick up wg0    # Site-To-Site
wg-quick up wg1    # Client-To-Site

echo "[gateway] NAT subredes túnel -> CIDRs del cluster (services/pods)"
for sub in "$C2S_SUBNET" "$S2S_SUBNET"; do
  iptables -t nat -A POSTROUTING -s "$sub" -d "$SVC_CIDR" -j MASQUERADE
  iptables -t nat -A POSTROUTING -s "$sub" -d "$POD_CIDR" -j MASQUERADE
done
for ifc in wg0 wg1; do
  iptables -A FORWARD -i "$ifc" -j ACCEPT
  iptables -A FORWARD -o "$ifc" -j ACCEPT
done

echo "[gateway] estado de WireGuard:"
wg show

echo "[gateway] túneles arriba. Esperando handshakes de los peers."
# Mantiene el pod vivo; reacciona a SIGTERM bajando las interfaces.
trap 'echo "[gateway] bajando"; wg-quick down wg1 || true; wg-quick down wg0 || true; exit 0' TERM INT
sleep infinity &
wait
