# Ambiente local do Condoguard

Um comando (`make up`) sobe o sistema inteiro em containers, com HTTPS em
`https://localhost`. Este guia parte de uma máquina limpa.

## O que sobe

| Serviço | Para quê | Acesso pelo host |
|---|---|---|
| `caddy` | Proxy reverso, único ponto de entrada, HTTPS local, limite de requisições | `https://localhost` (portas 80 e 443) |
| `web` | Web em Next.js | via Caddy, em `/` |
| `api` | API em Go | via Caddy, em `/api/*` (ex.: `/api/health`, `/api/docs`) |
| `postgres` | PostgreSQL 17, volume persistente | `127.0.0.1:5432` |
| `redis` | Redis 7 com AOF | `127.0.0.1:6379` |
| `mailpit` | Recebe os e-mails do sistema | `http://127.0.0.1:8025` |
| `minio` | Arquivos (S3) | console em `http://127.0.0.1:9001` |
| `minio-setup` | Cria o bucket e a credencial da API; roda e sai | — |
| `cloudflared` | Cloudflare Tunnel, só no perfil `poc` | — |
| `backup`, `k6` | Ferramentas sob demanda (perfil `tools`) | — |

Só o Caddy publica porta para a rede. Os demais ficam presos em `127.0.0.1` e
não aparecem para outras máquinas. Todos os serviços contínuos têm healthcheck
e `restart: unless-stopped`.

## 1. Pré-requisitos

Você precisa de **Git**, **Make**, **OpenSSL** e **Docker com o Compose v2**
(`docker compose version` deve mostrar 2.24 ou mais novo). Reserve ~8 GB de RAM
e ~10 GB de disco para o Docker.

