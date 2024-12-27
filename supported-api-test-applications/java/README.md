# Setup
Please set the following environment variables to ensure the `com.qdrant.app.App` application can connect to your Qdrant Cloud cluster

API_KEY="******************************************************"

HOST="************************************.**********.***.cloud.qdrant.io"

```
$  /usr/bin/env /usr/lib/jvm/java-17-openjdk-amd64/bin/java @/tmp/cp_565r4oetde0ykqed24lyp6e5f.argfile com.qdrant.app.App 
SLF4J(W): No SLF4J providers were found.
SLF4J(W): Defaulting to no-operation (NOP) logger implementation
SLF4J(W): See https://www.slf4j.org/codes.html#noProviders for further details.
17:52:26.610 [main] INFO  com.qdrant.app.App - java.util.concurrent.ExecutionException: io.grpc.StatusRuntimeException: ALREADY_EXISTS: Wrong input: Collection `dominic_java_test_collection_1` already exists!

17:52:28.206 [main] INFO  com.qdrant.app.App - id {
  num: 2
}
score: 0.93255514
version: 1

17:52:28.207 [main] INFO  com.qdrant.app.App - id {
  num: 1
}
score: 0.6322232
version: 1
```
