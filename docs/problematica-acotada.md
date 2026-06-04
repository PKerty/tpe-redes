# TPE – Acceso Remoto Seguro con WireGuard
## Problemática acotada (revisión para entrega final)

> **Devolución de cátedra:** *"La entrega está aprobada. Tengan en cuenta para la
> presentación final que hay problemas que están planteando que no están
> solucionando, por lo que hay que acotar la problemática a lo que efectivamente
> resuelven."*

Este documento reescribe la sección **Problemática y Contexto** y el **Scope**
para que "lo que planteamos" sea exactamente "lo que resolvemos" con
**WireGuard + Kubernetes NetworkPolicies**. Reemplaza la lista P1–P8 de la
pre-entrega.

---

## 1. Contexto real del deploy (verificado sobre el repo)

The Store corre en un cluster **Kind** (una sola máquina) con 5 microservicios
(UI, Catalog, Cart, Orders, Checkout). Estado verificado en
`dist/kubernetes.yaml` y `local.sh`:

- **Todos los Services son `ClusterIP`** → no hay NodePort ni LoadBalancer.
- **El único punto de entrada es el Ingress NGINX** publicado en `localhost:80`
  (sólo se mapean los puertos 80/443 del nodo al host; ningún otro puerto sale).
- **No existen NetworkPolicies** → cualquier pod alcanza a cualquier pod.
- **Persistencia `in-memory`** en los 5 servicios → **no hay Redis/Postgres/
  RabbitMQ desplegados**; los Secrets existen como objetos pero ningún pod los
  consume sobre la red.

**Consecuencia central:** fuera del Ingress en `localhost:80`, **el cluster no
es alcanzable desde fuera del nodo de ninguna forma segura**. No hay canal para
operarlo remotamente ni para que una red externa consuma sus servicios.

---

## 2. Problema acotado — lo que SÍ resolvemos

Acotamos el trabajo a **dos problemas concretos de acceso remoto** y **uno de
segmentación** que los habilita de forma segura:

### Problema A — No hay acceso administrativo remoto seguro
Un administrador o desarrollador **fuera de la red del nodo** no puede operar el
cluster (`kubectl` contra el API server, ni alcanzar servicios internos) sin
exponer el API server o los servicios en texto plano a la red.
→ **Resuelto con WireGuard Client-To-Site.**

### Problema B — No hay forma de que una red externa consuma los servicios
Una **red corporativa completa** necesita consumir los servicios del cluster
**sin instalar un cliente VPN en cada equipo** y sin abrir el cluster a la red.
→ **Resuelto con WireGuard Site-To-Site** (túnel permanente entre el gateway de
la red corporativa y el gateway del cluster; los equipos sólo necesitan una ruta
estática).

### Problema C — Sin segmentación, el acceso remoto es acceso total
Una vez que el túnel deja entrar tráfico a la red del cluster, **cualquier
origen alcanza cualquier pod** (movimiento lateral). El acceso remoto sin
segmentación equivale a abrir todo el cluster.
→ **Resuelto con NetworkPolicies** (default-deny + reglas mínimas por servicio).
Es la pieza de defensa en profundidad que hace que el túnel habilite *sólo* lo
necesario.

**Qué provee cada tecnología (sin sobre-prometer):**

| Tecnología | Qué aporta exactamente |
|------------|------------------------|
| **WireGuard** | Canal de red **cifrado (ChaCha20-Poly1305) y autenticado por clave pública** entre peers, para los tramos *cliente↔gateway* y *red corporativa↔gateway*. `AllowedIPs` define qué subredes cruzan el túnel (mínimo privilegio de ruteo). |
| **NetworkPolicies** | Segmentación **a nivel de red del cluster**: default-deny y reglas explícitas de qué servicio habla con qué servicio. Bloquea movimiento lateral. |

---

## 3. Fuera de alcance — lo que NO resolvemos (y con qué se resolvería)

Esto es lo que la cátedra pidió declarar explícitamente. **WireGuard no es la
herramienta para estos problemas** y los sacamos de la problemática:

