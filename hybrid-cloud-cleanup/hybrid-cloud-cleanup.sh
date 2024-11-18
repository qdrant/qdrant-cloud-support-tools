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
namespace="$1"
if [ -z "$namespace" ]; then
    read -p "Enter the Kubernetes namespace of Qdrant Hybrid cloud: " namespace
fi;

# Check if the namespace exists
if ! kubectl get namespace "$namespace" &> /dev/null; then
    echo "Namespace $namespace does not exist. Please enter a valid namespace."
    exit 1
fi

helm -n "$namespace" delete qdrant-cloud-agent || true
helm -n "$namespace" delete qdrant-prometheus || true
helm -n "$namespace" delete qdrant-operator || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-cloud-agent -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-prometheus -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-operator -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRelease.cd.qdrant.io qdrant-node-exporter -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-cloud-agent" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-prometheus" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-operator" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmChart.cd.qdrant.io "$namespace-qdrant-node-exporter" -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl -n "$namespace" patch HelmRepository.cd.qdrant.io qdrant-cloud -p '{"metadata":{"finalizers":null}}' --type=merge || true
kubectl delete namespace "$namespace" || true
kubectl get crd -o name | grep qdrant | xargs -n 1 kubectl delete