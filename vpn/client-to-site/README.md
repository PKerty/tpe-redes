# Escenario 1 — Client-To-Site (acceso administrativo remoto)

Un administrador/desarrollador **fuera de la red del cluster** levanta un túnel
WireGuard contra la interfaz `wg1` del gateway y opera el cluster con `kubectl`
y accede a servicios internos. **Todo el tráfico viaja cifrado** y sólo alcanza
las subredes declaradas en `AllowedIPs` (mínimo privilegio).

## Topología (demo en una PC)

```
  [ container 'admin' ]                 [ pod wg-gateway / vpn-system ]
   wg0: 10.200.0.2  ───── túnel WG ─────►  wg1: 10.200.0.1
   (red docker 'kind')   Endpoint:           │ NAT a 10.96.0.0/16 (services)
                         <nodeIP>:31821/udp   │     y 10.244.0.0/16 (pods)
   kubectl ─► https://10.96.0.1:443 ──────────┘──► API server
```

El container `admin` está en la red `kind` sólo para alcanzar el **NodePort UDP**
del nodo (`<nodeIP>:31821`). El acceso a `10.96.0.0/16` / `10.244.0.0/16`
**no existe por la red docker**: aparece únicamente al levantar el túnel
(esas subredes están en `AllowedIPs`). Por eso llegar a `10.96.0.1` prueba que
el acceso pasa por la VPN.

## Configuración del cliente (`wg0.conf`)

```ini
[Interface]
Address = 10.200.0.2/24
PrivateKey = <clave privada del admin>

[Peer]
PublicKey = <clave pública gw-c2s del gateway>
Endpoint = <IP del nodo Kind>:31821
AllowedIPs = 10.200.0.0/24, 10.96.0.0/16, 10.244.0.0/16
PersistentKeepalive = 25
```

`AllowedIPs` es el control de **mínimo privilegio**: define exactamente qué
subredes del cluster puede alcanzar este admin. Un admin con menos privilegios
llevaría, por ejemplo, sólo `10.96.0.0/16` (services) y no el rango de pods.

## Uso

```bash
vpn/scripts/00-gen-keys.sh         # una vez
vpn/scripts/10-deploy-gateway.sh   # gateway en el cluster
vpn/scripts/20-up-admin-client.sh  # levanta el cliente admin y el túnel

# Verificar
docker exec admin wg show
docker exec admin ping -c2 10.200.0.1
docker exec admin kubectl --kubeconfig /root/admin.kubeconfig get nodes
```

## Gestión de claves

Cada admin genera su par localmente; su clave **pública** se agrega como `[Peer]`
en `wg1` del gateway. La privada nunca sale de su equipo. Rotación: ver
`vpn/scripts/rotate-keys.sh`.
