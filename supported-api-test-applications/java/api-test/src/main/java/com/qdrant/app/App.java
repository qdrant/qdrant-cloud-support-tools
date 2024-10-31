package com.qdrant.app;

import java.util.concurrent.ExecutionException;
import java.util.concurrent.Future;

import com.google.common.util.concurrent.FutureCallback;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;

import io.qdrant.client.QdrantClient;
import io.qdrant.client.QdrantGrpcClient;
import io.qdrant.client.grpc.Collections.Distance;
import io.qdrant.client.grpc.Collections.VectorParams;

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
        int size = 128;
        
        // Create a new client to connect to the Qdrant Managed Cloud
        try (QdrantClient client = 
            new QdrantClient(QdrantGrpcClient
            .newBuilder(host)
            .withApiKey(apiKey)
            .build())) {

            ListenableFuture<Boolean> exists = client.collectionExistsAsync(collectionName);

            /*
            Futures.addCallback(
                exists,
                new FutureCallback<Boolean>() {
                    public void onSuccess(Boolean exists) {
                        if (!exists) {
                            try {client.createCollectionAsync(
                                collectionName,
                                VectorParams.newBuilder()
                                    .setDistance(Distance.Cosine)
                                    .setSize(size)
                                    .build())
                                .get();
                            } catch (InterruptedException e) {
                                e.printStackTrace();
                            } catch (ExecutionException e) {
                                e.printStackTrace();
                            }
                        }
                    }
                    public void onFailure(Throwable thrown) {
                        thrown.printStackTrace();
                    }
                },
                client);
                */
        }
    }
}
    