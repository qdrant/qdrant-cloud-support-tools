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

# Check if the required tools are installed
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed. Please install kubectl and try again."
    exit 1
fi

# Check if kubectl can access the Kubernetes cluster
if ! kubectl version &> /dev/null; then
    echo "kubectl cannot access the Kubernetes cluster. Please check your kubeconfig and try again."
    exit 1
fi
if ! command -v helm &> /dev/null; then
    echo "helm is not installed. Please install helm and try again."
    exit 1
fi

# Get the namespace from the user, if not passed as argument
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <namespace> [-force]"
    exit 1
fi
namespace="$1"

# Check if the namespace exists
if ! kubectl get namespace "$namespace" &> /dev/null; then
    echo "Namespace $namespace does not exist. Please provide a valid namespace."
    exit 1
fi

# Warning
echo "==================== WARNING ====================="
echo "THIS WILL DELETE ALL RESOURCES CREATED BY QDRANT"
echo "MAKE SURE YOU HAVE CREATED AND TESTED YOUR BACKUPS"
echo "THIS IS A NON REVERSIBLE ACTION"
echo "==================== WARNING ====================="
echo "Showing configuration info to double check you are executing on the correct cluster:"
echo "kubectl context: $(kubectl config current-context)"
kubectl version | grep Server
echo "Waiting 20 seconds to allow to cancel"
sleep 20

# Check if QdrantCluster resources are still present
if [ -n "$(kubectl -n $namespace get qdrantclusters.qdrant.io 2>/dev/null)" ]  && [ "$2" != "-force" ]; then
    echo "QdrantCluster resources still found in this cluster, see below"
    echo "====="
    kubectl -n "$namespace" get qdrantclusters.qdrant.io
    echo "====="
    echo "We advise to double check that you want to remove these,"
    echo "as it is unexpected to still have QdrantCluster resources present"
    echo "It is strongly recommended to delete all Qdrant clusters from the Hybrid Cloud Environment before proceeding"
    echo "If you are sure you still want to run this script, add -force parameter to the command"
    echo "Example: $0 $1 -force"
    exit 1
fi

helm -n "$namespace" delete qdrant-cloud-agent || true
helm -n "$namespace" delete qdrant-prometheus || true
helm -n "$namespace" delete qdrant-operator || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-cloud-agent -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-prometheus -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-operator-v2 -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-cluster-manager -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-node-exporter -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-cluster-exporter -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-kubernetes-event-exporter -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-cloud-agent" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-prometheus" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-operator-v2" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-cluster-manager" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-node-exporter" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-cluster-exporter" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-kubernetes-event-exporter" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRepository.cd.qdrant.io qdrant-cloud -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl delete namespace "$namespace" || true
kubectl get crd -o name | grep qdrant | xargs -n 1 kubectl delete
