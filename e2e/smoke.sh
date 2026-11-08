#!/bin/sh
# Testes de ponta a ponta do ambiente, sempre pelo Caddy (https://localhost).
# Pré-requisitos: `make up`, `make seed` e `make trust-ca` (ou CA em CA_CERT).
#
# Conta usada: E2E_USERNAME/E2E_PASSWORD (contas de teste do perfil seed). Sem
# elas, cria uma conta descartável via /auth/register enquanto o seed não existe.
set -eu

cd "$(dirname "$0")/.."
BASE=${BASE_URL:-https://localhost}
CA=${CA_CERT:-.local/caddy-root.crt}
CURL="curl -sS --max-time 15 --cacert $CA"
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1" >&2; failures=$((failures + 1)); }

# expect_status DESCRIÇÃO STATUS_ESPERADO [args do curl...]
expect_status() {
	desc=$1
	want=$2
	shift 2
	got=$($CURL -o /dev/null -w '%{http_code}' "$@" || echo 000)
	if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (esperado $want, veio $got)"; fi
}

[ -f "$CA" ] || { echo "smoke: CA não encontrada em $CA (rode make trust-ca)" >&2; exit 1; }

echo "# borda"
expect_status "http redireciona para https" 308 --cacert "$CA" "http://localhost/"
expect_status "web responde em /login" 200 "$BASE/login"
expect_status "web em / leva ao login" 200 -L "$BASE/"
expect_status "API saudável em /api/health" 200 "$BASE/api/health"
expect_status "OpenAPI em /api/openapi.json" 200 "$BASE/api/openapi.json"
expect_status "métricas internas bloqueadas" 404 "$BASE/api/metrics"
hsts=$($CURL -o /dev/null -D - "$BASE/" | tr -d '\r' | grep -i '^strict-transport-security:' || true)
if [ -n "$hsts" ]; then pass "cabeçalho HSTS presente"; else fail "cabeçalho HSTS ausente"; fi

echo "# autenticação"
user=${E2E_USERNAME:-}
pass_=${E2E_PASSWORD:-}
if [ -z "$user" ]; then
	suffix=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
	user="e2e-$suffix"
	pass_="E2e-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
	expect_status "cadastro de conta descartável" 201 -X POST "$BASE/api/auth/register" \
		-H 'Content-Type: application/json' \
		-d "{\"username\":\"$user\",\"email\":\"$user@e2e.condoguard.local\",\"password\":\"$pass_\"}"
fi

expect_status "login com senha errada é recusado" 401 -X POST "$BASE/api/auth/login" \
	-H 'Content-Type: application/json' -d "{\"username\":\"$user\",\"password\":\"errada-$pass_\"}"

token=$($CURL -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
	-d "{\"username\":\"$user\",\"password\":\"$pass_\"}" |
	sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [ -n "$token" ]; then pass "login devolve token"; else fail "login não devolveu token"; fi

echo "# listagens"
expect_status "listagem sem token é recusada" 401 "$BASE/api/residents"
for path in residents expenses notifications shopOwners; do
	expect_status "GET /api/$path autenticado" 200 -H "Authorization: Bearer $token" "$BASE/api/$path"
done

if [ "$failures" -gt 0 ]; then
	echo "smoke: $failures falha(s)" >&2
	exit 1
fi
echo "smoke: tudo certo"
