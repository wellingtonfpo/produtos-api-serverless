#!/usr/bin/env bash
# Remove TODOS os recursos criados pelo deploy.sh (inclusive os dados da tabela).
set -uo pipefail
cd "$(dirname "$0")"

export AWS_PAGER=""
APP="${APP_NAME:-produtos-api}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region || true)}}"
export AWS_DEFAULT_REGION="${REGION:-us-east-1}"
TABLE="${APP}-produtos"
ROLE="${APP}-lambda-role"
FUNCOES=(listarProdutos obterProduto criarProduto atualizarProduto removerProduto)

read -r -p "Remover API, Lambdas, role e tabela '${TABLE}'? (digite 'sim'): " R
[[ "$R" == "sim" ]] || { echo "Cancelado."; exit 0; }

echo ">> API Gateway"
API_ID="$(aws apigatewayv2 get-apis --query "Items[?Name=='${APP}'].ApiId | [0]" --output text)"
if [[ "$API_ID" != "None" && -n "$API_ID" ]]; then
  aws apigatewayv2 delete-api --api-id "$API_ID"
fi

echo ">> Funções Lambda"
for f in "${FUNCOES[@]}"; do
  aws lambda delete-function --function-name "${APP}-${f}" 2>/dev/null || true
  aws logs delete-log-group --log-group-name "/aws/lambda/${APP}-${f}" 2>/dev/null || true
done

echo ">> Role IAM"
aws iam delete-role-policy --role-name "$ROLE" --policy-name "${APP}-dynamodb" 2>/dev/null || true
aws iam detach-role-policy --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role --role-name "$ROLE" 2>/dev/null || true

echo ">> Tabela DynamoDB"
aws dynamodb delete-table --table-name "$TABLE" >/dev/null 2>&1 || true

rm -rf build .api-url
echo "Recursos removidos."
