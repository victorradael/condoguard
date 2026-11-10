COMPOSE ?= docker compose
SCENARIO ?= smoke
BACKUP ?=

# Arquivos gravados no host (backups, resultados do k6) ficam com o seu usuário.
export HOST_UID := $(shell id -u)
export HOST_GID := $(shell id -g)
# Mesma pasta que o compose usa; criada antes do bind mount para não nascer como root.
export BACKUP_DIR ?= $(or $(shell sed -n 's/^BACKUP_DIR=//p' .env 2>/dev/null | tail -n1),./backups)

.DEFAULT_GOAL := help
.PHONY: help env up down ps logs build seed seed-poc reset-demo backup restore \
	loadtest trust-ca poc-up poc-down check test-backup e2e

help: ## Lista os alvos
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  %-12s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

env: ## Cria o .env e gera os segredos que faltam
	@sh scripts/init-secrets.sh

.env:
	@sh scripts/init-secrets.sh

up: .env ## Sobe tudo e espera ficar saudável
	@test -f api/go.mod -a -f web/package.json || { echo "Submódulos vazios: rode git submodule update --init --recursive"; exit 1; }
	$(COMPOSE) up -d --build --remove-orphans
	@sh scripts/wait-healthy.sh

down: ## Para tudo (mantém os dados)
	$(COMPOSE) --profile poc --profile tools down --remove-orphans

ps: ## Estado dos serviços
	$(COMPOSE) ps --all

logs: ## Acompanha os logs (S=serviço para filtrar)
	$(COMPOSE) logs -f --tail=200 $(S)

build: .env ## Reconstrói as imagens
	$(COMPOSE) --profile tools build

seed: .env ## Dados fictícios pequenos (dev e CI)
	@sh scripts/seed.sh seed

seed-poc: .env ## Condomínio fictício completo da PoC
	@sh scripts/seed.sh seed-poc

reset-demo: .env ## Apaga e recria só os dados de demonstração
	@sh scripts/seed.sh reset-demo

backup: .env ## Backup do Postgres e do MinIO em $(BACKUP_DIR)
	@mkdir -p "$(BACKUP_DIR)"
	$(COMPOSE) --profile tools run --rm backup backup $(BACKUP)

restore: .env ## Restaura um backup (BACKUP=nome; padrão: o último)
	@if [ "$(YES)" != "1" ]; then \
		printf 'Isto SUBSTITUI o banco e os arquivos atuais. Continuar? [s/N] '; \
		read r; [ "$$r" = "s" ] || [ "$$r" = "S" ] || exit 1; \
	fi
	@mkdir -p "$(BACKUP_DIR)"
	-$(COMPOSE) stop api
	$(COMPOSE) --profile tools run --rm backup restore $(BACKUP)
	$(COMPOSE) up -d api
	@sh scripts/wait-healthy.sh

loadtest: .env ## Teste de carga k6 (SCENARIO=smoke|carga|pico)
	@mkdir -p loadtest/results
	$(COMPOSE) --profile tools run --rm k6 run -e SCENARIO=$(SCENARIO) /scripts/login-listagens.js

trust-ca: ## Exporta e instala a CA local do Caddy (HTTPS sem aviso)
	@sh scripts/trust-ca.sh

poc-up: .env ## Sobe também o Cloudflare Tunnel (perfil poc)
	@test -f cloudflared/config.yml || { echo "Falta cloudflared/config.yml (veja docs/AMBIENTE_LOCAL.md)"; exit 1; }
	@sh scripts/check-tunnel.sh
	$(COMPOSE) --profile poc up -d --build --remove-orphans
	@sh scripts/wait-healthy.sh

poc-down: ## Derruba só o túnel
	$(COMPOSE) --profile poc stop cloudflared

check: .env ## Valida o compose (com perfis) e o isolamento do túnel
	$(COMPOSE) config --quiet
	$(COMPOSE) --profile poc --profile tools config --quiet
	@sh scripts/check-tunnel.sh

e2e: ## Testes de ponta a ponta pelo Caddy
	@sh scripts/trust-ca.sh --export-only
	@[ -n "$$E2E_EMAIL" ] || sh scripts/e2e-bootstrap.sh
	@sh e2e/smoke.sh

test-backup: .env ## Prova backup + restore num volume vazio (APAGA os volumes)
	@CONFIRM=$(CONFIRM) sh scripts/test-backup-restore.sh
