#!/usr/bin/env bash
# Testa o CRUD da API implantada. Uso: ./teste.sh [URL_BASE]
set -euo pipefail
cd "$(dirname "$0")"

URL="${1:-$(cat .api-url 2>/dev/null || true)}"
[[ -n "$URL" ]] || { echo "Informe a URL base ou execute ./deploy.sh primeiro."; exit 1; }
URL="${URL%/}"

req() { # req MÉTODO CAMINHO [CORPO]
  local metodo="$1" caminho="$2" corpo="${3:-}"
  echo "\$ ${metodo} ${caminho} ${corpo}"
  curl -sS -X "$metodo" "${URL}${caminho}" \
    -H 'content-type: application/json' \
    ${corpo:+-d "$corpo"} \
    -w '\n[HTTP %{http_code}]\n\n'
}

echo "== 1. Criar produto"
CRIADO="$(curl -sS -X POST "${URL}/produtos" -H 'content-type: application/json' \
  -d '{"nome":"Teclado mecânico","preco":349.9,"estoque":12}')"
echo "$CRIADO"; echo
ID="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' <<<"$CRIADO")"
[[ -n "$ID" ]] || { echo "Falha ao criar produto."; exit 1; }

echo "== 2. Listar produtos";        req GET    "/produtos"
echo "== 3. Obter produto";          req GET    "/produtos/${ID}"
echo "== 4. Atualizar produto";      req PUT    "/produtos/${ID}" '{"preco":299.9,"estoque":8}'
echo "== 5. Validação (esperado 400)"; req POST "/produtos" '{"nome":"","preco":-1}'
echo "== 6. Remover produto";        req DELETE "/produtos/${ID}"
echo "== 7. Obter removido (esperado 404)"; req GET "/produtos/${ID}"
