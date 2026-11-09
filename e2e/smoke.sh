#!/bin/sh
# Testes de ponta a ponta do ambiente, sempre pelo Caddy (https://localhost).
# Pré-requisitos: `make up`, `make seed` e `make trust-ca` (ou CA em CA_CERT).
#
# Conta usada: E2E_EMAIL/E2E_PASSWORD (contas de teste do perfil seed). Sem
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
expect_status "OpenAPI sem login é recusado" 401 "$BASE/api/openapi.json"
expect_status "Swagger sem login é recusado" 401 "$BASE/api/docs"
expect_status "métricas internas bloqueadas" 404 "$BASE/api/metrics"
hsts=$($CURL -o /dev/null -D - "$BASE/" | tr -d '\r' | grep -i '^strict-transport-security:' || true)
if [ -n "$hsts" ]; then pass "cabeçalho HSTS presente"; else fail "cabeçalho HSTS ausente"; fi

echo "# autenticação (bearer, como o app)"
email=${E2E_EMAIL:-}
pass_=${E2E_PASSWORD:-}
if [ -z "$email" ]; then
	suffix=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
	email="e2e-$suffix@e2e.condoguard.local"
	pass_="E2e-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
	expect_status "cadastro de conta descartável" 201 -X POST "$BASE/api/auth/register" \
		-H 'Content-Type: application/json' \
		-d "{\"username\":\"e2e-$suffix\",\"email\":\"$email\",\"password\":\"$pass_\"}"
fi
login_body="{\"email\":\"$email\",\"password\":\"$pass_\"}"

expect_status "login com senha errada é recusado" 401 -X POST "$BASE/api/auth/login" \
	-H 'Content-Type: application/json' -d "{\"email\":\"$email\",\"password\":\"errada-$pass_\"}"

token=$($CURL -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' -d "$login_body" |
	sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')
if [ -n "$token" ]; then pass "login devolve token"; else fail "login não devolveu token"; fi

echo "# listagens"
expect_status "listagem sem token é recusada" 401 "$BASE/api/residents"
for path in residents expenses notifications shop-owners; do
	expect_status "GET /api/$path autenticado" 200 -H "Authorization: Bearer $token" "$BASE/api/$path"
done
expect_status "OpenAPI só para admin" 403 -H "Authorization: Bearer $token" "$BASE/api/openapi.json"

echo "# sessão do web (cookies httpOnly pelo Caddy)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
jar=$tmp/jar
web_login() { $CURL -o "$tmp/body" -w '%{http_code}' -X POST "$BASE/api/auth/login" \
	-H 'Content-Type: application/json' -H "Origin: $1" -b "$jar" -c "$jar" \
	-d "{\"email\":\"$email\",\"password\":\"$pass_\",\"useCookies\":true}" || echo 000; }

got=$(web_login "$BASE")
if [ "$got" = 200 ]; then pass "login do web com cookie"; else fail "login do web com cookie (esperado 200, veio $got)"; fi
if grep -q 'accessToken\|refreshToken' "$tmp/body"; then fail "tokens no corpo do login do web"; else pass "tokens fora do corpo do login do web"; fi
# Formato do cookie jar do curl: domínio, subdomínios, caminho, secure, validade, nome, valor.
if awk '$6 == "cg_refresh" && $3 == "/api/auth" && $4 == "TRUE" && $1 ~ /^#HttpOnly_/ { ok = 1 } END { exit !ok }' "$jar"; then
	pass "cg_refresh httpOnly e Secure em /api/auth"
else
	fail "cg_refresh precisa ser httpOnly e Secure em /api/auth: $(grep cg_refresh "$jar" || echo ausente)"
fi
expect_status "GET /api/users/me com o cookie" 200 -b "$jar" "$BASE/api/users/me"
expect_status "/dashboard com sessão abre sem voltar ao login" 200 -b "$jar" "$BASE/dashboard"
expect_status "/dashboard sem sessão vai para o login" 307 "$BASE/dashboard"
expect_status "refresh pelo cookie" 200 -X POST -H "Origin: $BASE" -b "$jar" -c "$jar" "$BASE/api/auth/refresh"
expect_status "refresh pelo cookie vindo de outra origem é recusado" 403 -X POST \
	-H 'Origin: https://evil.example' -b "$jar" "$BASE/api/auth/refresh"
got=$(rm -f "$tmp/foreign" && jar=$tmp/foreign web_login https://evil.example)
if [ "$got" = 403 ]; then pass "login com cookie vindo de outra origem é recusado"; else fail "login com cookie de outra origem (esperado 403, veio $got)"; fi
cp "$jar" "$tmp/old"
expect_status "logout" 204 -X POST -H "Origin: $BASE" -b "$jar" -c "$jar" "$BASE/api/auth/logout"
expect_status "refresh depois do logout é recusado" 401 -X POST -H "Origin: $BASE" -b "$tmp/old" "$BASE/api/auth/refresh"

if [ "$failures" -gt 0 ]; then
	echo "smoke: $failures falha(s)" >&2
	exit 1
fi
echo "smoke: tudo certo"
