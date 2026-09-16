#!/usr/bin/env bash

# check that bash is used
if [ -z "$BASH_VERSION" ]; then
    echo "This script must be run with bash"
    exit 1
fi

# check that bash version is 3 or higher
if [ "${BASH_VERSINFO[0]}" -lt 3 ]; then
    echo "This script requires bash version 3 or higher. You are running: ${BASH_VERSION}"
    exit 1
fi

cd $(dirname $0)

set -e
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

# Check if the required tools are installed
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed. Please install kubectl and try again."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install jq and try again."
    exit 1
fi

# Check if kubectl can access the Kubernetes cluster
if ! kubectl version &> /dev/null; then
    echo "kubectl cannot access the Kubernetes cluster. Please check your kubeconfig and try again."
    exit 1
fi

# Get the namespace from the user, if not passed as argument
namespace="$1"
if [ -z "$namespace" ]; then
    read -p "Enter the Kubernetes namespace of Qdrant Cloud: " namespace
fi;

cluster_id_filter=""
for arg in "${@:2}"; do
    if [[ "$arg" == --cluster-id=* ]]; then
        cluster_id_filter="${arg#--cluster-id=}"
    fi
done

# Check if the namespace exists
if ! kubectl get namespace "$namespace" &> /dev/null; then
    echo "Namespace $namespace does not exist. Please enter a valid namespace."
    exit 1
fi

# Ensure output directory exists
output_dir="qdrant-cloud-support-bundle-$(date +%Y%m%d%H%M%S)"
output_log="$output_dir/output.log"
mkdir -p "$output_dir"

exec 5> "$output_dir/trace.log"
BASH_XTRACEFD="5"
PS4='$LINENO: '
set -x

if [ -n "$cluster_id_filter" ]; then
    echo "Creating Qdrant Cloud support bundle for namespace ${namespace}, Qdrant cluster ${cluster_id_filter}"
else
    echo "Creating Qdrant Cloud support bundle for namespace ${namespace}"
fi

echo ""
echo "Getting Kubernetes resources"

# Infra-level resources - always fetch regardless of cluster filter
# Includes resources without cluster-id label (deployment.apps, service) so they are never empty when filtering
infra_crds=("storageclass.storage.k8s.io" "volumesnapshotclass.snapshot.storage.k8s.io" "helmrelease.cd.qdrant.io" "helmrepository.cd.qdrant.io" "helmchart.cd.qdrant.io" "deployment.apps" "service" "node" "pod" "configmap")

# Qdrant-cluster-scoped resources - filtered by cluster-id label if a filter is set
cluster_crds=("qdrantcluster.qdrant.io" "qdrantclustersnapshot.qdrant.io" "qdrantclusterscheduledsnapshot.qdrant.io" "qdrantclusterrestore.qdrant.io" "statefulset.apps" "ingress.networking.k8s.io" "networkpolicy.networking.k8s.io" "persistentvolumeclaim" "volumesnapshot.snapshot.storage.k8s.io" "poddisruptionbudget.policy")

label_selector_args=()
if [ -n "$cluster_id_filter" ]; then
    label_selector_args=(-l "cluster-id=$cluster_id_filter")
fi

for crd in "${infra_crds[@]}"; do
    mkdir -p "$output_dir/resources/$crd"
    kubectl -n "$namespace" get "$crd" -o wide 2>> "${output_log}" > "$output_dir/resources/list_$crd.yaml" || true
    echo -n '.'
    if kubectl get "$crd" &> /dev/null; then
        names=$(kubectl -n "$namespace" get "$crd" -o name)
        for name in $names; do
            kubectl -n "$namespace" get "$name" -o yaml 2>> "${output_log}" > "$output_dir/resources/$name.yaml" || true
            echo -n '.'
            kubectl -n "$namespace" describe "$name" 2>> "${output_log}" > "$output_dir/resources/$name.txt" || true
            echo -n '.'
        done
    fi
done

for crd in "${cluster_crds[@]}"; do
    mkdir -p "$output_dir/resources/$crd"
    kubectl -n "$namespace" get "$crd" "${label_selector_args[@]}" -o wide 2>> "${output_log}" > "$output_dir/resources/list_$crd.yaml" || true
    echo -n '.'
    if kubectl get "$crd" &> /dev/null; then
        names=$(kubectl -n "$namespace" get "$crd" "${label_selector_args[@]}" -o name)
        for name in $names; do
            kubectl -n "$namespace" get "$name" -o yaml 2>> "${output_log}" > "$output_dir/resources/$name.yaml" || true
            echo -n '.'
            kubectl -n "$namespace" describe "$name" 2>> "${output_log}" > "$output_dir/resources/$name.txt" || true
            echo -n '.'
        done
    fi
done

