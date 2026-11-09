#!/bin/sh
# Copia a CA raiz local do Caddy para .local/caddy-root.crt e, se possível,
# instala na loja de certificados do sistema. Com --export-only, só copia.
set -eu

cd "$(dirname "$0")/.."
COMPOSE=${COMPOSE:-docker compose}
out=.local/caddy-root.crt
mkdir -p .local

$COMPOSE cp caddy:/data/caddy/pki/authorities/local/root.crt "$out" >/dev/null
echo "trust-ca: CA exportada para $out"

[ "${1:-}" = "--export-only" ] && exit 0

case "$(uname -s)" in
	Darwin)
		sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$out"
		;;
	Linux)
		if grep -qi microsoft /proc/version 2>/dev/null; then
			echo "trust-ca: no WSL, importe $out no Windows (veja docs/AMBIENTE_LOCAL.md)."
		fi
		if [ -d /usr/local/share/ca-certificates ]; then
			sudo cp "$out" /usr/local/share/ca-certificates/condoguard-caddy-local.crt
			sudo update-ca-certificates
		elif [ -d /etc/pki/ca-trust/source/anchors ]; then
			sudo cp "$out" /etc/pki/ca-trust/source/anchors/condoguard-caddy-local.crt
			sudo update-ca-trust
		else
			echo "trust-ca: instale $out manualmente na loja do sistema."
		fi
		echo "trust-ca: Firefox usa loja própria; veja o guia."
		;;
	*)
		echo "trust-ca: instale $out manualmente (veja docs/AMBIENTE_LOCAL.md)."
		;;
esac
