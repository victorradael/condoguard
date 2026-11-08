#!/bin/sh
# Espera todos os serviços contínuos do compose ficarem saudáveis.
# Uso: scripts/wait-healthy.sh [timeout_em_segundos] (padrão 300)
set -eu

cd "$(dirname "$0")/.."
COMPOSE=${COMPOSE:-docker compose}
timeout=${1:-300}
elapsed=0

while :; do
	# Formato: serviço estado saúde (saúde vazia = sem healthcheck)
	status=$($COMPOSE ps --all --format '{{.Service}} {{.State}} {{.Health}}')
	pending=$(printf '%s\n' "$status" | awk '
		$1 == "minio-setup" { if ($2 == "exited") next }
		$2 != "running" || ($3 != "" && $3 != "healthy") { print $1 "(" $2 (($3 != "") ? "/" $3 : "") ")" }')
	failed_setup=$($COMPOSE ps --all --format '{{.Service}} {{.ExitCode}}' | awk '$1 == "minio-setup" && $2 != "0"')

	if [ -n "$failed_setup" ]; then
		echo "wait-healthy: minio-setup falhou" >&2
		$COMPOSE logs minio-setup >&2
		exit 1
	fi
	if [ -z "$pending" ]; then
		echo "wait-healthy: todos os serviços saudáveis"
		$COMPOSE ps
		exit 0
	fi
	if [ "$elapsed" -ge "$timeout" ]; then
		echo "wait-healthy: tempo esgotado (${timeout}s). Pendentes: $pending" >&2
		$COMPOSE ps --all >&2
		exit 1
	fi
	sleep 5
	elapsed=$((elapsed + 5))
done
