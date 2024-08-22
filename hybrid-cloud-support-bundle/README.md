# Hybrid Cloud Support Bundle

This tool collects logs and configuration files from a Qdrant Hybrid Cloud environment and all managed Qdrant database clusters, and bundles them in a `tgz` archive for easy sharing with Qdrant Support Engineers.

## Prerequisites

This script requires to be run in a Linux, macOS, or Windows environment with WSL. `bash` is required.

The following tools are required to use this script:

- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [jq](https://jqlang.github.io/jq/download/)

`kubectl` must be configured to access the Kubernetes cluster of your Qdrant Hybrid Cloud environment.

## Usage

1. Clone this repository or download `hybrid-cloud-support-bundle.sh`
```bash
wget https://raw.githubusercontent.com/qdrant/qdrant-cloud-support-tools/main/hybrid-cloud-support-bundle/hybrid-cloud-support-bundle.sh 
```
2. Make sure that script is executable
```bash
chmod +x hybrid-cloud-support-bundle.sh
```
3. Run the script
```bash
./hybrid-cloud-support-bundle.sh the-qdrant-namespace
```

## Collected data

* YAML definitions of `kubectl describe` output including events and status of the following resources in the Qdrant namespace:
  * QdrantClusters.qdrant.io
  * QdrantClusterRestores.qdrant.io
  * QdrantClusterSnapshots.qdrant.io
  * QdrantClusterScheduledSnapshots.qdrant.io
  * StorageClasses
  * StatefulSets.apps
  * Pods
  * Services
  * Deployments.apps
  * Ingresses.networking.k8s.io
  * NetworkPolicies.networking.k8s.io
  * ConfigMaps
  * HelmCharts.cd.qdrant.io
  * HemlRelease.cd.qdrant.io
  * HelmRepositories.cd.qdrant.io
  * Nodes
  * VolumeSnapshots.snapshot.storage.k8s.io
  * VolumeSnapshotClasses.snapshot.storage.k8s.io
  * PersistentVolumeClaims
* Logs from all pods in the Qdrant namespace
* Kubernetes version
* Results of the Kubernetes metrics API for all nodes and pods in the Qdrant namespace, if available
* Results of the Qdrant DB:
  * Telemetry endpoint
  * Cluster information endpoint
  * Collection list endpoint
  * Collection configuration endpoint
  * Collection cluster information endpoint
* Network Connectivity between pods in the Qdrant namespace

The support bundle does not contain any user data stored int the Qdrant database, on volumes or snapshots, or sensitive information like API keys or certificates.
