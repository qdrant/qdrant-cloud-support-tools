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
    read -p "Enter the Kubernetes namespace of Qdrant Hybrid cloud: " namespace
fi;

# Check if the namespace exists
if ! kubectl get namespace "$namespace" &> /dev/null; then
    echo "Namespace $namespace does not exist. Please enter a valid namespace."
    exit 1
fi

# Ensure output directory exists
output_dir="hybrid-cloud-support-bundle-$(date +%Y%m%d%H%M%S)"
output_log="$output_dir/output.log"
mkdir -p "$output_dir"

exec 5> "$output_dir/trace.log"
BASH_XTRACEFD="5"
PS4='$LINENO: '
set -x

echo "Creating Hybrid Cloud support bundle for namespace ${namespace}"

echo ""
echo "Getting Kubernetes resources"

# Get all Qdrant related resources in the namespace into indivdual files
crds=("qdrantcluster.qdrant.io" "qdrantclustersnapshot.qdrant.io" "qdrantclusterscheduledsnapshot.qdrant.io" "qdrantclusterrestore.qdrant.io" "pod" "deployment.apps" "statefulset.apps" "service" "configmap" "ingress.networking.k8s.io" "node" "storageclass.storage.k8s.io" "helmrelease.cd.qdrant.io" "helmrepository.cd.qdrant.io" "helmchart.cd.qdrant.io" "networkpolicy.networking.k8s.io" "persistentvolumeclaim" "volumesnapshotclass.snapshot.storage.k8s.io" "volumesnapshot.snapshot.storage.k8s.io")

for crd in "${crds[@]}"; do
    mkdir -p "$output_dir/resources/$crd"
    kubectl -n "$namespace" get "$crd" -o wide 2>> "${output_log}" > "$output_dir/resources/list_$crd.yaml" || true
    echo -n '.'
    # if crd exists
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

    # port-forward
    kubectl -n "$namespace" port-forward "$pod" 6333:6333 &
    sleep 3
    pid=$!

    # authenticate if api key is set
    if [ -n "$api_key" ]; then
        args+=(-H "Authorization: Bearer $api_key")
    fi

    curl -v "${args[@]}" "$protocol://localhost:6333/telemetry?details_level=10" 2>> "${output_log}" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-telemetry.json"
    echo -n '.'
    curl -v "${args[@]}" "$protocol://localhost:6333/collections" 2>> "${output_log}" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-collections.json"
    echo -n '.'
    curl -v "${args[@]}" "$protocol://localhost:6333/cluster" 2>> "${output_log}" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-cluster.json"
    echo -n '.'
    collections=$(curl -v "${args[@]}" "$protocol://localhost:6333/collections" 2>> "${output_log}" | jq -r '.result.collections[] | .name')
    echo -n '.'
    for collection in $collections; do
        curl -v "${args[@]}" "$protocol://localhost:6333/collections/$collection" 2>> "${output_log}" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-collection-$collection.json"
        echo -n '.'
        curl -v "${args[@]}" "$protocol://localhost:6333/collections/$collection/cluster" 2>> "${output_log}" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-collection-$collection-cluster.json"
        echo -n '.'
    done

    set +x
    if [ -n "$api_key" ]; then
        # Escape special characters in the API key
        escaped_api_key=$(printf '%s\n' "$api_key" | sed 's/[]\/$*.^[]/\\&/g')
        sed -i -e "s|${escaped_api_key}|*****|g" "$output_dir/output.log"
        sed -i -e "s|${escaped_api_key}|*****|g" "$output_dir/trace.log"
    fi
    set -x

    kill $pid 2>> "${output_log}"
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
