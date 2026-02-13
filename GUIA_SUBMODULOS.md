# Guia de Trabalho com Submódulos - CondoGuard

Este repositório atua como um agregador central para os diferentes componentes do sistema CondoGuard (`api`, `web`, `app`). Cada pasta é um **submódulo Git**, o que significa que aponta para um commit específico em outro repositório.

## Visão Geral da Estrutura

- **api/** -> Aponta para [condoguard-api](https://github.com/victorradael/condoguard-api)
- **web/** -> Aponta para [condoguard-interface](https://github.com/victorradael/condoguard-interface)
- **app/** -> Aponta para [condoguard-app](https://github.com/victorradael/condoguard-app)

---

## 🚀 Configuração Inicial

Ao clonar este repositório pela primeira vez, as pastas dos submódulos estarão vazias. Para baixar o conteúdo:

```bash
# Clone o repositório principal com a flag recursive
git clone --recursive https://github.com/victorradael/condoguard.git

# OU se já clonou sem a flag recursive:
git submodule update --init --recursive
```

---

## 🛠 Fluxo de Trabalho Diário

### 1. Atualizar todos os submódulos
Para garantir que você está trabalhando com a versão mais recente de todos os projetos:

```bash
# Puxa as alterações mais recentes dos branches remotos de cada submódulo
git submodule update --remote --merge
```

### 2. Trabalhando em um Submódulo (Ex: API)

Quando você entra na pasta `api/`, você está tecnicamente em outro repositório Git.

1.  **Navegue até o diretório**:
    ```bash
    cd api
    ```

2.  **Crie uma branch ou faça checkout na main**:
    *Atenção: Submódulos frequentemente ficam em estado "detached HEAD". Sempre garanta que está em uma branch antes de commitar.*
    ```bash
    git checkout main
    git pull origin main
    ```

3.  **Faça suas alterações, commit e push (COMO NORMALMENTE)**:
    ```bash
    git add .
    git commit -m "feat: nova funcionalidade na api"
    git push origin main
    ```

### 3. Atualizando a Referência no Repositório Principal (CRÍTICO)

Depois de fazer um push no submódulo (passo anterior), o repositório principal (`condoguard`) vai detectar que a referência do commit da `api` mudou. **Você precisa commitar essa atualização no repositório principal.**

1.  Volte para a raiz:
    ```bash
    cd ..
    ```

2.  Verifique o status:
    ```bash
    git status
    # Você verá algo como:
    # modified:   api (new commits)
    ```

3.  Commit e Push no Repositório Principal:
    ```bash
    git add api
    git commit -m "chore: atualiza referência do submódulo api"
    git push origin main
    ```

---

## ⚠️ Cuidados Importantes

1.  **Sempre dê Push no Submódulo Primeiro**: Se você atualizar o repositório principal apontando para um commit do submódulo que não foi enviado (push) para o remoto, outros desenvolvedores não conseguirão baixar suas alterações.
2.  **Branches**: O repositório principal aponta para um *commit específico*, não para uma branch. Ao entrar em um submódulo, verifique se está na branch correta (`git checkout main`) antes de começar a trabalhar.
3.  **Conflitos**: Se houver conflitos na referência do submódulo (ex: duas pessoas atualizaram a API), resolva fazendo um `git submodule update` e decidindo qual commit deve ser o oficial.