mkdir -p "$output_dir/resources/customresourcedefinitions"
for crd_name in $(kubectl get customresourcedefinitions -o name 2>> "${output_log}" | grep -E '(cd\.qdrant\.io|qdrant\.io)$'); do
    kubectl get "$crd_name" -o yaml 2>> "${output_log}" > "$output_dir/resources/customresourcedefinitions/$(basename "$crd_name").yaml" || true
    echo -n '.'
done

kubectl -n "$namespace" get secrets -l owner=helm --sort-by=.metadata.creationTimestamp 2>> "${output_log}" > "$output_dir/resources/helm_release_revisions.txt" || true

pods=$(kubectl -n "$namespace" get pods -o name 2>> "${output_log}" | cut -d '/' -f 2)

mkdir -p "$output_dir/logs"
mkdir -p "$output_dir/pod-resource-usage"

echo ""
echo "Getting logs of containers"

for pod in $pods; do
    # Get logs of all pods in the namespace
    kubectl -n "$namespace" logs "$pod" --all-containers 2>> "${output_log}" > "$output_dir/logs/$pod.log"
    echo -n '.'
    kubectl -n "$namespace" logs "$pod" --all-containers --previous 2>> "${output_log}" > "$output_dir/logs/$pod.previous.log" || true
    echo -n '.'

    # Get resource usage of all pods in the namespace
    kubectl -n "$namespace" top pod "$pod" > "$output_dir/pod-resource-usage/$pod.txt" 2>> "${output_log}" || true
done

echo ""
echo "Getting resource usage"

# Get resource usage of all nodes
mkdir -p "$output_dir/node-resource-usage"
nodes=$(kubectl get nodes -o name 2>> "${output_log}" | cut -d '/' -f 2)
for node in $nodes; do
    kubectl top node "$node" 2>> "${output_log}" > "$output_dir/node-resource-usage/$node.txt" || true
    echo -n '.'
done

echo ""
echo "Getting Qdrant telemetry"

