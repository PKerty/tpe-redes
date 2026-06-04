#!/usr/bin/env bash
# Orquestador: levanta toda la solución de acceso remoto en orden, sobre un
# cluster the-store ya desplegado. Pensado para la demo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

c_info "==> 0/5  Generando claves";                 ./00-gen-keys.sh
c_info "==> 1/5  Desplegando gateway WireGuard";     ./10-deploy-gateway.sh
c_info "==> 2/5  Cliente admin (Client-To-Site)";    ./20-up-admin-client.sh
c_info "==> 3/5  Red corporativa (Site-To-Site)";    ./30-up-site-to-site.sh
c_info "==> 4/5  NetworkPolicies (segmentación)";    ./40-apply-netpol.sh
c_info "==> 5/5  Verificación end-to-end";           ./90-verify.sh
