#!/usr/bin/env bash

cd $(dirname $0)

set -e

if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed. Please install kubectl and try again."
    exit 1
fi

echo "kubectl is installed"

if ! command -v helm &> /dev/null; then
    echo "helm is not installed. Please install helm and try again."
    exit 1
fi

echo "helm is installed"
echo ""

echo "The current Kubernetes cluster is: $(kubectl config current-context)"
echo ""

echo "The following storage classes are available:"

kubectl get storageclasses.storage.k8s.io

echo ""

# get default storage class
default_storage_class=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

if [ -z "$default_storage_class" ]; then
    echo "No default storage class is set. You will need to specifiy one when creating the Hybrid Cloud environment."
else
    echo "The default storage class is: $default_storage_class. If you want to use another one, you can specify it when creating the Hybrid Cloud environment."
fi

echo ""

echo "Testing if the storage classes provide block storage. Only storage classes with block storage are supported by Qdrant."
echo ""

storage_classes=$(kubectl get storageclass -o jsonpath='{.items[*].metadata.name}')

for storage_class in $storage_classes; do
    echo "Testing storage class $storage_class..."
    # Temporary PVC and Pod names
    PVC_NAME="qdrant-test-pvc-check"
    POD_NAME="qdrant-test-pvc-check"

    # YAML for the PersistentVolumeClaim
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: $storage_class
EOF

    # YAML for the Pod to test block storage
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
spec:
  terminationGracePeriodSeconds: 0
  containers:
  - name: test-container
    image: busybox
    command: ["/bin/sh", "-c", "sleep 3600"]
    volumeMounts:
    - mountPath: /volume
      name: test-volume
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: $PVC_NAME
  restartPolicy: Never
EOF

    # Wait for the Pod to be running
    echo "Waiting for Pod to be running..."
    kubectl wait --for=condition=Ready pod/$POD_NAME --timeout=120s

    # Verify if the volume is a block device inside the pod
    echo "Checking if the volume is a block device..."
    if kubectl exec -it $POD_NAME -- df -TP /volume | grep -q "ext4"; then
        echo "Storage class $storage_class provides block storage with an ext4 fileystem."
    elif kubectl exec -it $POD_NAME -- df -TP /volume | grep -q "xfs"; then
        echo "Storage class $storage_class provides block storage with an xfs fileystem."
    elif kubectl exec -it $POD_NAME -- df -TP /volume | grep -q "btrfs"; then
        echo "Storage class $storage_class provides block storage with a btrfs fileystem."
    else
        echo "Storage class $storage_class does provide a potentially unsupported filesystem:"
        kubectl exec -it $POD_NAME -- df -TP /volume
    fi

    # Clean up the resources
    kubectl delete pod $POD_NAME
    kubectl delete pvc $PVC_NAME
done

echo ""

# get storage classes that allow volume expansion
expandable_storage_classes=$(kubectl get storageclass -o jsonpath='{.items[?(@.allowVolumeExpansion==true)].metadata.name}')

if [ -z "$expandable_storage_classes" ]; then
    echo "None of your storage classes allow volume expansion. You will not be able to vertically scale your Qdrant Clusters."
else
    echo "The following storage classes allow volume expansion: $expandable_storage_classes. You will only be able to vertically scale your Qdrant Clusters using one of those storage classes."
fi

# check if volumesnapshot class crd exits
if kubectl get volumesnapshotclasses.snapshot.storage.k8s.io &> /dev/null; then
    echo ""
    echo "The following volume snapshot classes are available:"
    kubectl get volumesnapshotclasses.snapshot.storage.k8s.io
    echo ""
    echo "You can specifiy the volume snapshot class when creating the Hybrid Cloud environment."
else
    echo ""
    echo "No volume snapshot classes are available. You will not be able to create snapshots of your Qdrant Clusters."
fi

echo ""

# check if connection to cloud.qdrant.io can be established from within a Pod in the Kubernetes cluster
echo "Checking connectivity to cloud.qdrant.io from within a Pod in the Kubernetes cluster..."
kubectl run -i --tty --rm qdrant-connection-test --image=registry.suse.com/bci/bci-base:15.6 --restart=Never -- curl https://cloud.qdrant.io/settings.json

echo ""
echo "Your Kubernetes version is"
kubectl version
