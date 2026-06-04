# Imagen única compartida por el gateway del cluster y por los containers
# admin / corp (red corporativa). WireGuard en USERSPACE (wireguard-go) para no
# depender del módulo de kernel: sólo necesita /dev/net/tun + NET_ADMIN.
#
# wireguard-go no está empaquetado en Alpine, así que lo compilamos desde fuente
# (binario Go pequeño y autocontenido) y lo copiamos a la imagen final.

# ---- build stage: compilar wireguard-go ----
FROM golang:1.22-alpine AS build
ARG WIREGUARD_GO_VERSION=0.0.20230223
RUN apk add --no-cache git make bash
RUN git clone --depth 1 --branch "${WIREGUARD_GO_VERSION}" \
        https://git.zx2c4.com/wireguard-go /src \
    && cd /src \
    && make \
    && cp wireguard-go /usr/local/bin/wireguard-go

# ---- runtime stage ----
FROM alpine:3.20
RUN apk add --no-cache \
        wireguard-tools \
        iptables \
        ip6tables \
        iproute2 \
        bash \
        tcpdump \
        curl \
        bind-tools
COPY --from=build /usr/local/bin/wireguard-go /usr/bin/wireguard-go

# wg-quick usa la implementación userspace en vez del módulo de kernel.
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go
ENV LOG_LEVEL=info

CMD ["/bin/bash"]
