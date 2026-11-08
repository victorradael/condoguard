#!/bin/sh
# Chama o gerador de dados fictícios da API (cmd/seed).
# Uso: scripts/seed.sh seed|seed-poc|reset-demo [argumentos extras do seed]
#
# Enquanto o cmd/seed não existir na API (chega na 1c), avisa e sai sem erro.
set -eu

cd "$(dirname "$0")/.."
COMPOSE=${COMPOSE:-docker compose}

mode=${1:?uso: scripts/seed.sh seed|seed-poc|reset-demo}
shift

case "$mode" in
	seed) args="--profile=seed" ;;
	seed-poc) args="--profile=poc" ;;
	reset-demo) args="--profile=poc --reset-demo" ;;
	*) echo "seed: modo desconhecido '$mode'" >&2; exit 2 ;;
esac

if ! $COMPOSE run --rm --no-deps --entrypoint /bin/sh api -c 'test -x /app/seed'; then
	echo "seed: a API ainda não tem cmd/seed (previsto na 1c). Nada a fazer por enquanto."
	exit 0
fi

# shellcheck disable=SC2086
exec $COMPOSE run --rm --entrypoint /app/seed api $args "$@"
