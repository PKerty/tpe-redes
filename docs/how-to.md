# How-To — Acceso Remoto Seguro con WireGuard sobre `the-store`

Guía paso a paso para desplegar y demostrar la solución. Todo corre en **una sola
PC** con Kind. Para el alcance y la problemática, ver
[`problematica-acotada.md`](./problematica-acotada.md).

---

## 1. Qué se demuestra

| Escenario | Qué prueba |
|-----------|-----------|
| **Client-To-Site** | Un admin remoto levanta un túnel y opera el cluster con `kubectl` (al API server `10.96.0.1`) y accede a servicios internos. Todo cifrado. |
| **Site-To-Site** | Una red corporativa llega a los servicios **sin WireGuard en el equipo final** (sólo ruta estática). |
| **NetworkPolicies** | `default-deny` + reglas mínimas: el túnel sólo alcanza lo permitido; el movimiento lateral queda bloqueado. |
| **Cifrado** | En el cable sólo se ve UDP cifrado (ChaCha20-Poly1305); el HTTP viaja en claro únicamente dentro del túnel. |
| **Rotación de claves** | Se rota un par en caliente; la clave anterior queda invalidada. |

---

## 2. Prerequisitos

- **Docker**, **Kind** y **kubectl** instalados (ver `the-store-main/README.md`).
- Módulo `wireguard` del kernel (modo primario). Si no está disponible, la imagen
  cae a **userspace (`wireguard-go`)** automáticamente — no hace falta hacer nada.
  Para forzar la carga: `sudo modprobe wireguard`.

---

## 3. Arranque rápido (TL;DR)

```bash
# 1. App de microservicios (cluster Kind + the-store)
cd the-store-main && ./local.sh create-cluster --skip-tests && cd ..

# 2. Toda la solución de acceso remoto, en orden, con verificación
vpn/scripts/up.sh
```

`up.sh` corre: `00-gen-keys` → `10-deploy-gateway` → `20-up-admin-client` →
`30-up-site-to-site` → `40-apply-netpol` → `90-verify`. Al final debe imprimir
**`RESULTADO: 8 PASS, 0 FAIL`**.

---

## 4. Paso a paso

### 4.1 Generar claves
```bash
vpn/scripts/00-gen-keys.sh
```
Crea 4 pares en `vpn/keys/` (gitignored): `gw-c2s`, `gw-s2s`, `admin`, `corp`.
Cada privada nunca sale de su lado; sólo las públicas se intercambian.

### 4.2 Desplegar el gateway WireGuard
```bash
vpn/scripts/10-deploy-gateway.sh
```
Crea el namespace `vpn-system`, el Secret con `wg0.conf`/`wg1.conf`, y el
Deployment + Service **NodePort UDP** (31820 Site-To-Site, 31821 Client-To-Site).
El pod levanta `wg0` y `wg1`, habilita `ip_forward` (initContainer) y NATea hacia
los CIDRs del cluster.
```bash
kubectl get pod -n vpn-system
kubectl exec -n vpn-system deploy/wg-gateway -c wg-gateway -- wg show
```

### 4.3 Cliente admin (Client-To-Site)
```bash
vpn/scripts/20-up-admin-client.sh
docker exec admin wg show
docker exec admin kubectl --kubeconfig /root/admin.kubeconfig get pods -n the-store
```
El `kubectl` sale al API server **`10.96.0.1` por el túnel** (la ruta a
`10.96.0.0/16` sólo existe sobre `wg0`).

### 4.4 Red corporativa (Site-To-Site)
```bash
vpn/scripts/30-up-site-to-site.sh
docker exec corp-pc wg show          # vacío: NO tiene WireGuard
CAT=$(kubectl get svc catalog -n the-store -o jsonpath='{.spec.clusterIP}')
docker exec corp-pc curl -s -o /dev/null -w '%{http_code}\n' http://$CAT/health   # 200
```

### 4.5 Segmentación (NetworkPolicies)
```bash
vpn/scripts/40-apply-netpol.sh
kubectl get networkpolicy -n the-store
```

### 4.6 Verificación end-to-end
```bash
vpn/scripts/90-verify.sh     # imprime PASS/FAIL por chequeo
```

---

## 5. Demostraciones para la presentación

**Segmentación (CU-3):** la VPN llega a Catalog pero NO a Orders; el movimiento
lateral está bloqueado.
```bash
CAT=$(kubectl get svc catalog -n the-store -o jsonpath='{.spec.clusterIP}')
ORD=$(kubectl get svc orders  -n the-store -o jsonpath='{.spec.clusterIP}')
docker exec admin curl -s -o /dev/null -w 'admin->catalog %{http_code}\n'      --max-time 4 http://$CAT/health
docker exec admin curl -s -o /dev/null -w 'admin->orders  %{http_code}\n'      --max-time 4 http://$ORD/actuator/health || echo 'admin->orders BLOQUEADO'
```

**Cifrado en el cable:**
```bash
vpn/scripts/verify-encryption.sh
```
Muestra UDP cifrado en `eth0` (sin texto plano) y el `GET /health` en claro dentro
de `wg0`.

**Rotación de claves (en caliente):**
```bash
vpn/scripts/rotate-keys.sh admin     # o: corp
```
Genera un par nuevo, lo actualiza en el gateway sin reiniciarlo, reconecta el
cliente y confirma que la clave anterior quedó invalidada.

---

## 6. Cómo funciona por dentro

- **Gateway = pod** en `vpn-system`, modo **kernel** (sólo `NET_ADMIN`); un
  initContainer privilegiado habilita `ip_forward` (en un pod `/proc/sys/net` es
  read-only). Fallback userspace (`wireguard-go`) si no hay módulo.
- **Exposición = NodePort UDP**. Los clientes (containers en la red `kind`)
  alcanzan `<nodeIP>:31820/31821`.
- **AllowedIPs** = mínimo privilegio de ruteo: definen qué subredes cruzan el
  túnel por cada peer.
- **NAT por destino** en el gateway: todo lo que se reenvía a `10.96.0.0/16` /
  `10.244.0.0/16` sale con la IP del pod, así el cluster sabe responder (vale para
  admin, túnel y la LAN corporativa del Site-To-Site).
- **NetworkPolicies** las aplica el CNI de Kind (kindnet): `default-deny` ingress
  + una regla por servicio.

Todos los valores de red están en [`vpn/scripts/lib.sh`](../vpn/scripts/lib.sh).

---

## 7. Troubleshooting

| Síntoma | Causa / solución |
|---------|------------------|
| Tras `10-deploy`, los clientes tardan en reconectar | El `rollout restart` recrea el pod; los túneles re-handshakean en ~25 s (PersistentKeepalive). Reintentar. |
| `corp-pc` no llega al cluster | Verificar `ip_forward=1` en `corp-gateway` (se setea con `--sysctl`) y la ruta estática en `corp-pc`. |
| `172.20.0.0/24` ocupado | La red corporativa usa `172.30.0.0/24` (configurable en `lib.sh`). |
| El gateway no levanta `wg` | Módulo de kernel ausente: la imagen usa userspace; revisar `kubectl logs -n vpn-system deploy/wg-gateway`. |
| NetworkPolicies no bloquean | El CNI debe soportarlas (kindnet sí en Kind reciente; si no, instalar Calico). |

---

## 8. Teardown

```bash
vpn/scripts/99-teardown.sh          # quita VPN/netpols, deja la app intacta
vpn/scripts/99-teardown.sh --all    # además borra las claves
```
