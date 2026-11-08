# Caddy com o plugin de limite de requisições (não vem na imagem oficial).
FROM caddy:2.11.9-builder-alpine AS build
RUN xcaddy build --with github.com/mholt/caddy-ratelimit@5625512f24f6f59d6f64fb3aafe5eecff0b286db

FROM caddy:2.11.9-alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy
