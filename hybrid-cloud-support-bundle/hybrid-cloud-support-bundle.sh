#!/usr/bin/env bash

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
mkdir -p "$output_dir"

# Testing connectivity
kubectl -n $namespace apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: overlaytest
spec:
  selector:
      matchLabels:
        name: overlaytest
  template:
    metadata:
      labels:
        name: overlaytest
    spec:
      tolerations:
      - operator: Exists
      containers:
      - image: registry.cloud.qdrant.io/library/qdrant-debug
        imagePullPolicy: Always
        name: overlaytest
        command: ["sh", "-c", "tail -f /dev/null"]
        terminationMessagePath: /dev/termination-log
      terminationGracePeriodSeconds: 1
EOF

kubectl rollout status daemonset overlaytest -n $namespace

mkdir -p "$output_dir/overlaytest"

echo "=> Start network overlay test" > "$output_dir/overlaytest/overlaytest.log"
  kubectl get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.nodeName}{"\n"}{end}' |
  while read spod shost
    do kubectl get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.status.podIP}{" "}{@.spec.nodeName}{"\n"}{end}' |
    while read tip thost
      do kubectl --request-timeout='10s' exec $spod -c overlaytest -- /bin/sh -c "ping -c2 $tip > /dev/null 2>&1"
        RC=$?
        if [ $RC -ne 0 ]
          then echo FAIL: $spod on $shost cannot reach pod IP $tip on $thost >> "$output_dir/overlaytest/overlaytest.log"
          else echo $shost can reach $thost >> "$output_dir/overlaytest/overlaytest.log"
        fi
    done
  done
echo "=> End network overlay test" >> "$output_dir/overlaytest/overlaytest.log"

kubectl delete daemonset overlaytest -n $namespace
exit 1
# Get all Qdrant related resources in the namespace into indivdual files
crds=("qdrantcluster.qdrant.io" "qdrantclustersnapshot.qdrant.io" "qdrantclusterscheduledsnapshot.qdrant.io" "qdrantclusterrestore.qdrant.io" "pod" "deployment.apps" "statefulset.apps" "service" "configmap" "ingress.networking.k8s.io" "node" "storageclass.storage.k8s.io" "helmrelease.cd.qdrant.io" "helmrepository.cd.qdrant.io" "helmchart.cd.qdrant.io" "networkpolicy.networking.k8s.io" "persistentvolumeclaim" "volumesnapshotclass.snapshot.storage.k8s.io" "volumesnapshot.snapshot.storage.k8s.io")

for crd in "${crds[@]}"; do
    mkdir -p "$output_dir/resources/$crd"
    kubectl -n "$namespace" get "$crd" -o name | tr '\n' '\0' | xargs -S1024 -0 -n1 -I {} sh -c "kubectl -n $namespace get {} -o yaml > $output_dir/resources/{}.yaml || true"
    echo -n '.'
    kubectl -n "$namespace" get "$crd" -o name | tr '\n' '\0' | xargs -S1024 -0 -n1 -I {} sh -c "kubectl -n $namespace describe {} > $output_dir/resources/{}.txt || true"
    echo -n '.'
done

# Get logs of all pods in the namespace
mkdir -p "$output_dir/logs"
kubectl -n "$namespace" get pods -o name | cut -d '/' -f 2 | tr '\n' '\0' | xargs -S1024 -0 -n1 -I {} sh -c "kubectl -n $namespace logs {} --all-containers > $output_dir/logs/{}.log"
echo -n '.'
kubectl -n "$namespace" get pods -o name | cut -d '/' -f 2 | tr '\n' '\0' | xargs -S1024 -0 -n1 -I {} sh -c "kubectl -n $namespace logs {} --all-containers --previous > $output_dir/logs/{}.previous.log || true"
echo -n '.'

# Get resource usage of all pods in the namespace
mkdir -p "$output_dir/pod-resource-usage"
kubectl -n "$namespace" get pods -o name | cut -d '/' -f 2 | tr '\n' '\0' | xargs -S1024 -0 -n1 -I {} sh -c "kubectl -n $namespace top pod {} > $output_dir/pod-resource-usage/{}.txt || true"
echo -n '.'

# Get resource usage of all nodes
mkdir -p "$output_dir/node-resource-usage"
kubectl get nodes -o name | cut -d '/' -f 2 | tr '\n' '\0' | xargs -S1024 -0 -n1 -I {} sh -c "kubectl top node {} > $output_dir/node-resource-usage/{}.txt || true"
echo -n '.'

# Get telemetry of Qdrant Pods
mkdir -p "$output_dir/qdrant-telemetry"
for pod in $(kubectl -n "$namespace" get pods -l app=qdrant -o name); do
    pod_name=$(echo $pod | cut -d '/' -f 2)
    cluster_id=$(kubectl -n "$namespace" get pod "$pod_name" -o jsonpath='{.metadata.labels.cluster-id}')
    cluster_name="qdrant-$cluster_id"

    # get secret reference from pod environment variable
    api_key_secret_name=$(kubectl -n "$namespace" get pod "$pod_name" -o jsonpath='{.spec.containers[0].env[?(@.name=="QDRANT__SERVICE__API_KEY")].valueFrom.secretKeyRef.name}')
    echo -n '.'
    api_key_secret_key=$(kubectl -n "$namespace" get pod "$pod_name" -o jsonpath='{.spec.containers[0].env[?(@.name=="QDRANT__SERVICE__API_KEY")].valueFrom.secretKeyRef.key}')
    echo -n '.'
    # get api key
    api_key=$(kubectl -n "$namespace" get secret "$api_key_secret_name" -o jsonpath="{.data.$api_key_secret_key}" | base64 -d)
    echo -n '.'
    tls_active=$(kubectl -n "$namespace" get configmap "$cluster_name" -o jsonpath='{.data.production\.yaml}')
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

    curl "${args[@]}" "$protocol://localhost:6333/telemetry" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-telemetry.json"
    echo -n '.'
    curl "${args[@]}" "$protocol://localhost:6333/collections" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-collections.json"
    echo -n '.'
    curl "${args[@]}" "$protocol://localhost:6333/cluster" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-cluster.json"
    echo -n '.'
    collections=$(curl "${args[@]}" "$protocol://localhost:6333/collections" | jq -r '.result.collections[] | .name')
    echo -n '.'
    for collection in $collections; do
        curl "${args[@]}" "$protocol://localhost:6333/collections/$collection" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-collection-$collection.json"
        echo -n '.'
        curl "${args[@]}" "$protocol://localhost:6333/collections/$collection/cluster" | jq '.' > "$output_dir/qdrant-telemetry/$(basename $pod)-collection-$collection-cluster.json"
        echo -n '.'
    done

    kill $pid
done

# Get kubernetes version
kubectl version > "$output_dir/kubernetes-version.txt"

# Create a tarball of the output directory
tar -czf "$output_dir.tar.gz" "$output_dir"

echo ""
echo "Support bundle is saved in $output_dir.tar.gz"

# Remove the output directory
rm -rf "$output_dir"