### Linux (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install -y git make openssl ca-certificates curl
# Docker Engine + plugin do Compose (repositório oficial)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # depois saia e entre de novo na sessão
docker compose version
```

Em Fedora, use `sudo dnf install git make openssl` e siga
<https://docs.docker.com/engine/install/fedora/>.

### macOS

1. Instale o [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   e abra-o uma vez. Em *Settings → Resources*, deixe pelo menos 6 GB de memória.
2. Instale as ferramentas de linha de comando: `xcode-select --install`
   (traz `git` e `make`; o `openssl` já vem no sistema).

### Windows (WSL 2)

O ambiente roda **dentro do WSL 2**, não no PowerShell.

1. No PowerShell como administrador: `wsl --install -d Ubuntu` e reinicie.
2. Instale o [Docker Desktop](https://www.docker.com/products/docker-desktop/) e,
   em *Settings → Resources → WSL integration*, ative a distribuição Ubuntu.
3. No terminal do Ubuntu: `sudo apt update && sudo apt install -y git make openssl`.
4. **Clone o projeto dentro do sistema de arquivos do Linux** (ex.: `~/condoguard`),
   não em `/mnt/c/...`: fica muito mais rápido e evita problemas de permissão.

## 2. Baixar o projeto

```bash
git clone --recurse-submodules https://github.com/victorradael/condoguard.git
cd condoguard
# se já tinha clonado sem os submódulos:
git submodule update --init --recursive
```

## 3. Subir

```bash
make up
```

Na primeira vez, o `make up`:

1. cria o `.env` a partir do `.env.example` e **gera todos os segredos**
   (senhas do Postgres, Redis e MinIO e a chave dos JWT). O `.env` fica fora do
   git e com permissão `600`. Para gerar de novo só os que faltam: `make env`;
2. constrói as imagens da API, do web e do Caddy (alguns minutos);
3. sobe tudo e espera cada serviço ficar saudável. No fim, mostra o `docker compose ps`.

Se algo não ficar saudável em 5 minutos, o comando falha e lista o que faltou.
Veja os logs com `make logs S=api` (ou `web`, `caddy`, `postgres`...).

## 4. Confiar no HTTPS local

O Caddy emite o certificado de `localhost` com uma CA própria, criada na
primeira subida. Para o navegador aceitar sem aviso:

```bash
make trust-ca
```

- **Linux:** instala em `/usr/local/share/ca-certificates` (pede `sudo`).
  O Firefox usa loja própria: *Configurações → Privacidade e Segurança →
  Certificados → Ver certificados → Autoridades → Importar* e escolha
  `.local/caddy-root.crt`.
- **macOS:** instala no *System Keychain* (pede a senha). Reinicie o navegador.
- **Windows/WSL:** o comando exporta a CA para `.local/caddy-root.crt` dentro do
  WSL. No Windows, abra `\\wsl$\Ubuntu\home\<seu-usuário>\condoguard\.local`,
  clique duas vezes em `caddy-root.crt` → *Instalar certificado* → *Máquina
  local* → *Autoridades de Certificação Raiz Confiáveis*.

A CA fica no volume `caddy_data`. Se você apagar os volumes, rode
`make trust-ca` de novo.

## 5. Conferir

| Endereço | Esperado |
|---|---|
| <https://localhost> | tela de login do web |
| <https://localhost/api/health> | `{"status":"ok"}` |
| <https://localhost/api/docs> | Swagger da API (só admin; entre no web como admin antes) |
| <http://127.0.0.1:8025> | caixa de e-mails do Mailpit |
| <http://127.0.0.1:9001> | console do MinIO (usuário `MINIO_ROOT_USER` e senha `MINIO_ROOT_PASSWORD` do `.env`) |

Para conectar um cliente de banco: `127.0.0.1:5432`, banco `condoguard`,
usuário `condoguard_app` e a senha `POSTGRES_APP_PASSWORD` do `.env`.

Os testes automáticos de ponta a ponta fazem essa conferência: `make e2e`.

## Comandos

| Comando | O que faz |
|---|---|
| `make up` | Sobe tudo e espera ficar saudável |
| `make down` | Para tudo, **mantendo** os dados |
| `make ps` / `make logs S=api` | Estado e logs |
| `make seed` | Dados fictícios pequenos (1 bloco, 8 unidades; dev e CI) |
| `make seed-poc` | Condomínio fictício da PoC (3 blocos, 120 unidades, 12 meses) |
| `make reset-demo` | Apaga só os dados de demonstração e recria |
| `make backup` | Backup do banco e dos arquivos em `./backups/<data>` |
| `make restore [BACKUP=nome]` | Restaura um backup (padrão: o último). Pede confirmação |
| `make loadtest [SCENARIO=smoke\|carga\|pico]` | Teste de carga com k6 |
| `make e2e` | Testes de ponta a ponta pelo Caddy |
| `make check` | Valida o compose (com todos os perfis) e o isolamento do túnel |
| `make test-backup CONFIRM=1` | Prova backup + restore num volume vazio (**apaga os volumes**) |
| `make poc-up` / `make poc-down` | Liga/desliga o Cloudflare Tunnel |

Os alvos de seed chamam o `cmd/seed` da API. Enquanto ele não existir (chega na
1c), eles avisam e saem sem erro.

Para apagar **tudo**, inclusive os dados:
`docker compose --profile poc --profile tools down --volumes`.

## Banco de dados

O Postgres cria três papéis na primeira subida (`docker/postgres/initdb/`):

- `postgres`: superusuário, só para administração e backup;
- `condoguard_owner`: dono do esquema, usado pela API apenas para rodar as
  migrações ao subir (`DATABASE_MIGRATIONS_URL`);
- `condoguard_app`: usado pela API em execução (`DATABASE_URL`). Sem
  `SUPERUSER` e sem `BYPASSRLS`, então as políticas de Row-Level Security valem
  para ele. Recebe automaticamente `SELECT/INSERT/UPDATE/DELETE` em tudo que as
  migrações criarem, mas não pode alterar o esquema.

As senhas só são aplicadas quando o volume está vazio. Trocar uma senha no
`.env` depois exige recriar o volume (ou `ALTER ROLE` manual).

## Backup e restauração

```bash
make backup                       # cria ./backups/20261108T203000Z/
make restore                      # restaura o último (pede confirmação)
make restore BACKUP=20261108T203000Z YES=1
```

Cada backup tem `postgres.dump` (`pg_dump -Fc`), a cópia de todos os buckets do
MinIO e um `SHA256SUMS` conferido antes da restauração. A pasta pode ser trocada
com `BACKUP_DIR` no `.env`. Usuários e políticas do MinIO não vão no backup:
o `minio-setup` recria tudo a cada `make up`.

A restauração num volume vazio é testada no CI por `make test-backup`.

## Teste de carga (k6)

```bash
make loadtest                     # smoke: 1 usuário por 30 s
make loadtest SCENARIO=carga      # 50 usuários por 10 min
make loadtest SCENARIO=pico       # 0 → 150 usuários em 1 min, 2 min no topo
```

O caminho é k6 → Caddy → API, dentro da rede do compose. O roteiro
(`loadtest/login-listagens.js`) faz login e percorre as listagens, e reprova se
o p95 do login passar de 400 ms, o das listagens passar de 150 ms ou os erros
passarem de 0,5% (limites em dobro no pico). Respostas 429 do limite de
requisições contam à parte. Os resultados ficam em `loadtest/results/`.

Para medir com os dados da PoC, rode `make seed-poc` antes e defina
`K6_EMAIL`/`K6_PASSWORD` no `.env` com uma das contas de teste. Anote as
especificações da máquina junto com cada resultado.

## PoC pela internet (Cloudflare Tunnel)

O túnel publica o sistema num domínio seu sem abrir portas no roteador. O
`cloudflared` só alcança o Caddy: ele fica numa rede (`edge`) onde não existe
API, web nem banco, e o `make check` confere isso e a configuração do túnel.

Você precisa de uma conta na Cloudflare com um domínio já ativo nela.

1. **Instale o `cloudflared` no seu computador** (só para criar o túnel):
   - Linux: veja <https://pkg.cloudflare.com/> (pacote `cloudflared`);
   - macOS: `brew install cloudflared`;
   - WSL: igual ao Linux, dentro do Ubuntu.
2. **Autorize** (abre o navegador; escolha o domínio):
   ```bash
   cloudflared tunnel login
   ```
3. **Crie o túnel nomeado** e anote o ID (UUID) que aparece:
   ```bash
   cloudflared tunnel create condoguard
   ```
   Isso grava o arquivo de credenciais em `~/.cloudflared/<ID>.json`.
4. **Aponte um subdomínio para o túnel** (cria o registro DNS):
   ```bash
   cloudflared tunnel route dns condoguard poc.seudominio.com.br
   ```
5. **Configure o projeto:**
   ```bash
   cp cloudflared/config.yml.example cloudflared/config.yml
   cp ~/.cloudflared/<ID>.json cloudflared/
   ```
   Em `cloudflared/config.yml`, troque `TUNNEL_ID` (duas vezes) pelo ID e
   `condoguard.example.com` pelo seu subdomínio. **Não mude o `service`**: ele
   precisa continuar `http://caddy:8080`.
   No Linux, deixe as credenciais legíveis só pelo usuário do container:
   ```bash
   sudo chown 65532 cloudflared/<ID>.json && chmod 400 cloudflared/<ID>.json
   ```
