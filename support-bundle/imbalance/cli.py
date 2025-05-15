import argparse
import os
import logging
from fetchers import DEFAULT_NAMESPACE, get_filtered_pods, get_api_key, process_pod
from cache import CollectionCache
from node_report import generate_node_report, analyze_collections

def configure_logging() -> logging.Logger:
    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s - %(levelname)s - %(name)s - %(message)s"
    )
    return logging.getLogger(__name__)

def main():
    """
    Main entry point for the CLI tool.
    """
    parser = argparse.ArgumentParser(
        description="Fetch telemetry, collections, and cluster data from Qdrant pods."
    )
    parser.add_argument("--namespace", default=DEFAULT_NAMESPACE, help="Kubernetes namespace (default: DEFAULT_NAMESPACE)")
    parser.add_argument("--output-dir", default=".", help="Directory where JSON files will be saved (default: current directory)")
    args = parser.parse_args()

    # Configure logging
    global logger
    logger = configure_logging()

    os.makedirs(args.output_dir, exist_ok=True)

    cluster_dir = os.path.join(args.output_dir, "cluster")
    collection_dir = os.path.join(args.output_dir, "collection")
    telemetry_dir = os.path.join(args.output_dir, "telemetry")

    os.makedirs(cluster_dir, exist_ok=True)
    os.makedirs(collection_dir, exist_ok=True)
    os.makedirs(telemetry_dir, exist_ok=True)

    # Fetch and filter pods
    relevant_pods, cluster_id = get_filtered_pods(namespace=args.namespace)
    if not relevant_pods or not cluster_id:
        logger.error("Failed to find relevant pods or determine cluster ID.")
        return

    logger.info(f"Determined cluster ID: {cluster_id}")
    logger.info(f"Found {len(relevant_pods)} relevant pods for cluster {cluster_id}")

    # Fetch API key
    try:
        api_key = get_api_key(cluster_id, args.namespace)
        if api_key:
            logger.info(f"Retrieved API key for cluster {cluster_id}")
        else:
            logger.warning(f"No API key found for cluster {cluster_id}, proceeding without it.")
    except RuntimeError:
        logger.warning(f"No API key found for cluster {cluster_id}, proceeding without it.")
        api_key = None

    collection_cache = CollectionCache()

    for idx, pod in enumerate(relevant_pods):
        logger.info(f"Processing pod: {pod}")
        process_pod(pod, args.namespace, api_key, idx, args.output_dir, collection_cache)

    logger.info("\nProcessing completed successfully.")

    logger.info("\nStarting node report analysis...")

    report_path = os.path.join(args.output_dir, "imbalance-report.txt")
    with open(report_path, "w") as report_file:
        if os.path.exists(cluster_dir):
            generate_node_report(cluster_dir=cluster_dir)
            report_file.write("Cluster analysis completed.\n")
        else:
            report_file.write("Cluster directory does not exist. Skipping cluster analysis.\n")

        if os.path.exists(collection_dir):
            analyze_collections(collection_dir=collection_dir, cluster_dir=cluster_dir)
            report_file.write("Collection analysis completed.\n")
        else:
            report_file.write("Collection directory does not exist. Skipping collection analysis.\n")

    logger.info("\nNode report analysis completed.")


if __name__ == "__main__":
    main()