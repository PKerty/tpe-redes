#!/usr/bin/env bash
# Verificación end-to-end de la solución. Imprime PASS/FAIL por cada chequeo.
# Cubre: app funcional, Client-To-Site, segmentación por NetworkPolicies y
# (si está levantado) Site-To-Site.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

PASS=0; FAIL=0
ok()   { c_ok   "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { c_err  "  FAIL  $1"; FAIL=$((FAIL+1)); }

# code <url> desde un container docker
dcode() { docker exec "$1" curl -s -o /dev/null -w "%{http_code}" --max-time 4 "$2" 2>/dev/null || echo 000; }
# code <url> desde un pod del cluster
kcode() { kubectl exec -n "$APP_NS" "$1" -- curl -s -o /dev/null -w "%{http_code}" --max-time 4 "$2" 2>/dev/null || echo 000; }

CAT_IP=$(kubectl get svc catalog -n "$APP_NS" -o jsonpath='{.spec.clusterIP}')
ORD_IP=$(kubectl get svc orders  -n "$APP_NS" -o jsonpath='{.spec.clusterIP}')
UI_POD=$(kubectl get pod -n "$APP_NS" -l app.kubernetes.io/name=ui      -o jsonpath='{.items[0].metadata.name}')
CAT_POD=$(kubectl get pod -n "$APP_NS" -l app.kubernetes.io/name=catalog -o jsonpath='{.items[0].metadata.name}')

c_info "== App funcional =="
[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost/)" = "200" ] \
  && ok "Ingress -> UI responde 200" || bad "Ingress -> UI"
[ "$(kcode "$UI_POD" "http://$ORD_IP/actuator/health")" = "200" ] \
  && ok "UI -> Orders (llamada legítima) permitida" || bad "UI -> Orders"

c_info "== Client-To-Site (admin remoto) =="
if docker ps --format '{{.Names}}' | grep -q '^admin$'; then
  docker exec admin wg show wg0 >/dev/null 2>&1 && ok "Túnel admin (wg0) levantado" || bad "Túnel admin"
  [ "$(docker exec admin kubectl --kubeconfig /root/admin.kubeconfig get nodes --no-headers 2>/dev/null | wc -l)" -ge 1 ] \
    && ok "kubectl por el túnel (API server 10.96.0.1) funciona" || bad "kubectl por el túnel"
  [ "$(dcode admin "http://$CAT_IP/health")" = "200" ] \
    && ok "admin -> Catalog permitido (200)" || bad "admin -> Catalog"
else
  c_warn "  (container 'admin' no está levantado; correr 20-up-admin-client.sh)"
fi

c_info "== Segmentación por NetworkPolicies =="
if kubectl get netpol default-deny-ingress -n "$APP_NS" >/dev/null 2>&1; then
  if docker ps --format '{{.Names}}' | grep -q '^admin$'; then
    [ "$(dcode admin "http://$ORD_IP/actuator/health")" != "200" ] \
      && ok "admin(VPN) -> Orders BLOQUEADO (sin acceso directo)" || bad "admin -> Orders debería estar bloqueado"
  fi
  [ "$(kcode "$CAT_POD" "http://$ORD_IP/actuator/health")" != "200" ] \
    && ok "Movimiento lateral Catalog -> Orders BLOQUEADO" || bad "lateral Catalog -> Orders"
else
  c_warn "  (NetworkPolicies no aplicadas; correr 40-apply-netpol.sh)"
fi

c_info "== Site-To-Site (red corporativa) =="
if docker ps --format '{{.Names}}' | grep -q '^corp-pc$'; then
  [ "$(dcode corp-pc "http://$CAT_IP/health")" = "200" ] \
    && ok "corp-pc (SIN WireGuard) -> Catalog por el túnel (200)" || bad "corp-pc -> Catalog"
else
  c_warn "  (red corporativa no levantada; correr 30-up-site-to-site.sh)"
fi

echo
[ "$FAIL" -eq 0 ] && c_ok "RESULTADO: $PASS PASS, $FAIL FAIL" || c_err "RESULTADO: $PASS PASS, $FAIL FAIL"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