6. **Inclua o domínio nas origens da API**, no `.env`:
   `CORS_ALLOWED_ORIGINS=https://localhost,https://poc.seudominio.com.br`
7. **Suba com o túnel:**
   ```bash
   make poc-up
   ```
   e abra `https://poc.seudominio.com.br`.

Os arquivos de `cloudflared/` (fora o modelo) ficam fora do git. O certificado
`~/.cloudflared/cert.pem` do passo 2 não precisa ir para o projeto.

## Problemas comuns

- **Porta 80 ou 443 ocupada:** troque `HTTP_PORT`/`HTTPS_PORT` no `.env`
  (ex.: 8080/8443) e acesse `https://localhost:8443`.
- **Porta 5432 ou 6379 ocupada** (Postgres/Redis instalados no host): troque
  `POSTGRES_HOST_PORT`/`REDIS_HOST_PORT` no `.env`.
- **Não quero o sistema visível na rede local:** `CADDY_BIND_ADDRESS=127.0.0.1`.
  Para testar o app no celular, deixe `0.0.0.0`.
- **Submódulos vazios** (`api/` ou `web/` sem arquivos):
  `git submodule update --init --recursive`.
- **Muitos 429:** os limites por IP do Caddy estão em `RATE_LIMIT_EVENTS` e
  `RATE_LIMIT_AUTH_EVENTS` no `.env`. Os da API (login e cadastro) usam o IP
  real do cliente, que o Caddy manda em `X-Real-IP`; a API só confia nele
  vindo da sub-rede `APP_SUBNET` (`TRUSTED_PROXIES`).
- **Ambiente criado antes da sub-rede fixa** (FAB-16): a rede `app` antiga não
  tem `APP_SUBNET`, e a API veria o IP do Caddy fora da lista. Rode
  `make down && make up` uma vez para o Docker recriar a rede. Os dados ficam.
- **`Pool overlaps with other one on this host`** ao subir: a sub-rede
  `172.28.0.0/24` colide com outra rede da máquina. Troque `APP_SUBNET` no
  `.env` e rode `make down` e `make up`.
- **Navegador avisa que o certificado não é confiável:** `make trust-ca` e
  reinicie o navegador.

## Por que o MinIO vem da pgsty

O projeto MinIO original foi arquivado e deixou de publicar imagens Docker. O
ambiente usa o fork comunitário mantido pela pgsty (`pgsty/minio` e `pgsty/mc`),
compatível com a mesma API S3 e com o console. Como a API fala S3 puro, trocar
de fornecedor depois é só mudar a imagem e as credenciais.
