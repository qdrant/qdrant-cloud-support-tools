import argparse
import json
import os
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter("%(message)s"))
logger.addHandler(handler)
logger.setLevel(logging.DEBUG)
logger.propagate = False 

# Keys reference: https://docs.google.com/document/d/1wKcUN2qZu1EXPEVFFPST36UkYGsojthzYQeG-Aardd4

# To run:
# python node_report.py
# Make sure you have the folder structure: out/cluster | out/collection | out/telemetry

def calculate_totals(peer_data: Dict[str, Dict[str, Any]], cluster_dir: str) -> Dict[str, int]:
    """
    Calculate total points, shards, active shards, inactive shards, remote shards, shard transfers, and peers.
    """
    total_points = sum(data['points'] for data in peer_data.values())
    total_shards = sum(data['shards'] for data in peer_data.values())
    active_shards = 0
    inactive_shards = 0
    shard_transfers = 0
    unique_peers = set()
    collections = set()

    for file_name in os.listdir(cluster_dir):
        if file_name.endswith(".json"):
            with open(os.path.join(cluster_dir, file_name), encoding="utf-8") as cluster_file:
                cluster_data = json.load(cluster_file)
                result = cluster_data.get('result', {})
                if not result:
                    continue

                # Count active and inactive shards
                for shard in result.get('local_shards', []):
                    if shard.get('state') == 'Active':
                        active_shards += 1
                    else:
                        inactive_shards += 1

                shard_transfers += len(result.get('shard_transfers', []))

                unique_peers.add(result.get('peer_id', 'Unknown'))

                collection_name = file_name.split('-')[-1].replace('.json', '')
                collections.add(collection_name)

    return {
        "total_points": total_points,
        "total_shards": total_shards,
        "active_shards": active_shards,
        "inactive_shards": inactive_shards,
        "shard_transfers": shard_transfers,
        "peers": len(unique_peers),
        "collections": len(collections)
    }

def generate_node_report(cluster_dir: str) -> None:
    """
    Analyze cluster data grouped by peer_id to show real imbalance.
    """
    peer_data: Dict[str, Dict[str, Any]] = {}

    for file_name in os.listdir(cluster_dir):
        if file_name.endswith(".json"):
            try:
                with open(os.path.join(cluster_dir, file_name), encoding="utf-8") as cluster_file:
                    cluster_data = json.load(cluster_file)
                    result = cluster_data.get('result', {})
                    if not result:
                        logger.warning(f"File {file_name} contains no data. Skipping.")
                        continue

                    peer_id = str(result.get('peer_id', 'Unknown'))
                    local_shards = result.get('local_shards', [])
                    points = sum(shard.get('points_count', 0) for shard in local_shards)
                    shards = len(local_shards)

                    # Accumulate data for each peer
                    if peer_id not in peer_data:
                        peer_data[peer_id] = {'points': 0, 'shards': 0, 'files': []}
                    peer_data[peer_id]['points'] += points
                    peer_data[peer_id]['shards'] += shards
                    peer_data[peer_id]['files'].append(file_name)

            except FileNotFoundError:
                logger.warning(f"File {file_name} not found. Skipping.")
            except KeyError as e:
                logger.error(f"Unexpected data format in {file_name}: missing key {e}. Skipping.")

    # Display imbalance analysis grouped by peer_id
    logger.info("\n=== Imbalance Analysis per Peer ===")
    for idx, (peer_id, data) in enumerate(sorted(peer_data.items(), key=lambda x: x[1]['points'], reverse=True), start=1):
        files = ", ".join(data['files'])
        logger.info(f"{idx}. Peer ID={peer_id}, Points={data['points']}, Shards={data['shards']}, Files=[{files}]")

    # Display total summary
    logger.info("\n=== Total Summary ===")
    totals = calculate_totals(peer_data, cluster_dir)
    logger.info(f"Total Points: {totals['total_points']}")
    logger.info(f"Total Shards: {totals['total_shards']}")
    logger.info(f"Active Shards: {totals['active_shards']}")
    logger.info(f"Inactive Shards: {totals['inactive_shards']}")
    logger.info(f"Shard Transfers: {totals['shard_transfers']}")
    logger.info(f"Peers: {totals['peers']}")
    logger.info(f"Collections: {totals['collections']}")

