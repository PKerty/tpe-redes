# Demo Script — Acceso Remoto Seguro con WireGuard

## Prerequisitos (antes de la presentacion)

```bash
# 1. El cluster debe estar levantado y funcionando
kubectl get pods -n the-store   # verificar 5 pods Running
curl -s -o /dev/null -w "%{http_code}" http://localhost/  # verificar 200

# 2. Imagen WireGuard construida
docker build -t tpe-wireguard:latest /home/kerty/Projects/redes/vpn/docker/

# 3. Tener a mano el Plan B
# - Capturas de pantalla de cada paso
# - Output de 90-verify.sh guardado en un archivo
# - Video corto de la demo completa (~3 min)
```

---

## Setup de la sesion tmux

La demo usa una sesion tmux con 4 tabs (windows), uno por container. Se navega entre tabs durante la demo.

### Script de setup: `demo-tmux.sh`

```bash
#!/usr/bin/env bash
# Levanta la sesion tmux para la demo. Correr DESPUES de deployar la VPN.
# Cada tab tiene un shell interactivo en un container diferente.
set -euo pipefail

SESSION="tpe-demo"

# Matar sesion previa si existe
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Obtener IPs de servicios
CAT_IP=$(kubectl get svc catalog -n the-store -o jsonpath='{.spec.clusterIP}')
ORD_IP=$(kubectl get svc orders -n the-store -o jsonpath='{.spec.clusterIP}')

# Tab 0: control (host)
tmux new-session -d -s "$SESSION" -n "control"
tmux send-keys -t "$SESSION:control" "echo '=== CONTROL (host) ==='" Enter
tmux send-keys -t "$SESSION:control" "echo 'Probar: curl -s -o /dev/null -w \"%{http_code}\" http://localhost/'" Enter

# Tab 1: admin (C2S)
tmux new-window -t "$SESSION" -n "admin"
tmux send-keys -t "$SESSION:admin" "docker exec -it admin bash" Enter
tmux send-keys -t "$SESSION:admin" "echo '=== ADMIN (Client-to-Site) ==='" Enter
tmux send-keys -t "$SESSION:admin" "echo 'Probar: kubectl --kubeconfig /root/admin.kubeconfig get nodes'" Enter

# Tab 2: corp-pc (S2S)
tmux new-window -t "$SESSION" -n "corp-pc"
tmux send-keys -t "$SESSION:corp-pc" "docker exec -it corp-pc bash" Enter
tmux send-keys -t "$SESSION:corp-pc" "echo '=== CORP-PC (Site-to-Site, SIN WireGuard) ==='" Enter
tmux send-keys -t "$SESSION:corp-pc" "echo 'Probar: curl -s http://$CAT_IP/health'" Enter

# Tab 3: external-pc (sin VPN)
tmux new-window -t "$SESSION" -n "external-pc"
tmux send-keys -t "$SESSION:external-pc" "docker exec -it external-pc sh" Enter
tmux send-keys -t "$SESSION:external-pc" "echo '=== EXTERNAL-PC (SIN VPN) ==='" Enter
tmux send-keys -t "$SESSION:external-pc" "echo 'Probar: curl -s --max-time 3 http://$CAT_IP/health'" Enter

# Seleccionar tab de control
tmux select-window -t "$SESSION:control"

echo "Sesion tmux '$SESSION' lista. Conectar con: tmux attach -t $SESSION"
echo "Navegar tabs: Ctrl+B + n (siguiente) / Ctrl+B + p (anterior)"
echo "O con numero: Ctrl+B + 0/1/2/3"
```

### Navegacion tmux

- `Ctrl+B` + `n` — tab siguiente
- `Ctrl+B` + `p` — tab anterior
- `Ctrl+B` + `0` — tab control (host)
- `Ctrl+B` + `1` — tab admin (C2S)
- `Ctrl+B` + `2` — tab corp-pc (S2S)
- `Ctrl+B` + `3` — tab external-pc (sin VPN)
- `Ctrl+B` + `d` — detach de la sesion

---

## Flujo de la demo

### Fase PRE: El problema (2-3 min)

Objetivo: Mostrar que sin VPN, no hay acceso remoto.

#### Paso 1: La tienda funciona (CONTROL pane)

```
$ curl -s -o /dev/null -w "%{http_code}\n" http://localhost/
200
```

> "La tienda esta en produccion. Los clientes pueden comprar normalmente."

#### Paso 2: Levantar external-pc (CONTROL pane)

```bash
$ cd ~/Projects/redes/vpn/scripts
$ ./25-up-external-pc.sh
```

#### Paso 3: External-pc no puede acceder a nada (EXTERNAL-PC pane)

