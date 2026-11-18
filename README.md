# API REST serverless de produtos (AWS Lambda)

```
Cliente  →  API Gateway (HTTP API)  →  Lambda (uma função por rota)  →  DynamoDB
```

Sem autenticação: **a API fica pública**. Use apenas para estudo/testes e remova com `./destroy.sh` ao terminar.

## Rotas

| Rota                   | Função Lambda       | Descrição                                 |
|------------------------|---------------------|-------------------------------------------|
| `GET /produtos`        | `listarProdutos`    | Lista (paginação: `?limite=20&proximo=`)  |
| `GET /produtos/{id}`   | `obterProduto`      | Busca um produto                          |
| `POST /produtos`       | `criarProduto`      | Cria (`nome`, `preco`, `estoque`)         |
| `PUT /produtos/{id}`   | `atualizarProduto`  | Atualiza `nome`, `preco` e/ou `estoque`   |
| `DELETE /produtos/{id}`| `removerProduto`    | Remove                                    |

## Estrutura

```
produtos-api/
├── src/
│   ├── listarProdutos.js  obterProduto.js  criarProduto.js
│   ├── atualizarProduto.js  removerProduto.js
│   └── lib/ dynamo.js  http.js      # código compartilhado
├── deploy.sh     # cria/atualiza tudo via AWS CLI
├── teste.sh      # CRUD completo com curl
└── destroy.sh    # remove tudo
```

## Pré-requisitos

- AWS CLI v2 configurado (`aws configure`) com permissões para IAM, Lambda, DynamoDB e API Gateway
- `zip` e `curl` instalados
- Região: `AWS_REGION` / `AWS_DEFAULT_REGION` ou a configurada no CLI (padrão `us-east-1`)

## Implantação

```bash
chmod +x *.sh
./deploy.sh
```

O script executa, nesta ordem:

1. `aws dynamodb create-table` — tabela `produtos-api-produtos` (chave `id`, cobrança sob demanda)
2. `aws iam create-role` + políticas — logs no CloudWatch e acesso **somente** às 5 ações usadas, **somente** nesta tabela
3. `zip` do diretório `src/`
4. `aws lambda create-function` — 5 funções (Node.js 22, arm64, 256 MB, timeout 10 s); em novas execuções faz `update-function-code`
5. `aws apigatewayv2` — HTTP API, integrações `AWS_PROXY`, rotas, permissões `lambda add-permission` e stage `$default` com deploy automático e limites (`burst 50`, `rate 25 req/s`)

Ao final imprime a URL base (também salva em `.api-url`). Para publicar uma alteração de código, basta rodar `./deploy.sh` de novo.

## Testando

```bash
./teste.sh                      # roda o CRUD completo

URL=$(cat .api-url)
curl -X POST "$URL/produtos" -H 'content-type: application/json' \
     -d '{"nome":"Mouse","preco":89.9,"estoque":20}'
curl "$URL/produtos"
```

Logs: `aws logs tail /aws/lambda/produtos-api-listarProdutos --follow`

## Limpeza

```bash
./destroy.sh    # pede confirmação; apaga API, Lambdas, role, logs e tabela
```

## Observações

- Nome base configurável: `APP_NAME=minha-api ./deploy.sh` (use o mesmo valor no `destroy.sh`).
- `GET /produtos` usa `Scan`, adequado para exemplos e tabelas pequenas; em produção, modele chaves de acesso e use `Query`.
- O SDK v3 já vem no runtime Node.js da Lambda, então não há `node_modules` no pacote.
- Custos: tudo é pago por uso e, em volume de teste, tende a ficar no nível gratuito/centavos.
