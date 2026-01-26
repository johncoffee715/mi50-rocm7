#!/bin/bash

# Script para criar repositório no GitHub via API
# Uso: ./create_github_repo.sh SEU_TOKEN SEU_USUARIO NOME_REPO [PRIVATE]

set -e

if [ $# -lt 3 ]; then
    echo "Uso: $0 <GITHUB_TOKEN> <GITHUB_USERNAME> <REPO_NAME> [private|public]"
    echo ""
    echo "Exemplo:"
    echo "  $0 ghp_xxxxxxxxxxxx seu_usuario mi50-rocm7 public"
    echo ""
    echo "Para criar um token:"
    echo "  1. Acesse: https://github.com/settings/tokens"
    echo "  2. Clique em 'Generate new token' -> 'Generate new token (classic)'"
    echo "  3. Dê um nome (ex: 'mi50-rocm7')"
    echo "  4. Marque a permissão 'repo' (acesso completo a repositórios)"
    echo "  5. Clique em 'Generate token'"
    echo "  6. Copie o token (começa com ghp_)"
    exit 1
fi

GITHUB_TOKEN="$1"
GITHUB_USER="$2"
REPO_NAME="$3"
VISIBILITY="${4:-public}"  # default: public

if [ "$VISIBILITY" != "private" ] && [ "$VISIBILITY" != "public" ]; then
    echo "Erro: Visibilidade deve ser 'public' ou 'private'"
    exit 1
fi

echo "Criando repositório '$REPO_NAME' no GitHub..."
echo "Usuário: $GITHUB_USER"
echo "Visibilidade: $VISIBILITY"
echo ""

# Criar repositório via API
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/user/repos \
    -d "{
        \"name\": \"$REPO_NAME\",
        \"description\": \"Guia completo para instalar ROCm 7.0.2 na AMD MI50 para LocalLLaMA\",
        \"private\": $([ "$VISIBILITY" = "private" ] && echo "true" || echo "false"),
        \"auto_init\": false
    }")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$REPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 201 ]; then
    echo "✅ Repositório criado com sucesso!"
    echo ""
    echo "URL do repositório: https://github.com/$GITHUB_USER/$REPO_NAME"
    echo ""
    echo "Agora execute os seguintes comandos:"
    echo ""
    echo "  cd ~/mi50-rocm7"
    echo "  git init"
    echo "  git add ."
    echo "  git commit -m 'Initial commit: Guia completo ROCm 7.0.2 para MI50'"
    echo "  git branch -M main"
    echo "  git remote add origin https://github.com/$GITHUB_USER/$REPO_NAME.git"
    echo "  git push -u origin main"
    echo ""
elif [ "$HTTP_CODE" -eq 422 ]; then
    echo "❌ Erro: Repositório já existe ou nome inválido"
    exit 1
elif [ "$HTTP_CODE" -eq 401 ]; then
    echo "❌ Erro: Token inválido ou sem permissões"
    exit 1
else
    echo "❌ Erro ao criar repositório (HTTP $HTTP_CODE)"
    echo "Resposta: $BODY"
    exit 1
fi
