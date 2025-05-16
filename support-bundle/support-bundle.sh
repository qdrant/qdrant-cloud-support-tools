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

# Check if Python 3 is installed
if ! command -v python3 &>/dev/null; then
    echo "python3 is not installed. Please install Python 3.8 or higher and try again."
    exit 1
fi

# Check Python version
PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
REQ="3.8"
# Compare versions
if [ "$(printf '%s\n' "$REQ" "$PYVER" | sort -V | head -n1)" != "$REQ" ]; then
    echo "Python version must be >= $REQ. Found $PYVER"
    exit 1
fi

# Check if the required Python modules are installed
if ! python3 - <<'PYCODE' 2>/dev/null
import requests
PYCODE
then
    echo "Python module 'requests' is missing. Install with: pip3 install requests"
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

echo "Creating Qdrant Cloud support bundle for namespace ${namespace}"

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
echo "Running imbalance analysis"

# Get the cluster ID from the first pod in the namespace
cluster_id=$(kubectl -n "$namespace" get pods -o jsonpath='{.items[0].metadata.labels.cluster-id}' 2>> "${output_log}")

if [ -z "$cluster_id" ]; then
    echo "Error: Unable to determine cluster ID. Ensure that pods in the namespace have the 'cluster-id' label."
    exit 1
fi

echo "Detected cluster ID: $cluster_id"

# Run Python script for telemetry and imbalance analysis
script_dir=$(cd "$(dirname "$0")" && pwd)
python "$script_dir/imbalance/cli.py" --namespace "$namespace" --output-dir "$output_dir" >> "$output_dir/imbalance-report.txt" 2>&1
#python "$script_dir/imbalance/cli.py" --namespace "$namespace" --output-dir "$output_dir" 2>&1 | tee "$output_dir/imbalance-report.txt"

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
#rm -rf "$output_dir"