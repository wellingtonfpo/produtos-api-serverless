// PUT /produtos/{id}   corpo: qualquer combinação de nome, preco, estoque
const { UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const { doc, TABLE } = require("./lib/dynamo");
const { resposta, erro, lerJson, validarProduto, tratarErro } = require("./lib/http");

exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    if (!id) return erro(400, "Parâmetro 'id' ausente.");

    const { valor, erro: msg } = validarProduto(lerJson(event), { parcial: true });
    if (msg) return erro(400, msg);

    const campos = { ...valor, atualizadoEm: new Date().toISOString() };
    const nomes = {};
    const valores = {};
    const sets = Object.entries(campos).map(([campo, v], i) => {
      nomes[`#c${i}`] = campo;
      valores[`:v${i}`] = v;
      return `#c${i} = :v${i}`;
    });

    const r = await doc.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { id },
        UpdateExpression: `SET ${sets.join(", ")}`,
        ConditionExpression: "attribute_exists(id)",
        ExpressionAttributeNames: nomes,
        ExpressionAttributeValues: valores,
        ReturnValues: "ALL_NEW",
      })
    );

    return resposta(200, r.Attributes);
  } catch (e) {
    return tratarErro(e);
  }
};
