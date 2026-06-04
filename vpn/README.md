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

- **WireGuard userspace (`wireguard-go`)**: evita depender de cargar el módulo
  de kernel (`CONFIG_WIREGUARD=m` no garantizado en runtime). Sólo requiere
  `/dev/net/tun` + capability `NET_ADMIN`.
- **Cifrado**: ChaCha20-Poly1305, autenticación por clave pública (Noise IK).
- **Todo en una PC**: gateway como pod en Kind; cliente admin y red corporativa
  como containers Docker en la red `kind`, alcanzando el NodePort del nodo.

> **Progreso gradual:** este árbol se construye por etapas. Ver el estado en los
> commits y en `docs/`.
