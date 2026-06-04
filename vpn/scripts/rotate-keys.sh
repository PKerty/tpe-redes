#!/usr/bin/env bash
# Rotación de claves de un peer SIN reiniciar el gateway:
#   1) genera un par nuevo para el peer,
#   2) actualiza el peer en el gateway EN CALIENTE (wg set: quita la vieja, agrega
#      la nueva),
#   3) reconfigura el cliente con la clave nueva y reconecta,
#   4) persiste el Secret del gateway.
# La clave pública anterior queda invalidada de inmediato.
#
# Uso: rotate-keys.sh [admin|corp]     (default: admin)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh
require_keys

PEER="${1:-admin}"
case "$PEER" in
  admin) IFACE="$C2S_IF"; CLIENT_CT="admin";        ALLOWED="${C2S_ADMIN_IP}/32";;
  corp)  IFACE="$S2S_IF"; CLIENT_CT="corp-gateway"; ALLOWED="${S2S_CORP_IP}/32,${CORP_SUBNET}";;
  *) c_err "Uso: rotate-keys.sh [admin|corp]"; exit 1;;
esac

GWPOD="$(gateway_pod)"
[ -n "$GWPOD" ] || { c_err "No encuentro el pod del gateway."; exit 1; }
docker ps --format '{{.Names}}' | grep -q "^${CLIENT_CT}$" \
  || { c_err "El cliente '$CLIENT_CT' no está levantado."; exit 1; }

OLD_PUB="$(key_pub "$PEER")"
c_info "Rotando '$PEER' (interfaz $IFACE del gateway)."
echo "  clave pública ANTERIOR: $OLD_PUB"

# 1) Par nuevo
NEW_PRIV="$(docker run --rm "$IMAGE" wg genkey)"
NEW_PUB="$(printf '%s' "$NEW_PRIV" | docker run --rm -i "$IMAGE" wg pubkey)"
printf '%s' "$NEW_PRIV" > "$KEYS_DIR/$PEER.key"; chmod 600 "$KEYS_DIR/$PEER.key"
printf '%s' "$NEW_PUB"  > "$KEYS_DIR/$PEER.pub"
echo "  clave pública NUEVA:    $NEW_PUB"

# 2) Gateway en caliente: quitar peer viejo, agregar nuevo
c_info "Actualizando el peer en el gateway (en caliente)..."
kubectl exec -n "$VPN_NS" "$GWPOD" -c wg-gateway -- wg set "$IFACE" peer "$OLD_PUB" remove
kubectl exec -n "$VPN_NS" "$GWPOD" -c wg-gateway -- wg set "$IFACE" peer "$NEW_PUB" allowed-ips "$ALLOWED"

# 3) Persistir Secret (para sobrevivir a un reinicio del pod)
update_gateway_secret

# 4) Reconfigurar el cliente y reconectar
c_info "Reconfigurando el cliente '$CLIENT_CT' y reconectando..."
docker exec "$CLIENT_CT" sh -c "sed -i 's#^PrivateKey = .*#PrivateKey = ${NEW_PRIV}#' /etc/wireguard/wg0.conf; wg-quick down wg0 >/dev/null 2>&1; wg-quick up wg0 >/dev/null 2>&1"

sleep 2
c_info "Verificación:"
if kubectl exec -n "$VPN_NS" "$GWPOD" -c wg-gateway -- wg show "$IFACE" | grep -q "$OLD_PUB"; then
  c_err "  La clave vieja TODAVÍA figura en el gateway (rotación incompleta)."
else
  c_ok "  La clave vieja ya NO figura en el gateway (invalidada)."
fi
kubectl exec -n "$VPN_NS" "$GWPOD" -c wg-gateway -- wg show "$IFACE" | grep -q "$NEW_PUB" \
  && c_ok "  La clave nueva está activa en el gateway." || c_err "  La clave nueva no aparece."
c_ok "Rotación de '$PEER' completada."
