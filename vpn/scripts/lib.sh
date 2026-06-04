#!/usr/bin/env bash
# Librería compartida: variables de red y helpers para toda la solución.
# Se hace `source` desde los demás scripts. No ejecutar directamente.

set -euo pipefail

# --- Rutas ---
VPN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$VPN_DIR/.." && pwd)"
KEYS_DIR="$VPN_DIR/keys"

# --- Imagen / cluster ---
IMAGE="tpe-wireguard:latest"
CLUSTER="the-store"          # nombre del cluster Kind
APP_NS="the-store"           # namespace de la app
VPN_NS="vpn-system"          # namespace del gateway WireGuard

# --- Túnel Client-To-Site (interfaz wg1 en el gateway) ---
C2S_IF="wg1"
C2S_SUBNET="10.200.0.0/24"
C2S_GW_IP="10.200.0.1"       # gateway (servidor)
C2S_ADMIN_IP="10.200.0.2"    # cliente admin
C2S_LISTEN="51821"           # puerto WG dentro del pod
C2S_NODEPORT="31821"         # NodePort UDP expuesto en el nodo

# --- Túnel Site-To-Site (interfaz wg0 en el gateway) ---
S2S_IF="wg0"
S2S_SUBNET="10.100.0.0/30"
S2S_GW_IP="10.100.0.2"       # gateway del cluster (Peer B)
S2S_CORP_IP="10.100.0.1"     # gateway corporativo (Peer A)
S2S_LISTEN="51820"
S2S_NODEPORT="31820"

# --- Red corporativa simulada ---
# Nota: el TPE proponía 172.20.0.0/24, pero en la máquina de desarrollo ese /16
# ya estaba tomado por otra red docker. Usamos 172.30.0.0/24 (mismo rol).
CORP_NET="corp-net"          # red docker
CORP_SUBNET="172.30.0.0/24"
CORP_GW_IP="172.30.0.1"      # corp-gateway (con WireGuard)
CORP_PC_IP="172.30.0.50"     # corp-pc (SIN WireGuard)
CORP_BRIDGE_GW="172.30.0.254" # gateway del bridge docker (libera .1 para corp-gateway)

# --- CIDRs del cluster (defaults de Kind) ---
SVC_CIDR="10.96.0.0/16"
POD_CIDR="10.244.0.0/16"
APISERVER_IP="10.96.0.1"     # ClusterIP del API server

# --- Colores ---
c_info()  { printf '\033[0;34m%s\033[0m\n' "$*"; }
c_ok()    { printf '\033[0;32m%s\033[0m\n' "$*"; }
c_warn()  { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err()   { printf '\033[0;31m%s\033[0m\n' "$*" >&2; }

# --- Helpers ---

# Asegura que la imagen WireGuard exista (la construye si falta).
ensure_image() {
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    c_info "Construyendo imagen $IMAGE ..."
    docker build -t "$IMAGE" "$VPN_DIR/docker/"
  fi
}

# Asegura que el módulo wireguard del kernel esté cargado (modo kernel).
# Si no se puede cargar, los componentes usan el fallback userspace
# (wireguard-go, ya incluido en la imagen).
ensure_wg_module() {
  # Usamos /proc/modules (no depende de tener /sbin en el PATH como lsmod).
  if grep -q '^wireguard ' /proc/modules 2>/dev/null; then
    c_ok "Módulo wireguard ya cargado (modo kernel)."
    return 0
  fi
  c_warn "Módulo wireguard no cargado; intentando cargarlo..."
  if sudo modprobe wireguard 2>/dev/null && grep -q '^wireguard ' /proc/modules; then
    c_ok "Módulo wireguard cargado."
    return 0
  fi
  # Fallback: forzar autocarga vía container privilegiado efímero.
  docker run --rm --privileged "$IMAGE" \
    sh -c 'ip link add wgprobe type wireguard 2>/dev/null && ip link del wgprobe' >/dev/null 2>&1 || true
  if grep -q '^wireguard ' /proc/modules 2>/dev/null; then
    c_ok "Módulo wireguard cargado (vía container privilegiado)."
    return 0
  fi
  c_warn "No se pudo cargar el módulo; los pods/containers usarán userspace (wireguard-go)."
  return 0
}

# IP del nodo Kind en la red docker 'kind' (endpoint de los NodePorts).
node_ip() {
  docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{if eq $k "kind"}}{{$v.IPAddress}}{{end}}{{end}}' \
    "${CLUSTER}-control-plane"
}

# Lee una clave generada por 00-gen-keys.sh.
key_priv() { cat "$KEYS_DIR/$1.key"; }
key_pub()  { cat "$KEYS_DIR/$1.pub"; }

require_keys() {
  if [ ! -d "$KEYS_DIR" ] || [ -z "$(ls -A "$KEYS_DIR" 2>/dev/null)" ]; then
    c_err "No hay claves en $KEYS_DIR. Corré primero: vpn/scripts/00-gen-keys.sh"
    exit 1
  fi
}