def get_shard_details(cluster_dir: str, collection_name: str) -> Dict[int, Dict[str, Any]]:
    """
    Retrieve shard details (state, points) from cluster files for a given collection.
    """
    shard_details = {}
    for file_name in os.listdir(cluster_dir):
        if file_name.endswith(f"{collection_name}.json"):
            with open(os.path.join(cluster_dir, file_name), encoding="utf-8") as cluster_file:
                cluster_data = json.load(cluster_file)
                result = cluster_data.get('result', {})
                for shard in result.get('local_shards', []):
                    shard_id = shard.get('shard_id')
                    shard_details[shard_id] = {
                        "state": shard.get('state', 'Unknown'),
                        "points": shard.get('points_count', 0)
                    }
    return shard_details

def analyze_collections(collection_dir: str, cluster_dir: str) -> None:
    """
    Analyze collection configurations and statuses, and print detailed information.
    """
    logger.info("\n=== Collection Analysis ===")
    for file_name in os.listdir(collection_dir):
        if file_name.endswith(".json"):
            try:
                with open(os.path.join(collection_dir, file_name), encoding="utf-8") as collection_file:
                    collection_data = json.load(collection_file)
                    result = collection_data.get('result', {})
                    collection_id = file_name.replace("collection-", "").replace(".json", "")

                    logger.info(f"\nCollection: {collection_id}")
                    logger.info(f"  - Points: {result.get('points_count', 'Unknown')}")
                    logger.info(f"  - Segments: {result.get('segments_count', 'Unknown')}")
                    logger.info(f"  - Shards: {result.get('config', {}).get('params', {}).get('shard_number', 'Unknown')}")
                    logger.info(f"  - Replication Factor: {result.get('config', {}).get('params', {}).get('replication_factor', 'Unknown')}")
                    logger.info(f"  - Distance Metric: {result.get('config', {}).get('params', {}).get('vectors', {}).get('distance', 'Unknown')}")
                    logger.info(f"  - Indexed Vectors Count: {result.get('indexed_vectors_count', 'Unknown')}")

                    # Get shard details from cluster files
                    shard_details = get_shard_details(cluster_dir, collection_id)
                    if shard_details:
                        logger.info("\n  Shards:")
                        for shard_id, details in shard_details.items():
                            logger.info(f"    - Shard ID: {shard_id}, State: {details['state']}, Points: {details['points']}")

                    quantization_config = result.get('config', {}).get('quantization_config', 'None')
                    logger.info(f"\n - Quantization Config:\n{json.dumps(quantization_config, indent=2)}")

                    hnsw_config = result.get('config', {}).get('hnsw_config', {})
                    logger.info(f"\n - HNSW Config:\n{json.dumps(hnsw_config, indent=2)}")

            except FileNotFoundError:
                logger.warning(f"File {file_name} not found. Skipping.")
            except KeyError as e:
                logger.error(f"Unexpected data format in {file_name}: missing key {e}. Skipping.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analyze cluster and collection data.")
    # You can run it directly:
    #   python node_report.py --output-dir ./out
    parser.add_argument("--output-dir", default="out",
                        help="Base directory containing cluster and collection subdirectories.")
    args = parser.parse_args()

    cluster_dir = os.path.join(args.output_dir, "cluster")
    collection_dir = os.path.join(args.output_dir, "collection")

    # Make sure you have the folder structure: ./out/cluster | ./out/collection | ./out/telemetry
    if os.path.exists(cluster_dir):
        generate_node_report(cluster_dir=cluster_dir)
    else:
        logger.warning(f"Cluster directory {cluster_dir} does not exist. Skipping cluster analysis.")

    if os.path.exists(collection_dir):
        analyze_collections(collection_dir=collection_dir, cluster_dir=cluster_dir)
    else:
        logger.warning(f"Collection directory {collection_dir} does not exist. Skipping collection analysis.")