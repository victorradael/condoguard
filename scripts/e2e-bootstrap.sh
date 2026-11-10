#!/bin/sh
# Garante o condomínio padrão antes do e2e, enquanto o seed (1c) não existe.
# O sign-up público só funciona com o condomínio de DEFAULT_CONDOMINIUM_ID, e a
# API o resolve ao subir: se este script o criar, reinicia a API.
# O síndico criado aqui é descartável (a senha nunca é gravada nem exibida).
set -eu

cd "$(dirname "$0")/.."
COMPOSE=${COMPOSE:-docker compose}

suffix=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
pw="Bt-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"

out=$(printf '%s\n' "$pw" | $COMPOSE exec -T \
	-e "ADMIN_EMAIL=e2e-sindico-$suffix@e2e.condoguard.local" \
	-e "ADMIN_USERNAME=e2e-sindico-$suffix" \
	api /app/createadmin) || {
	echo "e2e-bootstrap: createadmin falhou" >&2
	exit 1
}
printf '%s\n' "$out"

case "$out" in
*'condominium '*' created'*)
	echo "e2e-bootstrap: condomínio novo, reiniciando a API para abrir o sign-up"
	$COMPOSE restart api
	sh scripts/wait-healthy.sh 120
	;;
esac
