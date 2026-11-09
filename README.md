<div style="text-align: center;">
    <img src="assets/condoguard-logo.png" alt="CondoguardLogo" height="150">
</div>

---

**CONDOGUARD** é uma aplicação que visa ajudar os condôminos a administrar suas despesas condominiais de forma eficiente e preventiva. Permite gerenciar despesas, fazer previsões financeiras e identificar possíveis problemas antes que se tornem críticos.

## Objetivo

Fornecer uma ferramenta robusta e amigável para a gestão financeira de residências e condomínios, dando a administradores e moradores uma visão clara de suas despesas e histórico de gastos.

## Repositório

Este é um monorepo com submódulos Git:

| Submódulo | Descrição | Stack |
|-----------|-----------|-------|
| `api/` | REST API do backend | Go 1.25, PostgreSQL 17, Redis 7 |
| `web/` | Aplicação web (frontend) | — |
| `app/` | Aplicação mobile | — |

## API

A API REST está em `api/` e fornece os seguintes recursos:

- **Autenticação** — registro e login com JWT (HS256, 10h)
- **Usuários** — CRUD completo (acesso restrito a `ROLE_ADMIN`)
- **Residências** — CRUD com unicidade de unidade por condomínio
- **Lojas** — CRUD com validação de CNPJ
- **Despesas** — CRUD com valores em centavos e filtro por período
- **Notificações** — CRUD com operação idempotente de marcar como lida

Consulte [`api/README.md`](api/README.md) para instruções de instalação e uso.

## Clonando o projeto com submódulos

```bash
git clone --recurse-submodules https://github.com/victorradael/condoguard.git
```

Se já clonou sem os submódulos:

```bash
git submodule update --init --recursive
```

## Ambiente local

Com Docker e Make instalados, um comando sobe tudo (API, web, PostgreSQL, Redis,
Mailpit, MinIO e Caddy) em `https://localhost`:

```bash
make up
```

Passo a passo para Linux, macOS e Windows/WSL, backup, teste de carga e PoC
pelo Cloudflare Tunnel em [`docs/AMBIENTE_LOCAL.md`](docs/AMBIENTE_LOCAL.md).
`make help` lista todos os comandos.

> Já tinha o ambiente de pé antes da FAB-16 (sub-rede fixa da rede `app`)?
> Rode `make down && make up` uma vez para o Docker recriar a rede.

## Licença

[GNU General Public License v3.0](api/LICENSE)

---

**CondoGuard** — Simplificando a gestão do seu condomínio.
