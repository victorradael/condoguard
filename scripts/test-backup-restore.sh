#!/bin/sh
# Prova que backup + restore recuperam os dados num volume vazio.
#
# 1. grava um marcador no Postgres e um arquivo no MinIO
# 2. make backup
# 3. derruba o ambiente APAGANDO os volumes
# 4. sobe Postgres e MinIO do zero e restaura
# 5. confere o marcador e o arquivo
#
# DESTRUTIVO: apaga os volumes do projeto. Exige CONFIRM=1.
set -eu

cd "$(dirname "$0")/.."
COMPOSE=${COMPOSE:-docker compose}
HOST_UID=$(id -u)
HOST_GID=$(id -g)
export HOST_UID HOST_GID

if [ "${CONFIRM:-}" != "1" ]; then
	echo "test-backup-restore: isto apaga os volumes do ambiente. Rode com CONFIRM=1." >&2
	exit 2
fi

name="teste-$(date -u +%Y%m%dT%H%M%SZ)"
marker="restore-check-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
backup_run="$COMPOSE --profile tools run --rm -T backup"
psql_q() { $COMPOSE exec -T postgres psql -U postgres -d condoguard -tAc "$1"; }
mc_root() {
	$COMPOSE run --rm -T --no-deps --entrypoint /bin/sh minio-setup -c \
		"mc alias set local http://minio:9000 \"\$MINIO_ROOT_USER\" \"\$MINIO_ROOT_PASSWORD\" >/dev/null && $1"
}

echo "== 1. dados de teste"
$COMPOSE up -d --wait postgres minio
psql_q "CREATE TABLE IF NOT EXISTS public._restore_check (valor text PRIMARY KEY)"
psql_q "INSERT INTO public._restore_check VALUES ('$marker')"
mc_root "mc mb --ignore-existing local/\"\$S3_BUCKET\" >/dev/null && echo '$marker' | mc pipe local/\"\$S3_BUCKET\"/_restore_check.txt >/dev/null"

echo "== 2. backup"
$backup_run backup "$name"

echo "== 3. apagando volumes"
$COMPOSE --profile tools --profile poc down --volumes --remove-orphans

echo "== 4. subindo do zero e restaurando"
$COMPOSE up -d --wait postgres minio
empty=$(psql_q "SELECT to_regclass('public._restore_check') IS NULL")
[ "$empty" = "t" ] || { echo "falha: o volume novo não está vazio" >&2; exit 1; }
$backup_run restore "$name"

echo "== 5. conferindo"
got=$(psql_q "SELECT valor FROM public._restore_check")
[ "$got" = "$marker" ] || { echo "falha: marcador no Postgres = '$got'" >&2; exit 1; }
obj=$(mc_root "mc cat local/\"\$S3_BUCKET\"/_restore_check.txt")
[ "$obj" = "$marker" ] || { echo "falha: arquivo no MinIO = '$obj'" >&2; exit 1; }

psql_q "DROP TABLE public._restore_check"
mc_root "mc rm local/\"\$S3_BUCKET\"/_restore_check.txt >/dev/null"
echo "test-backup-restore: OK (backup $name restaurado num volume vazio)"
