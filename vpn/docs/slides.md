# Slides — Acceso Remoto Seguro con WireGuard

## Slide 1: Titulo

**Titulo:** Acceso Remoto Seguro con WireGuard  
**Subtitulo:** Client-to-Site y Site-to-Site sobre Kubernetes

- Pedro Curti (61616)
- Jose Burgos (61525)
- 72.20 Redes de Informacion — ITBA — 1C 2026

### Notas del orador

> Buenas. Somos Pedro y Jose, y hoy les presentamos nuestro trabajo practico sobre acceso remoto seguro con WireGuard. Trabajamos sobre una plataforma de e-commerce llamada The Store, que corre en Kubernetes.

---

## Slide 2: La solucion actual — The Store

**Contenido de la slide:**

- Plataforma e-commerce con 5 microservicios en Kubernetes (Kind)
- Arquitectura: UI (Java), Catalog (Go), Cart (Java), Orders (Java), Checkout (Node.js)
- Todos los servicios son ClusterIP — solo accesibles dentro del cluster
- Ingress NGINX en puerto 80 sin TLS
- Sin autenticacion en endpoints operacionales

**Visual:** Diagrama simple del cluster (cajitas con los 5 servicios, Ingress a la izquierda, sin nada a la derecha).

### Notas del orador

> The Store es una plataforma de e-commerce con 5 microservicios corriendo en un cluster Kubernetes local. Todos los servicios se comunican por ClusterIP — o sea, solo se acceden entre ellos dentro del cluster. El unico punto de entrada es un Ingress NGINX en el puerto 80, sin TLS. Los endpoints operacionales — para hacer testing, inyectar errores, ver metricas — no tienen ningun tipo de autenticacion. Funciona, pero solo si estas en la misma red donde corre el cluster.

---

## Slide 3: Problemas identificados

**Contenido de la slide:**

1. **Sin acceso remoto:** No hay mecanismo para que un admin gestione el cluster desde afuera de la red. `kubectl` y `docker` solo funcionan en la maquina local.
2. **Sin segmentacion:** Cualquier pod puede comunicarse con cualquier otro. No hay NetworkPolicies. El movimiento lateral es total.
3. **Acceso admin desprotegido:** Las credenciales y comandos de gestion transitan sin cifrado. No hay tunel seguro para operaciones administrativas.

**Visual:** Los 3 puntos como cards o bloques visuales. Nada de texto extra.

### Notas del orador

> Identificamos tres problemas principales. Primero, no hay forma de acceder al cluster remotamente. Si el admin no esta fisicamente en la red local, no puede hacer nada. Segundo, no hay segmentacion de red: cualquier pod se comunica con cualquier otro sin restriccion, lo que habilita movimiento lateral. Tercero, las operaciones administrativas viajan sin cifrado — kubectl, acceso a servicios internos, todo en claro. Estos tres problemas se resuelven con nuestra solucion.

---

## Slide 4: Nuestra solucion — Vision general

**Contenido de la slide:**

- **VPN WireGuard** con dos tuneles:
  - Client-to-Site: admin remoto con su propio cliente WireGuard
  - Site-to-Site: tunel permanente con la red corporativa
- **NetworkPolicies Kubernetes**: default-deny + reglas por servicio
- **Acceso autorizado por clave + segmentacion a nivel red**

**Visual:** Diagrama simplificado con 3 zonas: "Internet/Remoto" (admin laptop), "Red corporativa" (empleados), y "Cluster K8s" (gateway WireGuard + servicios). Flechas de tunel entre zonas.

### Notas del orador

> Nuestra solucion tiene dos pilares. Primero, una VPN con WireGuard que ofrece dos escenarios: Client-to-Site, donde un admin remoto se conecta con su propio cliente WireGuard y accede al cluster completo con kubectl; y Site-to-Site, donde un tunel permanente permite que toda la red corporativa acceda a los servicios del cluster sin instalar nada en las PCs de los empleados. Segundo, NetworkPolicies de Kubernetes que implementan un modelo de zero trust: todo el trafico esta bloqueado por defecto, y solo se habilita lo que cada servicio necesita. La combinacion de ambas cosas nos da acceso autorizado por clave criptografica mas segmentacion a nivel de red.

---

## Slide 5: Como cubre los problemas

**Contenido de la slide:**

| Problema | Solucion |
|---|---|
| Sin acceso remoto | VPN Client-to-Site (admin) + Site-to-Site (corporativo) |
| Sin segmentacion | NetworkPolicies: default-deny + reglas por servicio |
| Acceso admin desprotegido | Tunel cifrado ChaCha20-Poly1305 + autenticacion por clave WireGuard |

**Visual:** Tabla simple, 3 filas, limpia.

### Notas del orador

> Aca se ve como cada problema se mapea a la solucion. El acceso remoto se resuelve con los dos tuneles VPN: C2S para admins, S2S para la red corporativa. La segmentacion se resuelve con NetworkPolicies que bloquean todo por defecto y solo permiten lo necesario. Y el acceso admin desprotegido se resuelve con cifrado ChaCha20-Poly1305 en el tunel y autenticacion mutua por claves WireGuard — si no tenes la clave, no entras.

---

## Slide 6: Por que WireGuard

**Contenido de la slide:**

