#!/usr/bin/env bash
# Aplica las NetworkPolicies de segmentación al namespace the-store:
# default-deny de ingress + una regla mínima por servicio.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

c_info "Aplicando NetworkPolicies en el namespace $APP_NS ..."
kubectl apply -f "$VPN_DIR/network-policies/"

echo
kubectl get networkpolicy -n "$APP_NS"
echo
c_ok "Políticas aplicadas. Verificar con: vpn/scripts/90-verify.sh"
