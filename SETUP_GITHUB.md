# Como Criar o Repositório no GitHub

## Opção 1: Usar API do GitHub (Recomendado - Automatizado)

### Passo 1: Criar um Personal Access Token (PAT)

1. Acesse: https://github.com/settings/tokens
2. Clique em **"Generate new token"** -> **"Generate new token (classic)"**
3. Dê um nome descritivo (ex: `mi50-rocm7`)
4. Selecione o escopo **`repo`** (acesso completo a repositórios)
5. Clique em **"Generate token"**
6. **Copie o token imediatamente** (começa com `ghp_`) - você não poderá vê-lo novamente!

### Passo 2: Executar o Script

```bash
cd ~/mi50-rocm7
./create_github_repo.sh SEU_TOKEN SEU_USUARIO mi50-rocm7 public
```

Substitua:
- `SEU_TOKEN`: O token que você copiou (ex: `ghp_xxxxxxxxxxxx`)
- `SEU_USUARIO`: Seu usuário do GitHub
- `mi50-rocm7`: Nome do repositório (pode ser outro)
- `public` ou `private`: Visibilidade do repositório

O script criará o repositório automaticamente e mostrará os próximos passos.

## Opção 2: Usar GitHub CLI (gh) - Se Instalado

Se você tem o GitHub CLI instalado:

```bash
# Autenticar (se ainda não fez)
gh auth login

# Criar o repositório
cd ~/mi50-rocm7
gh repo create mi50-rocm7 --public --description "Guia completo para instalar ROCm 7.0.2 na AMD MI50 para LocalLLaMA" --source=. --remote=origin --push
```

Isso criará o repositório, adicionará o remote e fará o push automaticamente!

## Opção 3: Usar Interface Web (Manual)

1. Acesse: https://github.com/new
2. Preencha:
   - **Repository name**: `mi50-rocm7` (ou outro nome de sua preferência)
   - **Description**: "Guia completo para instalar ROCm 7.0.2 na AMD MI50 para LocalLLaMA"
   - Escolha **Public** ou **Private**
   - **NÃO marque** nenhuma opção (README, .gitignore, license) - já temos esses arquivos
3. Clique em **"Create repository"**

## Passo 3: Executar os Comandos Git

Após criar o repositório no GitHub, você receberá uma URL. Use os comandos abaixo substituindo `SEU_USUARIO` pela sua conta do GitHub:

```bash
# Navegar até o diretório do projeto
cd ~/mi50-rocm7

# Inicializar o repositório Git
git init

# Adicionar todos os arquivos
git add .

# Fazer o commit inicial
git commit -m "Initial commit: Guia completo ROCm 7.0.2 para MI50"

# Adicionar o repositório remoto (substitua SEU_USUARIO)
git remote add origin https://github.com/SEU_USUARIO/mi50-rocm7.git

# Renomear branch para main (se necessário)
git branch -M main

# Fazer push para o GitHub
git push -u origin main
```

## Alternativa: Usar SSH

Se você preferir usar SSH em vez de HTTPS:

```bash
git remote add origin git@github.com:SEU_USUARIO/mi50-rocm7.git
git push -u origin main
```

## Notas Importantes

- O arquivo `.deb` será incluído no repositório (pode ser grande, mas é necessário)
- Os arquivos em `tensor-files/` também serão incluídos (são essenciais para o funcionamento)
- Se o repositório ficar muito grande, considere usar Git LFS para os arquivos binários
