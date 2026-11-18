// GET /produtos/{id}
const { GetCommand } = require("@aws-sdk/lib-dynamodb");
const { doc, TABLE } = require("./lib/dynamo");
const { resposta, erro, tratarErro } = require("./lib/http");

exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    if (!id) return erro(400, "Parâmetro 'id' ausente.");

    const r = await doc.send(new GetCommand({ TableName: TABLE, Key: { id } }));
    if (!r.Item) return erro(404, "Produto não encontrado.");

    return resposta(200, r.Item);
  } catch (e) {
    return tratarErro(e);
  }
};
