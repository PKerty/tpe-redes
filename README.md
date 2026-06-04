# TPE Redes de Información — Acceso Remoto Seguro con WireGuard

**ITBA · 72.20 Redes de Información · 1C 2026 · Tema 4: Acceso Remoto Seguro**

Implementación de **acceso remoto seguro** al cluster de microservicios
[`the-store`](./the-store-main/) usando **WireGuard** (userspace) y
**Kubernetes NetworkPolicies**, desplegado localmente sobre **Kind** (una sola
máquina).

## Problemática (acotada)

> Ver el documento completo en [`docs/problematica-acotada.md`](./docs/problematica-acotada.md).

El cluster sólo expone un Ingress NGINX en `localhost:80`; **nada más es
alcanzable desde fuera del nodo de forma segura**. Resolvemos **tres** problemas
concretos y declaramos el resto fuera de alcance:

| # | Problema | Solución |
|---|----------|----------|
| A | No hay acceso administrativo remoto seguro (`kubectl`, servicios internos) | WireGuard **Client-To-Site** |
| B | Una red externa no puede consumir servicios sin cliente VPN por equipo | WireGuard **Site-To-Site** |
| C | Sin segmentación, el túnel habilita acceso total (movimiento lateral) | **NetworkPolicies** default-deny |

**Fuera de alcance (declarado):** mTLS/Service Mesh intra-cluster, TLS en el
Ingress, gestión de secretos, CI/CD real por el túnel. Son controles de otra
capa, no de acceso remoto.

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
 ┌───────────────────────────┐  Client-to-│      │ rutea a 10.96/12 (svc)    │
 │  admin (WG client) ───────┼──Site──────┼──────┘        10.244/16 (pods)   │
 └───────────────────────────┘  túnel WG  └──────────────────────────────────┘
        kubectl → 10.96.0.1                NetworkPolicies: default-deny + reglas
```

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
└── docs/                  # Problemática acotada, how-to, enunciado
```

## Quick start

> Requisitos: Docker, Kind, kubectl. (Ver `the-store-main/README.md`.)

```bash
# 1. Levantar el cluster con la app
cd the-store-main && ./local.sh create-cluster --skip-tests && cd ..

# 2. Desplegar toda la solución de acceso remoto + verificar (8 PASS esperados)
vpn/scripts/up.sh
```

`up.sh` corre, en orden: generación de claves → gateway → cliente admin
(Client-To-Site) → red corporativa (Site-To-Site) → NetworkPolicies →
verificación end-to-end.

Demos individuales: `vpn/scripts/verify-encryption.sh` (cifrado en el cable) y
`vpn/scripts/rotate-keys.sh admin` (rotación en caliente).

**Guía paso a paso completa:** [`docs/how-to.md`](./docs/how-to.md).
Teardown: `vpn/scripts/99-teardown.sh`.
