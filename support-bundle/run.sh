#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=qdrant
JOB=support-bundle-job
BUNDLE=qdrant-cloud-support-bundle.tar.gz
LABEL=app=support-bundle


kubectl delete job $JOB -n $NAMESPACE --ignore-not-found


kubectl apply -f support-bundle-job.yaml

# Wait for the pod to be Running
kubectl wait pod -l $LABEL -n $NAMESPACE --for=condition=Ready --timeout=120s

POD=$(kubectl get pods -l $LABEL -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
echo "Found running pod: $POD"

# Copy the bundle
kubectl cp $NAMESPACE/$POD:/app/$BUNDLE ./$BUNDLE -c bundle
echo "Bundle saved locally: ./$BUNDLE"

# Clean up the job
#kubectl delete job support-bundle-job -n qdrant
#kubectl delete job $JOB -n $NAMESPACE
