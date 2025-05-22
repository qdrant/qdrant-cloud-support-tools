import argparse
import os
import logging
import shutil
import sys
import time

from fetchers import DEFAULT_NAMESPACE, get_filtered_pods, get_api_key, process_pod
from cache import CollectionCache
from node_report import generate_node_report, analyze_collections

class Tee:
    """
    Duplicate writes to multiple file-like objects.
    """
    def __init__(self, *files):
        self.files = files

    def write(self, data):
        for f in self.files:
            f.write(data)

    def flush(self):
        for f in self.files:
            f.flush()

LOG_FMT = "%(asctime)s - %(levelname)s - %(name)s - %(message)s"

def configure_logging(log_file_path: str) -> logging.Logger:
    """
    Configure root logger:
      - DEBUG → console (stderr)
      - DEBUG → file (log_file_path)
    """
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)

    # Console handler
    ch = logging.StreamHandler(sys.stderr)
    ch.setLevel(logging.DEBUG)
    ch.setFormatter(logging.Formatter(LOG_FMT))

    # File handler
    fh = logging.FileHandler(log_file_path, mode="w", encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(logging.Formatter(LOG_FMT))

    logger.addHandler(ch)
    logger.addHandler(fh)

    return logger

def main():
    parser = argparse.ArgumentParser(
        description="Fetch telemetry, collections, and cluster data from Qdrant pods."
    )
    parser.add_argument(
        "--namespace",
        default=DEFAULT_NAMESPACE,
        help="Kubernetes namespace (default: qdrant)"
    )
    parser.add_argument(
        "--output-dir",
        default=".",
        help="Directory where JSON files will be saved"
    )
    args = parser.parse_args()

    # ensure output dirs
    os.makedirs(args.output_dir, exist_ok=True)
    report_path = os.path.join(args.output_dir, "imbalance-report.txt")

    # Configure logging (logger.* → console+file)
    logger = configure_logging(report_path)

    # Wrap print() → console + file
    original_stdout = sys.stdout
    original_stderr = sys.stderr
    report_fd = open(report_path, "a", encoding="utf-8")
    sys.stdout = Tee(original_stdout, report_fd)
    sys.stderr = Tee(original_stderr, report_fd)

    # Prepare subdirs
    cluster_dir = os.path.join(args.output_dir, "cluster")
    cluster_general_dir = os.path.join(cluster_dir, "cluster-general")
    collection_dir = os.path.join(args.output_dir, "collection")
    telemetry_dir = os.path.join(args.output_dir, "telemetry")
    for d in (cluster_dir, cluster_general_dir, collection_dir, telemetry_dir):
        os.makedirs(d, exist_ok=True)

    # Fetch pods
    relevant_pods, cluster_id = get_filtered_pods(namespace=args.namespace)
    if not relevant_pods or not cluster_id:
        logger.error("Failed to find relevant pods or determine cluster ID.")
        return

    logger.info(f"Determined cluster ID: {cluster_id}")
    logger.info(f"Found {len(relevant_pods)} relevant pods for cluster {cluster_id}")

    # API key
    try:
        api_key = get_api_key(cluster_id, args.namespace)
        if api_key:
            logger.info(f"Retrieved API key for cluster {cluster_id}")
        else:
            logger.warning(f"No API key found for cluster {cluster_id}, proceeding without it.")
    except RuntimeError:
        logger.warning(f"No API key found for cluster {cluster_id}, proceeding without it.")
        api_key = None

    # Process each pod
    cache = CollectionCache()
    for idx, pod in enumerate(relevant_pods):
        logger.info(f"Processing pod: {pod}")
        process_pod(pod, args.namespace, api_key, idx, args.output_dir, cache)

    logger.info("Processing completed successfully.")
    logger.info("Starting node report analysis...")

    # Generate reports (these use print, now captured by Tee)
    if os.path.exists(cluster_dir):
        generate_node_report(cluster_dir=cluster_dir)
    else:
        print(f"Cluster directory {cluster_dir} does not exist. Skipping.", file=sys.stderr)

    if os.path.exists(collection_dir):
        analyze_collections(collection_dir=collection_dir, cluster_dir=cluster_dir)
    else:
        print(f"Collection directory {collection_dir} does not exist. Skipping.", file=sys.stderr)

    logger.info("Node report analysis completed.")

    # restore stdout/stderr
    sys.stdout = original_stdout
    sys.stderr = original_stderr
    report_fd.close()

    # # Archive and clean up
    # cwd = os.getcwd()
    # bundle_name = "qdrant-cloud-support-bundle"
    # archive_path = shutil.make_archive(
    #     base_name=os.path.join(cwd, bundle_name),
    #     format="gztar",
    #     root_dir=os.path.join(cwd, args.output_dir)
    # )
    # shutil.rmtree(os.path.join(cwd, args.output_dir))
    # print(f"Archive created at {archive_path}", file=sys.stderr)

    # # **Keep the container alive** to allow `kubectl cp` to work
    # print("Bundle ready, sleeping for 1 hour to allow kubectl cp...", file=sys.stderr)
    # time.sleep(3600)

    # Archive and clean up
    cwd = os.getcwd()
    bundle_name = "qdrant-cloud-support-bundle"
    archive_path = shutil.make_archive(
        base_name=os.path.join(cwd, bundle_name),
        format="gztar",
        root_dir=os.path.join(cwd, args.output_dir)
    )
    shutil.rmtree(os.path.join(cwd, args.output_dir))
    print(f"Archive created at {archive_path}", file=sys.stderr)

    # Bundle is ready; keep this container running so that kubectl cp can fetch it.
    print("Bundle ready, entering sleep loop until job is deleted...", file=sys.stderr)
    while True:
        time.sleep(60)

if __name__ == "__main__":
    main()