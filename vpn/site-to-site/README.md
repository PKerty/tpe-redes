# Escenario 2 — Site-To-Site (red corporativa sin cliente VPN)

Una red corporativa entera consume los servicios del cluster **sin instalar
WireGuard en cada equipo**. Un único túnel permanente une el *gateway
corporativo* con el *gateway del cluster*; los equipos finales sólo necesitan
una **ruta estática** hacia el cluster (que en producción empuja el router/DHCP).

## Topología (demo en una PC)

```
 Red corporativa 'corp-net' (172.30.0.0/24)
 ┌─────────────────────────────────────────┐
 │  corp-pc 172.30.0.50   (SIN WireGuard)   │
 │     │ ruta estática: 10.96/16,10.244/16  │
 │     ▼   via 172.30.0.1                    │
 │  corp-gateway 172.30.0.1 (WireGuard)      │        pod wg-gateway (vpn-system)
 │     wg0: 10.100.0.1  ──── túnel WG ───────┼──► wg0: 10.100.0.2
 │     (además en red 'kind' p/ NodePort)    │      NAT a 10.96/16 y 10.244/16
 └─────────────────────────────────────────┘      Endpoint: <nodeIP>:31820/udp
```

> **Nota de IPs:** el TPE proponía `172.20.0.0/24`, pero en la máquina de
> desarrollo ese rango ya estaba tomado por otra red docker. Usamos
> `172.30.0.0/24` (mismo rol). Está centralizado en `vpn/scripts/lib.sh`.

## Por qué `corp-pc` no necesita WireGuard

`corp-pc` sólo tiene una **ruta estática**: "para llegar al cluster
(`10.96.0.0/16`, `10.244.0.0/16`), mandá a `corp-gateway`". El cifrado lo hace
el `corp-gateway`, transparente para el equipo final. `docker exec corp-pc wg show`
devuelve vacío: no hay túnel en el equipo.

## Recorrido de un paquete (`corp-pc` → Catalog)

1. `corp-pc` (172.30.0.50) → `http://<catalog ClusterIP>` → ruta estática lo
   manda a `corp-gateway`.
2. `corp-gateway` reenvía (`ip_forward`) el paquete por `wg0`: cruza el túnel
   cifrado (ChaCha20-Poly1305) porque `10.96.0.0/16` está en `AllowedIPs`.
3. El gateway del cluster descifra, **NATea el origen** a la IP de su pod (así el
   cluster sabe responder) y entrega a Catalog.
4. La respuesta vuelve por el mismo túnel hasta `corp-pc`.

## Claves: sólo 2 pares

Site-To-Site usa **un par de claves por gateway** (corp + cluster), no `N×(N−1)`
como un esquema cliente-por-cliente. La rotación es directa (ver
`vpn/scripts/rotate-keys.sh`).

## Uso

```bash
vpn/scripts/30-up-site-to-site.sh

docker exec corp-pc  wg show          # vacío (sin WireGuard)
docker exec corp-gateway wg show      # túnel del gateway corporativo
CAT=$(kubectl get svc catalog -n the-store -o jsonpath='{.spec.clusterIP}')
docker exec corp-pc curl -s -o /dev/null -w '%{http_code}\n' http://$CAT/health   # 200
```

`corp-pc → Orders` queda **bloqueado** por NetworkPolicies (segmentación): la red
corporativa sólo alcanza lo explícitamente permitido (Catalog/UI), no Orders.
