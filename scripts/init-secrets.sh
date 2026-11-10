#!/bin/sh
# Cria o .env a partir do .env.example (se ainda não existir) e preenche cada
# segredo vazio com um valor aleatório. Idempotente: nunca troca um valor já
# preenchido. Não imprime segredos.
set -eu

cd "$(dirname "$0")/.."

SECRETS="POSTGRES_SUPERUSER_PASSWORD POSTGRES_OWNER_PASSWORD POSTGRES_APP_PASSWORD REDIS_PASSWORD MINIO_ROOT_PASSWORD S3_SECRET_KEY"
SECRETS_BASE64="JWT_SECRET_KEY"
# Base64 de exatamente 32 bytes (AES-256): semente do TOTP cifrada em repouso.
SECRETS_KEY32="TOTP_ENCRYPTION_KEY"

if [ ! -f .env ]; then
	cp .env.example .env
	echo "init-secrets: .env criado a partir do .env.example"
fi
chmod 600 .env

# Hex: seguro em URLs de conexão sem precisar de escape.
rand_hex() {
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -hex 32
	else
		od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
	fi
}

rand_base64() {
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -base64 48 | tr -d '\n'
	else
		head -c 48 /dev/urandom | base64 | tr -d '\n'
	fi
}

rand_key32() {
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -base64 32 | tr -d '\n'
	else
		head -c 32 /dev/urandom | base64 | tr -d '\n'
	fi
}

fill() {
	var=$1
	value=$2
	if grep -q "^${var}=" .env; then
		current=$(sed -n "s/^${var}=//p" .env | head -n 1)
		[ -n "$current" ] && return 0
		tmp=$(mktemp .env.XXXXXX)
		awk -v k="$var" -v v="$value" 'BEGIN { done = 0 }
			!done && index($0, k "=") == 1 && length($0) == length(k) + 1 { print k "=" v; done = 1; next }
			{ print }' .env >"$tmp"
		chmod 600 "$tmp"
		mv "$tmp" .env
	else
		printf '%s=%s\n' "$var" "$value" >>.env
	fi
	echo "init-secrets: $var gerado"
}

for var in $SECRETS; do
	fill "$var" "$(rand_hex)"
done
for var in $SECRETS_BASE64; do
	fill "$var" "$(rand_base64)"
done
for var in $SECRETS_KEY32; do
	fill "$var" "$(rand_key32)"
done
