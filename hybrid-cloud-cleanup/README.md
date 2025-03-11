# hybrid-cloud-cleanup

**WARNING**

```
THIS WILL DELETE ALL RESOURCES CREATED BY QDRANT
MAKE SURE YOU HAVE CREATED AND TESTED YOUR BACKUPS
THIS IS A NON REVERSIBLE ACTION
```

This repository contains a tool to completely clean up and remove a Qdrant Hybrid Cloud environment from a Kubernetes cluster.

## Usage

The script requires `bash` on Linux, macOS, or Windows Subsystem for Linux. You need `kubectl` and `helm` installed. `kubectl` must be configured to access the Kubernetes cluster that you want to use for a Hybrid Cloud environment.

```bash
./hybrid-cloud-cleanup.sh your-qdrant-namespace
```