# Acceso Remoto Seguro con WireGuard sobre *the-store*

**ITBA · 72.20 Redes de Información · 1C 2026 · Tema 4: Acceso Remoto Seguro**

Acceso remoto seguro al cluster de microservicios [`the-store`](./the-store-main/)
combinando **WireGuard** (túneles cifrados Client-To-Site y Site-To-Site) con
**Kubernetes NetworkPolicies** (segmentación de red), todo desplegado en una sola
PC sobre **Kind**.

> 📄 La **problemática completa**, los casos de uso y el alcance acotado de la
> solución están en [`docs/how-to.pdf`](./docs/how-to.pdf) (Parte I). Este README
> se enfoca en **cómo ejecutar y probar** la solución.

## Qué se demuestra

| Escenario | Qué prueba |
|---|---|
| **Client-To-Site** | Un admin remoto levanta un túnel y opera el cluster con `kubectl` (API server `10.96.0.1`) y accede a servicios internos. Todo cifrado. |
| **Site-To-Site** | Una red corporativa llega a los servicios **sin WireGuard en el equipo final** (sólo ruta estática). |
| **NetworkPolicies** | default-deny + reglas mínimas: el túnel sólo alcanza lo permitido; el movimiento lateral queda bloqueado. |
| **Cifrado** | En el cable sólo se ve UDP cifrado (ChaCha20-Poly1305); el HTTP viaja en claro únicamente dentro del túnel. |
| **Rotación de claves** | Se rota un par en caliente; la clave anterior queda invalidada. |

## Arquitectura

```
   Red Corporativa (simulada)                 Cluster Kubernetes (Kind)
 ┌───────────────────────────┐            ┌──────────────────────────────────┐
 │  corp-pc (sin WireGuard)  │            │  ns: the-store                   │
 │        │ ruta estática    │            │   UI · Catalog · Cart ·          │
 │        ▼                  │  Site-to-  │   Orders · Checkout (ClusterIP)  │
 │  corp-gateway (WG) ───────┼──Site──────┼──► ns: vpn-system                │
 └───────────────────────────┘  túnel WG  │      wg-gateway (pod)            │
                                          │      NodePort UDP                │
 ┌───────────────────────────┐  Client-to-│      │ rutea a 10.96/16 (svc)    │
 │  admin (WG client) ───────┼──Site──────┼──────┘        10.244/16 (pods)   │
 └───────────────────────────┘  túnel WG  └──────────────────────────────────┘
        kubectl → 10.96.0.1                NetworkPolicies: default-deny + reglas
```

## Prerequisitos

- **Docker**, **Kind** y **kubectl** instalados (ver [`the-store-main/README.md`](./the-store-main/README.md)).
- Módulo `wireguard` del kernel (modo primario). Si no está disponible, la imagen
  cae a **userspace (`wireguard-go`)** automáticamente. El módulo se carga en el
  kernel **del host** (los pods comparten ese kernel). Para forzar la carga:
  `sudo modprobe wireguard`.

## Arranque rápido (TL;DR)

```bash
# 1. App de microservicios (cluster Kind + the-store)
cd the-store-main && ./local.sh create-cluster --skip-tests && cd ..

# 2. Toda la solución de acceso remoto, en orden, con verificación
vpn/scripts/up.sh
```

`up.sh` corre, en orden: `00-gen-keys` → `10-deploy-gateway` →
`20-up-admin-client` → `25-up-external-pc` → `30-up-site-to-site` →
`40-apply-netpol` → `90-verify`. Al final debe imprimir
**`RESULTADO: 10 PASS, 0 FAIL`** (con todos los escenarios levantados).

## Paso a paso

### 1. Generar claves

```bash
vpn/scripts/00-gen-keys.sh
```

Crea 4 pares en `vpn/keys/` (gitignored): `gw-c2s`, `gw-s2s`, `admin`, `corp`.
Cada privada nunca sale de su lado; sólo las públicas se intercambian.

### 2. Desplegar el gateway WireGuard

```bash
vpn/scripts/10-deploy-gateway.sh
kubectl get pod -n vpn-system
kubectl exec -n vpn-system deploy/wg-gateway -c wg-gateway -- wg show
```

Crea el namespace `vpn-system`, el Secret con `wg0.conf`/`wg1.conf` y el
Deployment + Service **NodePort UDP** (31820 Site-To-Site, 31821 Client-To-Site).
El pod levanta `wg0` y `wg1`, habilita `ip_forward` (initContainer) y NATea
hacia los CIDRs del cluster.

### 3. Cliente admin (Client-To-Site)

```bash
vpn/scripts/20-up-admin-client.sh
docker exec admin wg show
docker exec admin kubectl --kubeconfig /root/admin.kubeconfig get pods -n the-store
```

El `kubectl` sale al API server **`10.96.0.1` por el túnel** (la ruta a
`10.96.0.0/16` sólo existe sobre `wg0`).

### 4. Red corporativa (Site-To-Site)

```bash
vpn/scripts/30-up-site-to-site.sh
docker exec corp-pc wg show          # vacío: NO tiene WireGuard
CAT=$(kubectl get svc catalog -n the-store -o jsonpath='{.spec.clusterIP}')
docker exec corp-pc curl -s -o /dev/null -w '%{http_code}\n' http://$CAT/health   # 200
```

### 5. Segmentación (NetworkPolicies)

```bash
vpn/scripts/40-apply-netpol.sh
kubectl get networkpolicy -n the-store
```

### 6. Verificación end-to-end

```bash
vpn/scripts/90-verify.sh     # imprime PASS/FAIL por chequeo
```

### 7. Rotación de claves (ante compromiso de un peer)

```bash
vpn/scripts/rotate-keys.sh admin    # o: rotate-keys.sh corp
```

Rota el par de claves del peer indicado **sin reiniciar el gateway**:

1. Genera un par nuevo para el peer (`wg genkey` / `wg pubkey`).
2. Actualiza el peer en el gateway **en caliente** con `wg set`: quita la clave
   pública vieja y agrega la nueva (la anterior queda **invalidada de inmediato**).
3. Persiste el cambio en el Secret del gateway (sobrevive a un reinicio del pod).
4. Reconfigura el cliente (`admin` o `corp-gateway`) con la clave nueva y
   reconecta el túnel.

Al final el script verifica que la clave vieja **ya no figura** en el gateway y
que la nueva está activa. Para comprobarlo a mano:

```bash
kubectl exec -n vpn-system deploy/wg-gateway -c wg-gateway -- wg show wg0
docker exec admin wg show            # handshake reciente con la clave nueva
```

## Teardown

```bash
vpn/scripts/99-teardown.sh          # quita VPN/netpols, deja la app intacta
vpn/scripts/99-teardown.sh --all    # además borra las claves
```

## Cómo funciona por dentro

- **Gateway = pod** en `vpn-system`, modo **kernel** (sólo `NET_ADMIN`); un
  initContainer privilegiado habilita `ip_forward` (en un pod `/proc/sys/net`
  es read-only). Fallback userspace (`wireguard-go`) si no hay módulo.
- **Exposición = NodePort UDP**: los clientes (containers en la red `kind`)
  alcanzan `<nodeIP>:31820/31821`.
- **AllowedIPs** = mínimo privilegio de ruteo y ACL de origen: definen qué
  subredes cruzan el túnel por cada peer.
- **NAT por destino** en el gateway: todo lo que se reenvía a `10.96.0.0/16` /
  `10.244.0.0/16` sale con la IP del pod, así el cluster sabe responder (vale
  para admin, túnel y la LAN corporativa).
- **NetworkPolicies** las aplica el CNI de Kind (kindnet): default-deny ingress
  + una regla por servicio.

Todos los valores de red están en [`vpn/scripts/lib.sh`](./vpn/scripts/lib.sh).

### Mapa de rangos de red

| CIDR | Rol |
|---|---|
| `10.200.0.0/24` | Subred del túnel Client-To-Site (IPs virtuales de WireGuard; gateway `.1`, admin `.2`) |
| `10.100.0.0/30` | Subred del túnel Site-To-Site (gateway corp ↔ gateway cluster) |
| `10.96.0.0/16` | Service CIDR del cluster (ClusterIPs; API server `10.96.0.1`) |
| `10.244.0.0/16` | Pod CIDR del cluster (IPs reales de los pods) |
| `172.21.0.0/16` | Red Docker `kind` (nodo y contenedores admin/corp/external) |
| `172.30.0.0/24` | LAN corporativa simulada (`corp-pc`) |

## Estructura del repo

```
.
├── the-store-main/        # App de microservicios (baseline, sin modificar)
├── vpn/                   # NUESTRA implementación
│   ├── gateway/           #   Gateway WireGuard del cluster (manifests k8s)
│   ├── client-to-site/    #   Cliente admin remoto
│   ├── site-to-site/      #   Gateway de red corporativa + PC sin VPN
│   ├── network-policies/  #   Segmentación default-deny + reglas por servicio
│   └── scripts/           #   Despliegue, demo, rotación de claves, verificación
└── docs/                  # How-to (PDF), entrega, enunciado, capturas Wireshark
```

## Documentación

- [`docs/how-to.pdf`](./docs/how-to.pdf) — documento completo: **Parte I**
  (problemática, casos de uso, alcance) + **Parte II** (este how-to).
- [`docs/entrega_TPE.pdf`](./docs/entrega_TPE.pdf) — entrega del TP.
- `docs/*.pcapng` — capturas Wireshark del tráfico con y sin túnel.
