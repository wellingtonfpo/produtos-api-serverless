const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient } = require("@aws-sdk/lib-dynamodb");

// Criado fora do handler: é reaproveitado entre invocações "quentes" da Lambda.
const doc = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

module.exports = { doc, TABLE: process.env.TABLE_NAME };
