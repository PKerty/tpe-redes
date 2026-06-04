# `vpn/` — Implementación de Acceso Remoto Seguro

Esta carpeta contiene **toda la implementación propia** del TPE (la app
`the-store/` queda intacta como baseline).

## Componentes

| Carpeta | Qué hace |
|---------|----------|
| `gateway/` | Gateway WireGuard del cluster: pod en `vpn-system` (WireGuard userspace), expuesto por NodePort UDP. Termina los túneles Client-To-Site y Site-To-Site y rutea hacia las subredes del cluster. |
| `client-to-site/` | Cliente admin remoto (container con WireGuard). Levanta el túnel y opera el cluster con `kubectl`. |
| `site-to-site/` | "Red corporativa" simulada: un `corp-gateway` (WireGuard) tunelizado al cluster y un `corp-pc` **sin** WireGuard que llega a los servicios por ruta estática. |
| `network-policies/` | Segmentación de red del cluster: `default-deny` + reglas mínimas por servicio. |
| `scripts/` | Orquestación de despliegue, demo, rotación de claves y verificación de tráfico cifrado. |

## Decisiones técnicas

- **WireGuard de kernel** como modo primario: el pod/container sólo necesita la
  capability `NET_ADMIN` y el módulo `wireguard` cargado en el host. Es más
  simple y rápido que userspace (no requiere `privileged` ni `/dev/net/tun`).
- **Fallback userspace (`wireguard-go`)**: la imagen incluye `wireguard-go` por
  si el host no tiene el módulo de kernel. `wg-quick` cae a userspace
  automáticamente. El preflight (`ensure_wg_module` en `scripts/lib.sh`) intenta
  cargar el módulo y, si no puede, deja el fallback activo.
- **Cifrado**: ChaCha20-Poly1305, autenticación por clave pública (Noise IK).
- **Todo en una PC**: gateway como pod en Kind; cliente admin y red corporativa
  como containers Docker, alcanzando el **NodePort UDP** del nodo Kind.

## Mapa de red (resumen)

| Túnel | Interfaz gw | Subred túnel | Gateway | Peer | NodePort UDP |
|-------|-------------|--------------|---------|------|--------------|
| Client-To-Site | `wg1` | `10.200.0.0/24` | `.1` | admin `.2` | `31821` |
| Site-To-Site | `wg0` | `10.100.0.0/30` | `.2` | corp `.1` | `31820` |

Red corporativa simulada: `172.20.0.0/24` (corp-gateway `.1`, corp-pc `.50`).
CIDRs del cluster ruteados por el túnel: services `10.96.0.0/16`, pods
`10.244.0.0/16`. Valores centralizados en [`scripts/lib.sh`](./scripts/lib.sh).

> **Progreso gradual:** este árbol se construye por etapas. Ver el estado en los
> commits y en `docs/`.
