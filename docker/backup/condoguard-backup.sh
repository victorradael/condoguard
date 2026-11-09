#!/bin/sh
# Uso (dentro do container `backup`):
#   condoguard-backup backup [NOME]     grava /backups/NOME (padrão: data UTC)
#   condoguard-backup restore [NOME]    restaura /backups/NOME (padrão: LATEST)
#   condoguard-backup list
#
# Cada backup é uma pasta com:
#   postgres.dump   pg_dump em formato custom (-Fc) do banco condoguard
#   minio/<bucket>/ cópia de todos os buckets
#   SHA256SUMS      conferido antes de qualquer restauração
#
# Usuários e políticas do MinIO não entram: o minio-setup recria a cada subida.
set -eu

BACKUPS=/backups

mc_login() {
	mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
}

do_backup() {
	name=${1:-$(date -u +%Y%m%dT%H%M%SZ)}
	dest="$BACKUPS/$name"
	if [ -e "$dest" ]; then
		echo "backup: $dest já existe" >&2
		exit 1
	fi
	mkdir -p "$dest/minio"

	echo "backup: banco -> $dest/postgres.dump"
	pg_dump --format=custom --file="$dest/postgres.dump"

	mc_login
	for bucket in $(mc ls --json local | sed -n 's/.*"key":"\([^"/]*\)\/".*/\1/p'); do
		echo "backup: bucket $bucket"
		mkdir -p "$dest/minio/$bucket"
		mc mirror --quiet --overwrite "local/$bucket" "$dest/minio/$bucket" >/dev/null
	done

	(cd "$dest" && find . -type f ! -name SHA256SUMS -exec sha256sum {} + | sort -k2 >SHA256SUMS)
	echo "$name" >"$BACKUPS/LATEST"
	echo "backup: concluído em $dest"
}

do_restore() {
	name=${1:-}
	if [ -z "$name" ]; then
		[ -f "$BACKUPS/LATEST" ] || { echo "restore: nenhum backup em $BACKUPS" >&2; exit 1; }
		name=$(cat "$BACKUPS/LATEST")
	fi
	src="$BACKUPS/$name"
	[ -f "$src/postgres.dump" ] || { echo "restore: $src/postgres.dump não encontrado" >&2; exit 1; }

	echo "restore: conferindo integridade de $src"
	(cd "$src" && sha256sum -c -s SHA256SUMS) || { echo "restore: SHA256SUMS não confere" >&2; exit 1; }

	echo "restore: banco"
	pg_restore --dbname="$PGDATABASE" --clean --if-exists --single-transaction --exit-on-error "$src/postgres.dump"

	mc_login
	for dir in "$src"/minio/*/; do
		[ -d "$dir" ] || continue
		bucket=$(basename "$dir")
		echo "restore: bucket $bucket"
		mc mb --ignore-existing "local/$bucket" >/dev/null
		mc mirror --quiet --overwrite --remove "$dir" "local/$bucket" >/dev/null
	done
	echo "restore: concluído a partir de $src"
}

cmd=${1:-backup}
[ $# -gt 0 ] && shift
case "$cmd" in
	backup) do_backup "$@" ;;
	restore) do_restore "$@" ;;
	list) ls -1 "$BACKUPS" | grep -v '^LATEST$' || true ;;
	*) echo "uso: condoguard-backup backup|restore|list [NOME]" >&2; exit 2 ;;
esac