```
$ curl -s --max-time 3 http://10.96.195.98/health
(timeout - sin respuesta)
```

> "Este PC esta en la misma red Docker que el cluster, pero no tiene ruta a los ClusterIP. No puede acceder a ningun servicio interno."

#### Paso 4: Tampoco tiene WireGuard (EXTERNAL-PC pane)

```
$ wg show
sh: wg: not found
```

> "Y ni siquiera tiene WireGuard instalado. Es un Alpine comun."

**Transicion:**

> "Este es el problema. Necesitamos acceso remoto seguro. Vamos a deployar la solucion."

---

### Fase DEPLOY: Levantar la VPN (2-3 min)

#### Paso 5: Deploy completo (CONTROL pane)

```bash
$ cd ~/Projects/redes/vpn/scripts
$ ./up.sh
```

> "Corremos el orquestador. Genera las claves, deploya el gateway en Kubernetes, levanta el admin, la red corporativa, el external-pc, y aplica las NetworkPolicies."

**Nota:** Si `up.sh` tarda mucho, se puede correr antes y solo mostrar el resultado. Alternativamente, correr los scripts individualmente y narrar cada paso:

```bash
# Opcion B: paso a paso (mas control sobre timing)
./00-gen-keys.sh       # "Generamos los 4 pares de claves"
./10-deploy-gateway.sh # "Deployamos el gateway WireGuard como pod en Kubernetes"
./20-up-admin-client.sh # "Conectamos el admin via Client-to-Site"
./25-up-external-pc.sh  # "Levantamos el PC externo (ya lo teniamos)"
./30-up-site-to-site.sh # "Armamos la red corporativa con Site-to-Site"
./40-apply-netpol.sh    # "Aplicamos las NetworkPolicies"
```

#### Paso 6: Verificar que el gateway esta corriendo (CONTROL pane)

```bash
$ kubectl get pods -n vpn-system
NAME                           READY   STATUS    RESTARTS   AGE
wg-gateway-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

> "El gateway WireGuard esta corriendo como pod en su propio namespace."

---

### Fase POST: La solucion (5-6 min)

**Setup:** Abrir la sesion tmux con los 4 panes.

```bash
$ tmux attach -t tpe-demo
# o correr demo-tmux.sh si no se creo antes
```

#### CU-1: Admin accede remotamente (ADMIN pane)

```
$ wg show wg0
interface: wg0
  public key: xxxxx
  private key: (hidden)
  listening port: 54832
  peer: xxxxx
    endpoint: 172.22.0.2:31821
    allowed ips: 10.200.0.0/24, 10.96.0.0/16, 10.244.0.0/16
    latest handshake: 10 seconds ago
    transfer: 1.50 KiB received, 2.10 KiB sent
```

> "El admin tiene el tunel levantado. Vemos que AllowedIPs solo permite las subredes del cluster — minimo privilegio."

```
$ kubectl --kubeconfig /root/admin.kubeconfig get nodes
NAME                          STATUS   ROLES           AGE   VERSION
the-store-control-plane       Ready    control-plane   45m   v1.36.1
```

> "kubectl funciona a traves del tunel. La API server esta en 10.96.0.1, que solo es alcanzable por VPN."

```
$ curl -s http://10.96.195.98/health
OK
```

> "Y puede acceder directamente al servicio de Catalog."

#### CU-3: Segmentacion — admin no llega a Orders (ADMIN pane)

```
$ curl -s --max-time 3 http://10.96.212.147/actuator/health
(timeout o connection refused)
```

> "Pero aunque el admin tiene VPN, no puede llegar a Orders directamente. Las NetworkPolicies bloquean el acceso del namespace vpn-system a Orders. Solo UI y Checkout pueden hablar con Orders. Esto es segmentacion."

#### CU-2: Empleado accede sin VPN (CORP-PC pane)

```
$ wg show
sh: wg: not found
```

> "El PC corporativo no tiene WireGuard instalado."

```
$ curl -s http://10.96.195.98/health
OK
```

> "Pero puede acceder al Catalog del cluster. El trafico va por ruta estatica al gateway corporativo, que lo cifra y lo manda por el tunel site-to-site. El empleado no sabe que esta yendo por una VPN."

```
$ ip route
default via 172.30.0.254 dev eth0
10.96.0.0/16 via 172.30.0.1 dev eth0
10.244.0.0/16 via 172.30.0.1 dev eth0
172.30.0.0/24 dev eth0 scope link  src 172.30.0.50
```

> "Solo tiene rutas estaticas apuntando al gateway corporativo. En produccion esto se distribuiria por DHCP."

#### PC externo: sigue sin acceso (EXTERNAL-PC pane)

```
$ curl -s --max-time 3 http://10.96.195.98/health
(timeout)
```

> "El PC externo, que no tiene VPN y no esta en la red corporativa, sigue sin poder acceder. La VPN es lo que habilita el acceso — sin la clave WireGuard, no hay tunel."

---

### Fase EXTRA: Bonus si hay tiempo (1-2 min)

#### Rotacion de claves (CU-4) (CONTROL pane)

```bash
$ ./scripts/rotate-keys.sh admin
```

> "Si sospechamos que una clave fue comprometida, rotamos en caliente. El gateway actualiza el peer sin reiniciar."

Verificar que la nueva clave funciona y la vieja no:

```bash
$ docker exec admin wg show wg0
# Mostrar nueva clave publica y handshake reciente
```

#### Verificacion automatizada (CONTROL pane)

```bash
$ ./scripts/90-verify.sh
```

> "Para cerrar, corremos la verificacion automatizada que chequea todo: la app funciona, el admin tiene kubectl, la segmentacion bloquea lo que tiene que bloquear, y la red corporativa accede correctamente."

Output esperado:
```
== App funcional ==
  PASS  Ingress -> UI responde 200
  PASS  UI -> Orders (llamada legitima) permitida
