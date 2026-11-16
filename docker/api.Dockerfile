# Imagem da API usada pelo ambiente local. Contexto de build: ./api
# Compila todos os binários de cmd/ (server hoje; seed a partir da 1c).
# Mesma imagem (fixada por digest) do api/Dockerfile; acompanha o go.mod.
FROM golang:1.27.4-alpine3.24@sha256:0a5f7fe796599ff487605987432e7619ae45beeb2fba4c2ce0b907879932aebf AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/ ./cmd/...

FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf
RUN apk add --no-cache ca-certificates tzdata \
	&& adduser -D -H -u 10001 condoguard
COPY --from=build /out/ /app/
USER 10001
EXPOSE 8080
ENTRYPOINT ["/app/server"]
