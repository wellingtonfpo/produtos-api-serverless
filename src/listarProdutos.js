// GET /produtos?limite=20&proximo=<token>
const { ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { doc, TABLE } = require("./lib/dynamo");
const { resposta, erro, tratarErro } = require("./lib/http");

exports.handler = async (event) => {
  try {
    const qs = event.queryStringParameters || {};
    const limite = Math.min(Math.max(parseInt(qs.limite, 10) || 20, 1), 100);

    let inicio;
    if (qs.proximo) {
      try {
        inicio = JSON.parse(Buffer.from(qs.proximo, "base64url").toString("utf8"));
      } catch {
        return erro(400, "Parâmetro 'proximo' inválido.");
      }
    }

    const r = await doc.send(
      new ScanCommand({ TableName: TABLE, Limit: limite, ExclusiveStartKey: inicio })
    );

    return resposta(200, {
      itens: r.Items ?? [],
      proximo: r.LastEvaluatedKey
        ? Buffer.from(JSON.stringify(r.LastEvaluatedKey)).toString("base64url")
        : null,
    });
  } catch (e) {
    return tratarErro(e);
  }
};
