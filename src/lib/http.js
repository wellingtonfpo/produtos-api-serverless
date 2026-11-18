const HEADERS = { "Content-Type": "application/json; charset=utf-8" };

const resposta = (statusCode, corpo, extra = {}) => ({
  statusCode,
  headers: { ...HEADERS, ...extra },
  body: corpo === undefined ? "" : JSON.stringify(corpo),
});

const erro = (statusCode, mensagem) => resposta(statusCode, { erro: mensagem });

// Lê o corpo JSON do evento (API Gateway HTTP API, payload v2.0).
// Lança SyntaxError se o JSON for inválido.
const lerJson = (event) => {
  if (!event.body) return {};
  const bruto = event.isBase64Encoded
    ? Buffer.from(event.body, "base64").toString("utf8")
    : event.body;
  return JSON.parse(bruto);
};

// Valida os campos de um produto.
// parcial=false (POST): nome e preco obrigatórios. parcial=true (PUT): ao menos um campo.
const validarProduto = (dados, { parcial = false } = {}) => {
  if (dados === null || typeof dados !== "object" || Array.isArray(dados)) {
    return { erro: "O corpo deve ser um objeto JSON." };
  }
  const valor = {};

  if (dados.nome !== undefined) {
    if (typeof dados.nome !== "string" || !dados.nome.trim() || dados.nome.length > 120) {
      return { erro: "'nome' deve ser um texto de 1 a 120 caracteres." };
    }
    valor.nome = dados.nome.trim();
  } else if (!parcial) {
    return { erro: "'nome' é obrigatório." };
  }

  if (dados.preco !== undefined) {
    if (typeof dados.preco !== "number" || !Number.isFinite(dados.preco) || dados.preco < 0) {
      return { erro: "'preco' deve ser um número maior ou igual a zero." };
    }
    valor.preco = dados.preco;
  } else if (!parcial) {
    return { erro: "'preco' é obrigatório." };
  }

  if (dados.estoque !== undefined) {
    if (!Number.isInteger(dados.estoque) || dados.estoque < 0) {
      return { erro: "'estoque' deve ser um inteiro maior ou igual a zero." };
    }
    valor.estoque = dados.estoque;
  } else if (!parcial) {
    valor.estoque = 0;
  }

  if (parcial && Object.keys(valor).length === 0) {
    return { erro: "Informe ao menos um campo: nome, preco ou estoque." };
  }
  return { valor };
};

// Converte exceções em respostas HTTP.
const tratarErro = (e, { naoEncontrado = "Produto não encontrado." } = {}) => {
  if (e instanceof SyntaxError) return erro(400, "JSON inválido.");
  if (e.name === "ConditionalCheckFailedException") return erro(404, naoEncontrado);
  console.error("Erro inesperado:", e);
  return erro(500, "Erro interno.");
};

module.exports = { resposta, erro, lerJson, validarProduto, tratarErro };
