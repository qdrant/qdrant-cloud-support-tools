# hybrid-cloud-prerequisites

This repository contains a tool to check that all prerequisites for a Qdrant Hybrid Cloud environment are met.

## Usage

The script requires `bash` on Linux, macOS, or Windows Subsystem for Linux. You need `kubectl` and `helm` installed. `kubectl` must be configured to access the Kubernetes cluster that you want to use for a Hybrid Cloud environment.

```bash
./hybrid-cloud-prerequisites.sh
```

The results will be printed on stdout.
