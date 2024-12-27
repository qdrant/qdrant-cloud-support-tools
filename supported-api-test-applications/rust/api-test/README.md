```
$ cargo add qdrant_client
$ cargo add tokio
$ cargo add tokio-test
$ cargo run
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.07s
     Running `target/debug/api-test`
url     => https://*******************************************************************:6334
api_key => ******************************************************
Ok(
    SearchResponse {
        result: [
            ScoredPoint {
                id: Some(
                    PointId {
                        point_id_options: Some(
                            Num(
                                2,
                            ),
                        ),
                    },
                ),
                payload: {
                    "color": Value {
                        kind: Some(
                            BoolValue(
                                true,
                            ),
                        ),
                    },
                    "rand_number": Value {
                        kind: Some(
                            IntegerValue(
                                32,
                            ),
                        ),
                    },
                    "extra_field": Value {
                        kind: Some(
                            BoolValue(
                                true,
                            ),
                        ),
                    },
                },
                score: 0.93255514,
                version: 1,
                vectors: None,
                shard_key: None,
                order_value: None,
            },
            ScoredPoint {
                id: Some(
                    PointId {
                        point_id_options: Some(
                            Num(
                                1,
                            ),
                        ),
                    },
                ),
                payload: {
                    "color": Value {
                        kind: Some(
                            BoolValue(
                                true,
                            ),
                        ),
                    },
                    "rand_number": Value {
                        kind: Some(
                            IntegerValue(
                                32,
                            ),
                        ),
                    },
                },
                score: 0.6322232,
                version: 1,
                vectors: None,
                shard_key: None,
                order_value: None,
            },
        ],
        time: 0.000597056,
    },
)
```