== Client-To-Site (admin remoto) ==
  PASS  Tunel admin (wg0) levantado
  PASS  kubectl por el tunel funciona
  PASS  admin -> Catalog permitido (200)
== Segmentacion por NetworkPolicies ==
  PASS  admin(VPN) -> Orders BLOQUEADO
  PASS  Movimiento lateral Catalog -> Orders BLOQUEADO
== PC externo sin VPN ==
  PASS  external-pc -> Ingress via nodo responde 200
  PASS  external-pc -> Catalog ClusterIP BLOQUEADO
== Site-to-Site (red corporativa) ==
  PASS  corp-pc -> Catalog por el tunel (200)

RESULTADO: 9 PASS, 0 FAIL
```

---

## Cheat sheet de IPs

Obtener antes de la demo:

```bash
CAT_IP=$(kubectl get svc catalog -n the-store -o jsonpath='{.spec.clusterIP}')
ORD_IP=$(kubectl get svc orders -n the-store -o jsonpath='{.spec.clusterIP}')
UI_IP=$(kubectl get svc ui -n the-store -o jsonpath='{.spec.clusterIP}')
NODE_IP=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{if eq $k "kind"}}{{$v.IPAddress}}{{end}}{{end}}' the-store-control-plane)

echo "Catalog: $CAT_IP"
echo "Orders:  $ORD_IP"
echo "UI:      $UI_IP"
echo "Node:    $NODE_IP"
```

Anotar los valores aca para referencia durante la demo:

```
Catalog: ________________
Orders:  ________________
UI:      ________________
Node:    ________________
```

---

## Timeline estimado

| Fase | Tiempo | Que pasa |
|---|---|---|
| PRE: El problema | 2-3 min | Store funciona, external-pc no accede |
| DEPLOY: Levantar VPN | 2-3 min | Correr up.sh o scripts individuales |
| POST: CU-1 Admin | 2 min | kubectl + curl a Catalog |
| POST: CU-3 Segmentacion | 1 min | admin no llega a Orders |
| POST: CU-2 Corp | 1.5 min | empleado sin WG accede a Catalog |
| POST: External-pc | 1 min | sigue sin acceso |
| EXTRA: Rotacion/Verify | 1-2 min | bonus si hay tiempo |
| **Total demo** | **~10 min** | |

---

## Plan B: Si la demo falla

1. **No debuguear en vivo.** Si algo falla, pasar al Plan B inmediatamente.
2. **Capturas de pantalla:** Tener screenshots de cada paso guardadas en una carpeta.
3. **Output de 90-verify.sh:** Guardar el output exitoso antes de la presentacion.
4. **Video corto:** Gravar la demo completa (~3 min) y tenerlo listo para reproducir.

### Para generar el Plan B antes de la presentacion:

```bash
# Correr la solucion completa
./scripts/up.sh

# Guardar output de verificacion
./scripts/90-verify.sh | tee /tmp/demo-verify-output.txt

# Grabar video (si tienen peek o similar)
# o sacar capturas de cada paso de la demo
```

---

## Checklist pre-presentacion

- [ ] Cluster levantado: `kubectl get pods -n the-store` (5 pods Running)
- [ ] Ingress funciona: `curl localhost/` (200)
- [ ] Imagen WireGuard construida: `docker images tpe-wireguard`
- [ ] tmux instalado: `which tmux`
- [ ] Plan B preparado: capturas + output de verify + video
- [ ] Cheat sheet de IPs anotado
- [ ] Bateria cargada / cargador conectado
- [ ] Proyector/ pantalla funcionando
