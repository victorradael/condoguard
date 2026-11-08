# Imagem da API usada pelo ambiente local. Contexto de build: ./api
# Compila todos os binários de cmd/ (server hoje; seed a partir da 1c).
FROM golang:1.25.14-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/ ./cmd/...

FROM alpine:3.24
RUN apk add --no-cache ca-certificates tzdata \
	&& adduser -D -H -u 10001 condoguard
COPY --from=build /out/ /app/
USER 10001
EXPOSE 8080
ENTRYPOINT ["/app/server"]
