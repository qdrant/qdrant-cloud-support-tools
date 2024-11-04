package com.qdrant.app;

// import static convenience methods
import static io.qdrant.client.PointIdFactory.id;
import static io.qdrant.client.ValueFactory.value;
import static io.qdrant.client.VectorsFactory.vectors;

import java.util.List;
import java.util.Map;

import io.qdrant.client.QdrantClient;
import io.qdrant.client.QdrantGrpcClient;
import io.qdrant.client.grpc.Collections.Distance;
import io.qdrant.client.grpc.Collections.VectorParams;
import io.qdrant.client.grpc.Points.PointStruct;
import io.qdrant.client.grpc.Points.ScoredPoint;
import io.qdrant.client.grpc.Points.SearchPoints;

/**
 * Qdrant Cloud Support Tools: Java API test
 */
public class App {
    /**
     * @param args
     */
    public static void main(String[] args) {

        String host = System.getenv("HOST");
        String apiKey = System.getenv("API_KEY");
        // Collection parameters
        String collectionName = "dominic_java_test_collection_1";
        int size = 4;
        
        // Create a new client to connect to the Qdrant Managed Cloud
        try (QdrantClient client = 
            new QdrantClient(QdrantGrpcClient
            .newBuilder(host)
            .withApiKey(apiKey)
            .build())) {

            try {
                client.createCollectionAsync(
                collectionName,
                VectorParams.newBuilder()
                    .setDistance(Distance.Cosine)
                    .setSize(size)
                    .build())
                .get();
            }
            catch (java.util.concurrent.ExecutionException e){
                System.out.printf("%s\n",e.toString());
            }
    
            Thread.sleep(1000);
    
            List<PointStruct> points =
                List.of(
                    PointStruct.newBuilder()
                        .setId(id(1))
                        .setVectors(vectors(0.32f, 0.52f, 0.21f, 0.52f))
                        .putAllPayload(
                            Map.of(
                                "color", value("red"),
                                "rand_number", value(32)))
                        .build(),
                    PointStruct.newBuilder()
                        .setId(id(2))
                        .setVectors(vectors(1.42f, 0.52f, 0.67f, 0.632f))
                        .putAllPayload(
                            Map.of(
                                "color", value("black"),
                                "rand_number", value(53),
                                "extra_field", value(true)))
                        .build());
            
            client.upsertAsync(collectionName, points).get();

            List<ScoredPoint> hits = client.searchAsync(
                SearchPoints.newBuilder()
                    .setCollectionName(collectionName)
                    .addAllVector(List.of(0.6235f, 0.123f, 0.532f, 0.123f))
                    .setLimit(5)
                    .build())
            .get();

            hits.forEach(e -> System.out.println(e.toString()));
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
    