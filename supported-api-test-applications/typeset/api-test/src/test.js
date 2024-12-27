"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var js_client_rest_1 = require("@qdrant/js-client-rest");
var host = process.env.HOST;
var url = "https://".concat(host, ":6333");
var api_key = process.env.API_KEY;
// connect to Qdrant Cloud
var client = new js_client_rest_1.QdrantClient({
    url: url,
    apiKey: api_key,
});
var result = await client.getCollections();
console.log('List of collections:', result.collections);
