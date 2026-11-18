// POST /produtos   corpo: { "nome": "...", "preco": 10.5, "estoque": 3 }
const { randomUUID } = require("node:crypto");
const { PutCommand } = require("@aws-sdk/lib-dynamodb");
const { doc, TABLE } = require("./lib/dynamo");
const { resposta, erro, lerJson, validarProduto, tratarErro } = require("./lib/http");

exports.handler = async (event) => {
  try {
    const { valor, erro: msg } = validarProduto(lerJson(event));
    if (msg) return erro(400, msg);

    const agora = new Date().toISOString();
    const item = { id: randomUUID(), ...valor, criadoEm: agora, atualizadoEm: agora };

    await doc.send(
      new PutCommand({
        TableName: TABLE,
        Item: item,
        ConditionExpression: "attribute_not_exists(id)",
      })
    );

    return resposta(201, item, { Location: `/produtos/${item.id}` });
  } catch (e) {
    return tratarErro(e);
  }
};
