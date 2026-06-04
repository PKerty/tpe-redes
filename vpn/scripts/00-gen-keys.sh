#!/usr/bin/env bash
# Genera todos los pares de claves WireGuard del POC.
# Cada par: <nombre>.key (privada) y <nombre>.pub (pública) en vpn/keys/.
# vpn/keys/ está en .gitignore: las claves NUNCA se commitean.
#
# Peers:
#   gw-c2s   gateway, interfaz Client-To-Site (wg1)
#   gw-s2s   gateway, interfaz Site-To-Site   (wg0)
#   admin    cliente admin remoto (Client-To-Site)
#   corp     gateway de la red corporativa    (Site-To-Site)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ensure_image
mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

PEERS="gw-c2s gw-s2s admin corp"

gen_one() {
  local name="$1"
  if [ -f "$KEYS_DIR/$name.key" ] && [ "${FORCE:-0}" != "1" ]; then
    c_warn "  $name ya existe (usá FORCE=1 para regenerar) — se conserva."
    return
  fi
  local priv pub
  priv="$(docker run --rm "$IMAGE" wg genkey)"
  pub="$(printf '%s' "$priv" | docker run --rm -i "$IMAGE" wg pubkey)"
  printf '%s' "$priv" > "$KEYS_DIR/$name.key"
  printf '%s' "$pub"  > "$KEYS_DIR/$name.pub"
  chmod 600 "$KEYS_DIR/$name.key"
  c_ok "  $name  ->  pub: $pub"
}

c_info "Generando claves en $KEYS_DIR ..."
for p in $PEERS; do gen_one "$p"; done
c_ok "Listo. $(ls "$KEYS_DIR" | wc -l) archivos de clave."