# Get telemetry of Qdrant Pods
mkdir -p "$output_dir/qdrant-telemetry"
for pod in $(kubectl -n "$namespace" get pods -l app=qdrant -o name 2>> "${output_log}"); do
    pod_name=$(echo $pod | cut -d '/' -f 2)

    pod_status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>> "${output_log}")
    if [ "$pod_status" != "Running" ]; then
        echo ""
        echo "Skipping $pod_name as it is not running"
        echo ""
        continue
    fi

    cluster_id=$(kubectl -n "$namespace" get pod "$pod_name" -o jsonpath='{.metadata.labels.cluster-id}' 2>> "${output_log}")

    if [ -n "$cluster_id_filter" ] && [ "$cluster_id" != "$cluster_id_filter" ]; then
        continue
    fi

    cluster_name="qdrant-$cluster_id"

    # get secret reference from pod environment variable
    api_key_secret_name=$(kubectl -n "$namespace" get pod "$pod_name" -o jsonpath='{.spec.containers[0].env[?(@.name=="QDRANT__SERVICE__API_KEY")].valueFrom.secretKeyRef.name}' 2>> "${output_log}")
    echo -n '.'
    api_key_secret_key=$(kubectl -n "$namespace" get pod "$pod_name" -o jsonpath='{.spec.containers[0].env[?(@.name=="QDRANT__SERVICE__API_KEY")].valueFrom.secretKeyRef.key}' 2>> "${output_log}")
    echo -n '.'
    # get api key
    api_key=$(kubectl -n "$namespace" get secret "$api_key_secret_name" -o jsonpath="{.data.$api_key_secret_key}" 2>> "${output_log}" | base64 -d)
    echo -n '.'
    tls_active=$(kubectl -n "$namespace" get configmap "$cluster_name" -o jsonpath='{.data.production\.yaml}' 2>> "${output_log}")
    echo -n '.'

    args=()

    protocol="http"
    if [[ "$tls_active" =~ "enable_tls: true" ]]; then
        protocol="https"
        args+=(-k)
    fi

    # port-forward using a free ephemeral port to avoid cross-pod contamination
    local_port=$(python3 -c "import socket; s=socket.socket(); s.bind(('', 0)); print(s.getsockname()[1]); s.close()" 2>/dev/null || echo 6333)
    kubectl -n "$namespace" port-forward "$pod" "${local_port}:6333" &
    pid=$!
    if ! curl -sf --retry 15 --retry-delay 1 --retry-connrefused \
            --max-time 2 "${args[@]}" "$protocol://localhost:${local_port}/healthz" 2>/dev/null; then
        echo ""
        echo "Port-forward did not become ready for $pod_name, skipping"
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        continue
    fi

    # authenticate if api key is set
    if [ -n "$api_key" ]; then
        args+=(-H "Authorization: Bearer $api_key")
    fi

    # the healthz check above proves the tunnel worked for one connection, but
    # kubectl port-forward has been observed to refuse the *next* new local
    # connection right after (especially across kubectl/API-server version
    # skew) even though the pod itself is healthy. Retry each pull on
    # connection-refused so a dropped tunnel self-heals instead of silently
    # producing an empty file.
    curl_retry_opts=(--retry 5 --retry-delay 1 --retry-connrefused --max-time 30)

    empty_file_check() {
        if [ ! -s "$1" ]; then
            echo ""
            echo "WARNING: $(basename "$1") is empty - the port-forward tunnel to $pod_name likely dropped mid-collection. See ${output_log} for details."
        fi
    }

    # use curl's own -o, not shell > / a pipe to jq, so curl owns the file
    # across retries.
    telemetry_file="$output_dir/qdrant-telemetry/$(basename $pod)-telemetry.json"
    collections_file="$output_dir/qdrant-telemetry/$(basename $pod)-collections.json"
    cluster_file="$output_dir/qdrant-telemetry/$(basename $pod)-cluster.json"
    slow_requests_file="$output_dir/qdrant-telemetry/$(basename $pod)-slow-requests.json"
    pod_files=("$telemetry_file" "$collections_file" "$cluster_file" "$slow_requests_file")

    set +e
    curl -v "${curl_retry_opts[@]}" "${args[@]}" -o "$telemetry_file" "$protocol://localhost:${local_port}/telemetry?details_level=10" 2>> "${output_log}"
    echo -n '.'
    curl -v "${curl_retry_opts[@]}" "${args[@]}" -o "$collections_file" "$protocol://localhost:${local_port}/collections" 2>> "${output_log}"
    echo -n '.'
    curl -v "${curl_retry_opts[@]}" "${args[@]}" -o "$cluster_file" "$protocol://localhost:${local_port}/cluster" 2>> "${output_log}"
    echo -n '.'
    curl -v "${curl_retry_opts[@]}" "${args[@]}" -o "$slow_requests_file" "$protocol://localhost:${local_port}/profiler/slow_requests" 2>> "${output_log}"
    echo -n '.'

    collections=$(jq -r '.result.collections[] | .name' "$collections_file" 2>> "${output_log}")
    for collection in $collections; do
        collection_file="$output_dir/qdrant-telemetry/$(basename $pod)-collection-$collection.json"
        collection_cluster_file="$output_dir/qdrant-telemetry/$(basename $pod)-collection-$collection-cluster.json"
        collection_optimizations_file="$output_dir/qdrant-telemetry/$(basename $pod)-collection-$collection-optimizations.json"
        collection_memory_file="$output_dir/qdrant-telemetry/$(basename $pod)-collection-$collection-memory.json"
        pod_files+=("$collection_file" "$collection_cluster_file" "$collection_optimizations_file" "$collection_memory_file")

        curl -v "${curl_retry_opts[@]}" "${args[@]}" -o "$collection_file" "$protocol://localhost:${local_port}/collections/$collection" 2>> "${output_log}"
        echo -n '.'
        curl -v "${curl_retry_opts[@]}" "${args[@]}" -o "$collection_cluster_file" "$protocol://localhost:${local_port}/collections/$collection/cluster" 2>> "${output_log}"
        echo -n '.'
        curl -v "${curl_retry_opts[@]}" "${args[@]}" -o "$collection_optimizations_file" "$protocol://localhost:${local_port}/collections/$collection/optimizations" 2>> "${output_log}"
        echo -n '.'
        curl -v "${curl_retry_opts[@]}" "${args[@]}" -o "$collection_memory_file" "$protocol://localhost:${local_port}/collections/$collection/memory" 2>> "${output_log}"
        echo -n '.'
    done

    for f in "${pod_files[@]}"; do
        empty_file_check "$f"
    done
    set -e

    set +x
    if [ -n "$api_key" ]; then
        # Escape special characters in the API key
        escaped_api_key=$(printf '%s\n' "$api_key" | sed 's/[]\/$*.^[]/\\&/g')

        # Process each file with sed and save to a temp file then move it back
        for file in "$output_dir/output.log" "$output_dir/trace.log"; do
            sed "s|${escaped_api_key}|***|g" "$file" > "${file}.tmp"
            mv "${file}.tmp" "$file"
        done
    fi
    set -x

    kill "$pid" 2>> "${output_log}" || true
    wait "$pid" 2>/dev/null || true
done

echo ""
echo "Getting Kubernetes version"
# Get kubernetes version
kubectl version > "$output_dir/kubernetes-version.txt"

echo ""
echo "Creating archive"

# Create a tarball of the output directory
tar -czf "$output_dir.tar.gz" "$output_dir"

echo ""
echo "Support bundle is saved in $output_dir.tar.gz"

# Remove the output directory
rm -rf "$output_dir"
