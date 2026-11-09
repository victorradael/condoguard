#!/bin/sh
# Confere, a partir do compose resolvido, que o cloudflared só alcança o Caddy:
# - `docker compose --profile poc config` é válido
# - o cloudflared está só na rede `edge`
# - na rede `edge` só há caddy, cloudflared e k6 (nenhum serviço de app/dados)
# - nenhum serviço além do Caddy publica porta fora de 127.0.0.1
# - o modelo cloudflared/config.yml.example (e o config.yml real, se existir)
#   só encaminha para http://caddy:8080 ou http_status:404
set -eu

cd "$(dirname "$0")/.."
COMPOSE=${COMPOSE:-docker compose}

$COMPOSE --profile poc --profile tools config --format json | python3 -c '
import json, sys

cfg = json.load(sys.stdin)
services = cfg["services"]
errors = []

cf_nets = set((services["cloudflared"].get("networks") or {}).keys())
if cf_nets != {"edge"}:
    errors.append(f"cloudflared deve estar só na rede edge, está em {sorted(cf_nets)}")

edge = sorted(n for n, s in services.items() if "edge" in (s.get("networks") or {}))
if set(edge) - {"caddy", "cloudflared", "k6"}:
    errors.append(f"rede edge tem serviços demais: {edge}")

for name, svc in services.items():
    for p in svc.get("ports") or []:
        ip = p.get("host_ip") or "0.0.0.0"
        published = p.get("published")
        if name != "caddy" and ip != "127.0.0.1":
            errors.append(f"{name} publica a porta {published} em {ip}")

if errors:
    print("check-tunnel: FALHOU", *errors, sep="\n  - ", file=sys.stderr)
    sys.exit(1)
print(f"check-tunnel: compose ok (edge = {edge})")
'

for f in cloudflared/config.yml.example cloudflared/config.yml; do
	[ -f "$f" ] || continue
	bad=$(sed -n 's/^[[:space:]-]*service:[[:space:]]*//p' "$f" | tr -d "\"'" |
		grep -v -x -e 'http://caddy:8080' -e 'http_status:404' || true)
	if [ -n "$bad" ]; then
		echo "check-tunnel: FALHOU: $f encaminha para algo além do Caddy: $bad" >&2
		exit 1
	fi
	echo "check-tunnel: $f ok (só http://caddy:8080)"
done
