#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=qdrant
JOB=support-bundle-job
LABEL=app=support-bundle
BUNDLE=qdrant-cloud-support-bundle.tar.gz

# Delete any previous job
kubectl delete job $JOB -n $NAMESPACE --ignore-not-found

# Launch the job
kubectl apply -f support-bundle-job.yaml

# Wait until the pod is Running
kubectl wait pod -l $LABEL -n $NAMESPACE --for=condition=Ready --timeout=600s
POD=$(kubectl get pods -l $LABEL -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
echo "Found running pod: $POD"

# Wait for the archive file to appear inside the container
echo "Waiting for bundle to be generated inside container..."
until kubectl exec -n $NAMESPACE $POD -c bundle -- test -f /app/$BUNDLE; do
  echo "  bundle not yet present, sleeping 5s..."
  sleep 5
done
echo "Bundle found!"

# Copy the bundle out
echo "Copying /app/$BUNDLE from $POD..."
kubectl cp $NAMESPACE/$POD:/app/$BUNDLE ./$BUNDLE -c bundle
echo "Bundle saved locally as ./$BUNDLE"

# Now you can delete the job
# kubectl delete job $JOB -n $NAMESPACE