| Problema (estaba en P1–P8) | Por qué WireGuard NO lo resuelve | Control adecuado |
|----------------------------|----------------------------------|------------------|
| **Cifrado e identidad service-to-service intra-cluster (mTLS)** — antes P1/P6 | WireGuard cifra el tráfico *en la red entre peers* (admin↔gateway, corp↔gateway). **No** cifra ni autentica el tráfico *entre pods dentro del cluster*. | **Service Mesh / mTLS** (tema 8) |
| **TLS terminado en el Ingress (HTTPS)** — antes P3 | El túnel WG protege el *transporte* del tramo externo, pero **no termina TLS en el Ingress ni emite certificados**. El tráfico entra al cluster en HTTP plano igual. | **cert-manager + TLS en el Ingress** |
| **Gestión de secretos (Base64 ≠ cifrado)** — antes P1 | WireGuard no toca cómo se almacenan los Secrets de Kubernetes. | **Gestor de secretos (Vault) / SOPS** |
| **Exposición de puertos del host / DB** — antes P5 | En este deploy la persistencia es `in-memory`: **no hay Redis/Postgres expuestos**, y el mapeo de puertos del nodo (80/443) es config de Kind/Docker, no algo que la VPN controle. | Hardening de plataforma (no aplica acá) |
| **CI/CD por canal dedicado** — antes P8 | Mismo mecanismo que Client-To-Site (el runner sería *otro peer*), pero **no vamos a correr un pipeline real por el túnel** en la demo. | Lo dejamos como **extensión conceptual**, no como problema resuelto |

> **Regla que seguimos:** si no lo demostramos funcionando, no lo ponemos como
> "problema resuelto". Lo nombramos como límite explícito y decimos qué control
> lo resolvería.

---

## 4. Scope del POC (alineado a lo anterior)

**Incluye (demostrable, todo en una PC con Kind):**
- Gateway VPN WireGuard del lado del cluster.
- **Escenario 1 – Client-To-Site:** laptop admin (peer WG) → túnel → `kubectl` +
  servicios internos. `AllowedIPs` restrictivos por admin.
- **Escenario 2 – Site-To-Site:** "red corporativa" simulada con un contenedor
  Docker gateway → túnel permanente → servicios del cluster, **sin cliente VPN en
  el equipo final** (sólo ruta estática).
- **NetworkPolicies:** default-deny + reglas mínimas por servicio.
- **Validación de tráfico cifrado** (captura/inspección del túnel) y **rotación
  de claves**.

**No incluye (declarado como límite):**
- mTLS / Service Mesh, TLS en el Ingress, gestión de secretos enterprise,
  HA de gateways, pipeline CI/CD real por el túnel, despliegue productivo cloud.

---

## 5. Casos de uso (reescritos, sólo lo que se demuestra)

- **CU-1 — Admin opera el cluster remotamente (Client-To-Site):** el admin
  levanta su túnel (`wg-quick up`), hace `kubectl` contra el API server y alcanza
  servicios internos. Sólo llega a las subredes de sus `AllowedIPs`.
- **CU-2 — Empleado consume servicios sin cliente VPN (Site-To-Site):** desde la
  red corporativa, el tráfico hacia un servicio del cluster cruza el túnel del
  gateway de forma transparente. El equipo final **no tiene WireGuard instalado**.
- **CU-3 — Segmentación efectiva (NetworkPolicies):** un origen que entró por el
  túnel **no** puede hablar con un servicio no permitido (ej. alcanzar Orders
  saltándose a UI). Se muestra el default-deny bloqueando y la regla explícita
  habilitando.
- **CU-4 — Rotación de claves ante compromiso:** se rota el par de claves de un
  peer; las claves anteriores quedan invalidadas y el túnel se restablece con las
  nuevas. (Client-To-Site: N pares; Site-To-Site: sólo 2 pares.)

---

## 6. Frase de cierre para la slide de problemática

> "WireGuard resuelve **el acceso remoto seguro** al cluster en dos modos
> (administrativo y red-a-red) y las NetworkPolicies aseguran que ese acceso sea
> **mínimo y segmentado**. Todo lo demás —mTLS intra-cluster, TLS en el Ingress,
> gestión de secretos— queda **explícitamente fuera de alcance** porque son
> controles de otra capa, no de acceso remoto."
