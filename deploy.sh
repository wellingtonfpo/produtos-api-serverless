#!/usr/bin/env bash
# Implanta a API REST serverless: DynamoDB + IAM + 5 Lambdas + API Gateway (HTTP API).
# Idempotente: pode ser executado novamente para publicar alterações no código.
set -euo pipefail
cd "$(dirname "$0")"

export AWS_PAGER=""
APP="${APP_NAME:-produtos-api}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region || true)}}"
REGION="${REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

RUNTIME="nodejs22.x"
TABLE="${APP}-produtos"
ROLE="${APP}-lambda-role"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
TABLE_ARN="arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${TABLE}"

# "função|método|rota" — uma função Lambda por rota
ROUTES=(
  "listarProdutos|GET|/produtos"
  "obterProduto|GET|/produtos/{id}"
  "criarProduto|POST|/produtos"
  "atualizarProduto|PUT|/produtos/{id}"
  "removerProduto|DELETE|/produtos/{id}"
)

command -v zip >/dev/null || { echo "Instale o 'zip' para empacotar as funções."; exit 1; }
echo ">> Conta ${ACCOUNT_ID} | Região ${REGION} | App ${APP}"

# ---------------------------------------------------------------- 1. DynamoDB
echo ">> [1/5] Tabela DynamoDB: ${TABLE}"
if ! aws dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE"
else
  echo "   já existe, mantendo."
fi

# ------------------------------------------------------------------- 2. IAM
echo ">> [2/5] Role IAM: ${ROLE}"
ROLE_NOVA=false
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$ROLE" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "Service": "lambda.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }]
    }' >/dev/null
  ROLE_NOVA=true
fi

# Logs no CloudWatch
aws iam attach-role-policy \
  --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Permissão mínima: apenas as ações usadas, apenas nesta tabela
aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name "${APP}-dynamodb" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"dynamodb:GetItem\",\"dynamodb:PutItem\",\"dynamodb:UpdateItem\",\"dynamodb:DeleteItem\",\"dynamodb:Scan\"],
      \"Resource\": \"${TABLE_ARN}\"
    }]
  }"

ROLE_ARN="$(aws iam get-role --role-name "$ROLE" --query Role.Arn --output text)"
if [[ "$ROLE_NOVA" == true ]]; then
  echo "   aguardando propagação do IAM (10s)..."
  sleep 10
fi

# ------------------------------------------------------------ 3. Empacotar
echo ">> [3/5] Empacotando código"
rm -rf build && mkdir -p build
(cd src && zip -qr ../build/function.zip .)

# ------------------------------------------------------------- 4. Lambdas
echo ">> [4/5] Funções Lambda"
for entrada in "${ROUTES[@]}"; do
  IFS='|' read -r FUNC _ _ <<<"$entrada"
  NOME="${APP}-${FUNC}"

  if aws lambda get-function --function-name "$NOME" >/dev/null 2>&1; then
    echo "   atualizando ${NOME}"
    aws lambda update-function-code \
      --function-name "$NOME" \
      --zip-file fileb://build/function.zip >/dev/null
    aws lambda wait function-updated-v2 --function-name "$NOME"
    aws lambda update-function-configuration \
      --function-name "$NOME" \
      --runtime "$RUNTIME" \
      --handler "${FUNC}.handler" \
      --environment "Variables={TABLE_NAME=${TABLE}}" >/dev/null
    aws lambda wait function-updated-v2 --function-name "$NOME"
  else
    echo "   criando ${NOME}"
    aws lambda create-function \
      --function-name "$NOME" \
      --runtime "$RUNTIME" \
      --architectures arm64 \
      --handler "${FUNC}.handler" \
      --role "$ROLE_ARN" \
      --memory-size 256 \
      --timeout 10 \
      --environment "Variables={TABLE_NAME=${TABLE}}" \
      --zip-file fileb://build/function.zip >/dev/null
    aws lambda wait function-active-v2 --function-name "$NOME"
  fi
done

# ------------------------------------------------------------ 5. API Gateway
echo ">> [5/5] API Gateway (HTTP API): ${APP}"
API_ID="$(aws apigatewayv2 get-apis --query "Items[?Name=='${APP}'].ApiId | [0]" --output text)"
if [[ "$API_ID" == "None" || -z "$API_ID" ]]; then
  API_ID="$(aws apigatewayv2 create-api \
    --name "$APP" \
    --protocol-type HTTP \
    --cors-configuration '{"AllowOrigins":["*"],"AllowMethods":["GET","POST","PUT","DELETE","OPTIONS"],"AllowHeaders":["content-type"]}' \
    --query ApiId --output text)"
fi

for entrada in "${ROUTES[@]}"; do
  IFS='|' read -r FUNC METODO ROTA <<<"$entrada"
  NOME="${APP}-${FUNC}"
  CHAVE="${METODO} ${ROTA}"

  EXISTE="$(aws apigatewayv2 get-routes --api-id "$API_ID" \
    --query "Items[?RouteKey=='${CHAVE}'].RouteId | [0]" --output text)"
  if [[ "$EXISTE" != "None" && -n "$EXISTE" ]]; then
    echo "   rota ${CHAVE} já existe."
    continue
  fi

  echo "   rota ${CHAVE} -> ${NOME}"
  FUNC_ARN="$(aws lambda get-function --function-name "$NOME" \
    --query Configuration.FunctionArn --output text)"

  INTEG_ID="$(aws apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-uri "$FUNC_ARN" \
    --payload-format-version 2.0 \
    --query IntegrationId --output text)"

  aws apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "$CHAVE" \
    --target "integrations/${INTEG_ID}" >/dev/null

  # Permite que o API Gateway invoque esta função (apenas para esta rota)
  ROTA_ARN="$(sed 's/{[^}]*}/*/g' <<<"$ROTA")"
  aws lambda add-permission \
    --function-name "$NOME" \
    --statement-id "apigw-${METODO}-$(tr -c 'A-Za-z0-9' '-' <<<"$ROTA")" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/${METODO}${ROTA_ARN}" >/dev/null
done

# Stage $default com deploy automático e limites de requisições (throttling)
LIMITES='ThrottlingBurstLimit=50,ThrottlingRateLimit=25'
if aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name '$default' >/dev/null 2>&1; then
  aws apigatewayv2 update-stage --api-id "$API_ID" --stage-name '$default' \
    --default-route-settings "$LIMITES" >/dev/null
else
  aws apigatewayv2 create-stage --api-id "$API_ID" --stage-name '$default' \
    --auto-deploy --default-route-settings "$LIMITES" >/dev/null
fi

URL="$(aws apigatewayv2 get-api --api-id "$API_ID" --query ApiEndpoint --output text)"
echo "$URL" > .api-url

echo
echo "Implantação concluída."
echo "URL base: ${URL}"
echo "Teste:    ./teste.sh   (ou: curl ${URL}/produtos)"
