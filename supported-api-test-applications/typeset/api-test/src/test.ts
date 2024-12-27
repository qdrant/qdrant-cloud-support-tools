import {QdrantClient} from '@qdrant/js-client-rest'

const host = process.env.HOST
const url = `https://${host}:6333`
const apiKey = process.env.API_KEY
const collectionName = "dominic_node_test_collection_1"
console.log(`url:    ${url}`)
console.log(`apiKey: ${apiKey}`)

async function main() {
    // connect to Qdrant Cloud
    const client = new QdrantClient({
        url: url,
        apiKey: apiKey,
    })

    // check for collection
    const response = await client.getCollections()

    const collectionNames = response.collections.map((collection) => collection.name)

    if (collectionNames.includes(collectionName)) {
        await client.deleteCollection(collectionName)
    }

    // (re-)create collection
    await client.createCollection(collectionName, {
        vectors: {
            size: 4,
            distance: 'Cosine',
        },
        optimizers_config: {
            default_segment_number: 2,
        },
        replication_factor: 1,
    })

    // index
    await client.upsert(collectionName, {
        wait: true,
        points: [
            {
                id: 1,
                vector: [0.32, 0.52, 0.21, 0.52],
                payload: {
                    color: 'red',
                    rand_number: 32,
                },
            },
            {
                id: 2,
                vector: [1.42, 0.52, 0.67, 0.632],
                payload: {
                    color: 'blue',
                    rand_number: 32,
                    extra_field: true,
                },
            },
        ]
    })

    // search
    const queryVector = [0.6235, 0.123, 0.532, 0.123];

    const res1 = await client.search(collectionName, {
        vector: queryVector,
        limit: 3,
    });

    console.log('search result: ', res1);
}

main()
    .then((code) => {
        process.exit();
    })
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });