package main

import (
	"context"
	"fmt"
	"log"

	"github.com/qdrant/go-client/qdrant"
)

func main() {
	// Create a new client to connect to the Qdrant Managed Cloud
	client, err := qdrant.NewClient(&qdrant.Config{
		Host:   "9ed46f5d-49d2-4339-89c1-08e2b4c79cf7.us-east4-0.gcp.cloud.qdrant.io", // Replace with your Qdrant instance host
		Port:   6334,
		APIKey: "dUAFamvvSCP1AcuGdRaq5o8ujE7vBd496_Be24iF2Q-EtRWe1Pv7IQ", // Replace with your API key
		UseTLS: true,
	})

	if err != nil {
		log.Fatalf("Failed to create Qdrant client: %v", err)
	}

	// Collection parameters
	collectionName := "joey_go_test_collection_1"

	// Create a new collection in Qdrant
	err = createCollection(client, collectionName)
	if err != nil {
		log.Fatalf("Failed to create collection: %v", err)
	}

	fmt.Println("Collection created successfully!")
}

// createCollection creates a collection in Qdrant Managed Cloud
func createCollection(client *qdrant.Client, collectionName string) error {
	// Define the collection configuration
	createCollectionParams := &qdrant.CreateCollection{
		CollectionName: collectionName,
		VectorsConfig: qdrant.NewVectorsConfig(&qdrant.VectorParams{
			Size:     128,                    // Vector dimensionality
			Distance: qdrant.Distance_Cosine, // Cosine similarity metric
		}),
	}

	// Call CreateCollection to create the collection
	err := client.CreateCollection(context.Background(), createCollectionParams)
	if err != nil {
		return fmt.Errorf("failed to create collection: %w", err)
	}

	return nil
}
