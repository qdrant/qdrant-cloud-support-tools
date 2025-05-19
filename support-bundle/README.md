# Qdrant Hybrid Cloud / Private Cloud Support Bundle

This tool collects logs and configuration files from a Qdrant Hybrid Cloud or Private Cloud environment and all managed Qdrant database clusters in it. It bundles them in a `tgz` archive for easy sharing with Qdrant Support Engineers.

## Prerequisites

This script requires to be run in a Linux, macOS, or Windows environment with WSL. At least `bash` version 3 is required.

The following tools are required to use this script:

- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [jq](https://jqlang.github.io/jq/download/)
- [Python 3.7+](https://www.python.org/downloads/)

If you're unable to install the required dependencies, please use the `no-deps.sh` script as an alternative.

`kubectl` must be configured to access the Kubernetes cluster of your Qdrant Hybrid Cloud environment.

## Installing dependencies

This script requires Python dependencies to be installed. To ensure compatibility, a `requirements.txt` file is provided with the exact versions of the required libraries.

1. **Create a virtual environment (optional but recommended):**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. **Install the dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

If you encounter any issues, ensure that your Python version is 3.7 or higher and that all dependencies are installed correctly.

## Usage

1. Clone this repository or download `support-bundle.sh`
```bash
wget https://raw.githubusercontent.com/qdrant/qdrant-cloud-support-tools/main/support-bundle/support-bundle.sh 
```
2. Make sure that the script is executable
```bash
chmod +x support-bundle.sh
```
3. Run the script
```bash
./support-bundle.sh the-qdrant-namespace
```

## What the script does

The `support-bundle.sh` script performs the following steps:

1. **Collects Kubernetes resources**:
   - YAML definitions of `kubectl describe` output, including events and status of resources in the Qdrant namespace.
   - Logs from all pods in the Qdrant namespace.
   - Kubernetes version.
   - Results of the Kubernetes metrics API for all nodes and pods in the Qdrant namespace (if available).

2. **Delegates Qdrant-specific data collection to a Python script**:
   - The Python script (`imbalance/cli.py`) collects data from Qdrant database endpoints, including:
     - Telemetry endpoint.
     - Cluster information endpoint.
     - Collection list endpoint.
     - Collection configuration endpoint.
     - Collection cluster information endpoint.
   - Performs imbalance analysis:
     - Distribution of shards and points across nodes.
     - Collection configuration details.
     - Shard states (active/inactive).
     - HNSW configuration and quantization settings.

3. **Packages all collected data**:
   - Bundles the collected data into a `tgz` archive for easy sharing.

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
* **Imbalance analysis**:
  * Distribution of shards and points across nodes
  * Collection configuration details
  * Shard states (active/inactive)
  * HNSW configuration and quantization settings

The support bundle does not contain any user data stored in the Qdrant database, on volumes or snapshots, or sensitive information like API keys or certificates.
