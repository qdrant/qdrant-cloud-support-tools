import argparse
import json
import os
import logging
from typing import Dict, Any

# Use root logger handlers; remove module-specific handlers
logger = logging.getLogger(__name__)
logger.handlers.clear()
logger.setLevel(logging.DEBUG)
logger.propagate = True


def calculate_totals(peer_data: Dict[str, Dict[str, Any]], cluster_dir: str) -> Dict[str, int]:
    """
    Calculate total points, shards, active shards, inactive shards,
    shard transfers, number of unique peers, and number of collections.
    """
    total_points = sum(data['points'] for data in peer_data.values())
    total_shards = sum(data['shards'] for data in peer_data.values())
    active_shards = 0
    inactive_shards = 0
    shard_transfers = 0
    unique_peers = set()
    collections = set()

    for file_name in os.listdir(cluster_dir):
        if not file_name.endswith('.json'):
            continue
        path = os.path.join(cluster_dir, file_name)
        with open(path, encoding='utf-8') as f:
            cluster_data = json.load(f)
            result = cluster_data.get('result', {})
            if not result:
                continue

            for shard in result.get('local_shards', []):
                if shard.get('state') == 'Active':
                    active_shards += 1
                else:
                    inactive_shards += 1

            shard_transfers += len(result.get('shard_transfers', []))
            unique_peers.add(result.get('peer_id', 'Unknown'))
            collection_name = file_name.rsplit('-', 1)[-1].replace('.json', '')
            collections.add(collection_name)

    return {
        'total_points': total_points,
        'total_shards': total_shards,
        'active_shards': active_shards,
        'inactive_shards': inactive_shards,
        'shard_transfers': shard_transfers,
        'peers': len(unique_peers),
        'collections': len(collections)
    }


def generate_node_report(cluster_dir: str) -> None:
    """
    Print imbalance analysis grouped by peer ID for all cluster JSON files.
    """
    peer_data: Dict[str, Dict[str, Any]] = {}

    for file_name in os.listdir(cluster_dir):
        if not file_name.endswith('.json'):
            continue
        path = os.path.join(cluster_dir, file_name)
        with open(path, encoding='utf-8') as f:
            cluster_data = json.load(f)
            result = cluster_data.get('result', {})
            if not result:
                continue

            peer_id = str(result.get('peer_id', 'Unknown'))
            local_shards = result.get('local_shards', [])
            points = sum(shard.get('points_count', 0) for shard in local_shards)
            shards = len(local_shards)

            if peer_id not in peer_data:
                peer_data[peer_id] = {'points': 0, 'shards': 0, 'files': []}
            peer_data[peer_id]['points'] += points
            peer_data[peer_id]['shards'] += shards
            peer_data[peer_id]['files'].append(file_name)

    print("\n=== Imbalance Analysis per Peer ===")
    sorted_peers = sorted(peer_data.items(), key=lambda x: x[1]['points'], reverse=True)
    for idx, (peer_id, data) in enumerate(sorted_peers, start=1):
        files_list = ", ".join(data['files'])
        print(f"{idx}. Peer ID={peer_id}, Points={data['points']}, Shards={data['shards']}, Files=[{files_list}]")

    print("\n=== Total Summary ===")
    totals = calculate_totals(peer_data, cluster_dir)
    print(f"Total Points: {totals['total_points']}")
    print(f"Total Shards: {totals['total_shards']}")
    print(f"Active Shards: {totals['active_shards']}")
    print(f"Inactive Shards: {totals['inactive_shards']}")
    print(f"Shard Transfers: {totals['shard_transfers']}")
    print(f"Peers: {totals['peers']}")
    print(f"Collections: {totals['collections']}")


def get_shard_details(cluster_dir: str, collection_name: str) -> Dict[int, Dict[str, Any]]:
    """
    Return a mapping of shard ID to its state and points for a given collection.
    """
    details: Dict[int, Dict[str, Any]] = {}

    for file_name in os.listdir(cluster_dir):
        if not file_name.endswith(f"{collection_name}.json"):
            continue
        path = os.path.join(cluster_dir, file_name)
        with open(path, encoding='utf-8') as f:
            cluster_data = json.load(f)
            result = cluster_data.get('result', {})
            for shard in result.get('local_shards', []):
                shard_id = shard.get('shard_id')
                details[shard_id] = {
                    'state': shard.get('state', 'Unknown'),
                    'points': shard.get('points_count', 0)
                }
    return details


def analyze_collections(collection_dir: str, cluster_dir: str) -> None:
    """
    Print detailed analysis for each collection directory.
    """
    print("\n=== Collection Analysis ===")

    for file_name in os.listdir(collection_dir):
        if not file_name.endswith('.json'):
            continue
        path = os.path.join(collection_dir, file_name)
        with open(path, encoding='utf-8') as f:
            collection_data = json.load(f)
            result = collection_data.get('result', {})
            collection_id = file_name.replace('collection-', '').replace('.json', '')

            print(f"\nCollection: {collection_id}")
            print(f"  - Points: {result.get('points_count', 'Unknown')}")
            print(f"  - Segments: {result.get('segments_count', 'Unknown')}")
            print(f"  - Shards: {result.get('config', {}).get('params', {}).get('shard_number', 'Unknown')}")
            print(f"  - Replication Factor: {result.get('config', {}).get('params', {}).get('replication_factor', 'Unknown')}")
            print(f"  - Distance Metric: {result.get('config', {}).get('params', {}).get('vectors', {}).get('distance', 'Unknown')}")
            print(f"  - Indexed Vectors Count: {result.get('indexed_vectors_count', 'Unknown')}")

            shard_details = get_shard_details(cluster_dir, collection_id)
            if shard_details:
                print("\n  Shards:")
                for shard_id, info in shard_details.items():
                    print(f"    - Shard ID: {shard_id}, State: {info['state']}, Points: {info['points']}")

            quant_cfg = result.get('config', {}).get('quantization_config', None)
            print(f"\n - Quantization Config:\n{json.dumps(quant_cfg, indent=2)}")
            hnsw_cfg = result.get('config', {}).get('hnsw_config', {})
            print(f"\n - HNSW Config:\n{json.dumps(hnsw_cfg, indent=2)}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Analyze cluster and collection data.')
    parser.add_argument(
        '--output-dir', default='out',
        help='Base directory containing cluster and collection subdirectories.'
    )
    args = parser.parse_args()

    cluster_dir = os.path.join(args.output_dir, 'cluster')
    collection_dir = os.path.join(args.output_dir, 'collection')

    if os.path.exists(cluster_dir):
        generate_node_report(cluster_dir=cluster_dir)
    else:
        logger.warning(f"Cluster directory {cluster_dir} does not exist. Skipping.")

    if os.path.exists(collection_dir):
        analyze_collections(collection_dir=collection_dir, cluster_dir=cluster_dir)
    else:
        logger.warning(f"Collection directory {collection_dir} does not exist. Skipping.")