- **AllowedIPs nativo:** Segmentacion de trafico sin configuracion adicional — exactamente lo que necesitamos para control de acceso por tunel
- **Handshake en 1 RTT:** El admin se conecta en milisegundos con el protocolo Noise IK
- **Sin PKI:** 4 pares de claves en archivos de texto. Sin CA, sin certificados, sin renovaciones
- **Kernel-space:** ~4000 lineas de codigo, rendimiento nativo del kernel

**Visual:** Los 4 bullets con iconos. Tabla chica de comparacion al costado (3 columnas x 3 filas maximo):

| | OpenVPN | WireGuard | IPsec |
|---|---|---|---|
| Handshake | TLS | **Noise IK (1 RTT)** | IKEv2 |
| Claves | PKI X.509 | **Pre-compartidas** | PKI X.509 |
| Complejidad | Alta | **Baja** | Muy alta |

### Notas del orador

> Elegimos WireGuard por cuatro razones clave para nuestro problema. Primero, AllowedIPs: WireGuard tiene segmentacion de trafico nativa — cada tunel solo enruta lo que definimos, sin configuracion extra. Segundo, el handshake es de un solo round-trip gracias al protocolo Noise IK. Tercero, no necesitamos PKI: manejamos 4 pares de claves en archivos de texto, punto. Cuarto, corre en kernel-space con apenas 4000 lineas de codigo. OpenVPN e IPsec podrian resolver esto, pero WireGuard lo hace con una fraccion de la complejidad.

---

## Slide 7: Arquitectura completa

**Contenido de la slide:**

**Visual:** Diagrama de arquitectura (el de la pre-entrega corregido) mostrando:

- **Cluster Kubernetes (Kind):**
  - Pod gateway WireGuard en namespace `vpn-system` con dos interfaces: wg0 (S2S) y wg1 (C2S)
  - Servicios: UI, Catalog, Cart, Orders, Checkout en namespace `the-store`
  - Ingress NGINX en puerto 80
  - NetworkPolicies como "capa" alrededor de los servicios

- **Red corporativa (172.30.0.0/24):**
  - corp-gateway (172.30.0.1) con WireGuard
  - corp-pc (172.30.0.50) SIN WireGuard

- **Admin remoto:**
  - Laptop con cliente WireGuard (10.200.0.2)

- **PC externo:**
  - Alpine sin WireGuard (en la red kind, sin acceso a internals)

- Tuneles cifrados ChaCha20-Poly1305 entre gateway y cada extremo

**No incluir texto en esta slide.** Solo el diagrama.

### Notas del orador

> Este es el diagrama completo. En el centro, el cluster Kubernetes con los 5 servicios y el gateway WireGuard como pod dedicado. El gateway tiene dos interfaces: wg0 para el tunel site-to-site con la red corporativa, y wg1 para el tunel client-to-site con el admin remoto. Las NetworkPolicies envuelven los servicios como capa de defensa: default-deny con reglas explicitas por servicio. A la izquierda, la red corporativa con un gateway que tiene WireGuard y las PCs de los empleados que no necesitan instalar nada. A la derecha, el admin remoto con su cliente WireGuard. Todo el trafico que cruza los tuneles va cifrado con ChaCha20-Poly1305.

---

## Slide 8: Demo en vivo

**Contenido de la slide:**

- Titulo: "Demo en vivo"
- Casos de uso:
  - CU-1: Admin accede remotamente via Client-to-Site
  - CU-2: Empleado accede sin cliente VPN via Site-to-Site
  - CU-3: Segmentacion — admin no puede llegar a Orders
  - PC externo sin VPN — no puede acceder a nada

**Visual:** Solo el titulo y los 4 puntos. Limpio.

### Notas del orador

> Pasamos a la demo. Vamos a mostrar los tres casos de uso principales y un caso negativo: un PC externo sin VPN que demuestra que sin la clave WireGuard no se puede acceder a nada del cluster. Cambiamos a la terminal.

---

## Slide 9: Conclusion

**Contenido de la slide:**

- Acceso remoto seguro para admins y red corporativa
- Segmentacion con NetworkPolicies — zero trust de ingress
- Cifrado extremo a extremo con ChaCha20-Poly1305
- Rotacion de claves en caliente sin reiniciar el gateway

**Visual:** 4 bullets, limpios. Tal vez con iconos.

### Notas del orador

> Para cerrar: logramos acceso remoto seguro tanto para admins individuales como para la red corporativa completa, sin instalar software en los equipos de los empleados. Implementamos segmentacion con NetworkPolicies bajo un modelo de zero trust. Todo el trafico va cifrado extremo a extremo. Y la rotacion de claves se hace en caliente, sin necesidad de reiniciar el gateway. Gracias, preguntas?

---

## Notas generales de presentacion

- **Tiempo total slides:** ~12-13 minutos (deja 10 min para demo, 5-7 para preguntas)
- **Ritmo:** ~1.5 min por slide
- **No leer las slides:** Las slides son apoyo visual. Las palabras las dicen ustedes.
- **Transicion a demo:** "Pasamos a la terminal" — switch limpio, sin pausa
- **Plan B:** Tener capturas de pantalla o video de la demo por si algo falla. Correr `90-verify.sh` antes de la presentacion y guardar el output.
