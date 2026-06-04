#!/usr/bin/env bash
# Desarma la solución de acceso remoto. Por defecto NO toca la app the-store ni
# el cluster Kind (sólo lo que agrega este TPE).
#   --all   además borra las claves generadas (vpn/keys/).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

c_info "Quitando containers y red corporativa..."
docker rm -f admin corp-gateway corp-pc >/dev/null 2>&1 || true
docker network rm "$CORP_NET" >/dev/null 2>&1 || true

c_info "Quitando NetworkPolicies de $APP_NS..."
kubectl delete -f "$VPN_DIR/network-policies/" --ignore-not-found >/dev/null 2>&1 || true

c_info "Quitando el gateway (namespace $VPN_NS)..."
kubectl delete namespace "$VPN_NS" --ignore-not-found >/dev/null 2>&1 || true

if [ "${1:-}" = "--all" ]; then
  c_warn "Borrando claves en $KEYS_DIR..."
  rm -rf "$KEYS_DIR"
fi

c_ok "Teardown completo. La app the-store y el cluster quedan intactos."
