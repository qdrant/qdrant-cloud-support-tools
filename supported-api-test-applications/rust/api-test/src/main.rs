use std::env;
//use futures::executor::block_on;
use qdrant_client::{Qdrant, QdrantError};
use qdrant_client::qdrant::{CreateCollectionBuilder, 
    Distance, 
    VectorParamsBuilder, 
    PointStruct, 
    UpsertPointsBuilder, 
    SearchPointsBuilder,
    SearchResponse};

#[tokio::main] 
async fn main() {
    let host = env::var("HOST").expect("HOST not set");
    let url: String = format!("https://{}:6334", host);
    let api_key = env::var("API_KEY").expect("API_KEY not set");
    let collection_name = "dominic_rust_test_collection_1";
    let size = 4;

    println!("url     => {}",url);
    println!("api_key => {}",api_key);

    let client = Qdrant::from_url(&url).api_key(api_key).build().unwrap();

    // Create collection
    let _collection_response = client
        .create_collection(
            CreateCollectionBuilder::new(collection_name)
             .vectors_config(VectorParamsBuilder::new(size, Distance::Cosine)),
        ).await;

    let points = vec![
        PointStruct::new(1,
            vec![0.32, 0.52, 0.21, 0.52],
            [
                ("color", true.into()),
                ("rand_number", 32.into()),
            ],
        )
        ,
        PointStruct::new(2,
            vec![1.42, 0.52, 0.67, 0.632],
            [
                ("color", true.into()),
                ("rand_number", 32.into()),
                ("extra_field", true.into()),
            ]
        )
        ];

    let _upsert_response = client
        .upsert_points(UpsertPointsBuilder::new(collection_name, points)).await;

    let search_request = SearchPointsBuilder::new(
        collection_name,
        vec![0.6235, 0.123, 0.532, 0.123], // Search vector
        5, // Search limit, number of results to return
    ).with_payload(true);

    let search_response: Result<SearchResponse, QdrantError> = client.search_points(search_request).await;
    println!("{:#?}", search_response);
}
