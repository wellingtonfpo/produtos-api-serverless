// DELETE /produtos/{id}
const { DeleteCommand } = require("@aws-sdk/lib-dynamodb");
const { doc, TABLE } = require("./lib/dynamo");
const { resposta, erro, tratarErro } = require("./lib/http");

exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    if (!id) return erro(400, "Parâmetro 'id' ausente.");

    await doc.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { id },
        ConditionExpression: "attribute_exists(id)",
      })
    );

    return resposta(204);
  } catch (e) {
    return tratarErro(e);
  }
};
