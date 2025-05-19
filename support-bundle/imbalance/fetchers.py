import subprocess
import time
import socket
import json
import logging
import os
from contextlib import contextmanager
from typing import Optional, Dict, Any, List, Generator, Tuple

import requests
import re

from endpoints import Endpoint
from cache import CollectionCache

logger = logging.getLogger(__name__)

DEFAULT_REMOTE_PORT = 6333
DEFAULT_NAMESPACE = "qdrant"

def extract_cluster_id(pod_name: str) -> Optional[str]:
    """
    Extracts the cluster ID from the pod name.
    Assumes pod names follow the pattern: qdrant-<cluster-id>-<index>.
    """
    match = re.match(r"qdrant-([a-z0-9\-]+)-\d+", pod_name)
    return match.group(1) if match else None

def is_cluster_pod(pod_name: str, cluster_id: str) -> bool:
    """
    Checks if the pod belongs to the cluster with the given cluster_id.
    """
    return bool(re.match(rf"qdrant-{cluster_id}-\d+", pod_name))

def wait_for_port(host: str, port: int, timeout: float = 10.0) -> bool:
    """
    Wait until a TCP port is open on the host.
    Returns True if the port is available before timeout.
    """
    start = time.time()
    while time.time() - start < timeout:
        try:
            with socket.create_connection((host, port), timeout=1):
                return True
        except OSError:
            time.sleep(0.2)
    return False


def get_api_key(cluster_id: str, namespace: str) -> Optional[str]:
    """
    Retrieve API key from Kubernetes secret for the cluster.
    """
    secret_name = f"qdrant-api-key-{cluster_id}"
    cmd = [
        "kubectl",
        "get",
        "secret",
        secret_name,
        "-n",
        namespace,
        "-o",
        'go-template={{index .data "api-key" | base64decode}}',
    ]
    logger.debug(f"Running command to get API key: {' '.join(cmd)}")
    try:
        api_key = subprocess.check_output(cmd, text=True).strip()
        if not api_key:
            logger.warning(f"API key for cluster {cluster_id} is empty.")
            return None
        return api_key
    except subprocess.CalledProcessError as e:
        logger.warning(f"Failed to retrieve API key for cluster {cluster_id}: {e}")
        return None


def get_filtered_pods(namespace: str) -> Tuple[List[str], Optional[str]]:
    """
    Fetches all pods in the specified namespace, filters out service-related pods,
    and extracts the cluster ID from the first relevant pod.
    """
    cmd = ["kubectl", "get", "pods", "-n", namespace, "-o", "json"]
    logger.debug(f"Running command to get pods: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        pods_json = json.loads(result.stdout)
        all_pods = [pod["metadata"]["name"] for pod in pods_json["items"]]

        # Extract cluster ID from the first relevant pod
        cluster_id = None
        for pod_name in all_pods:
            cluster_id = extract_cluster_id(pod_name)
            if cluster_id:
                break

        if not cluster_id:
            logger.warning("No cluster ID could be determined from the pod names.")
            return [], None

        # Filter pods that belong to the cluster
        relevant_pods = [pod_name for pod_name in all_pods if is_cluster_pod(pod_name, cluster_id)]

        if not relevant_pods:
            logger.warning("No relevant pods found in the namespace.")
            return [], None

        return relevant_pods, cluster_id
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to get pods: {e}")
        return [], None


@contextmanager
def port_forward_context(pod_name: str, namespace: str, remote_port: int = DEFAULT_REMOTE_PORT) -> Generator[int, None, None]:
    """
    Open a kubectl port-forward to a pod mapping a free local port to the remote port.
    Yield the local port number for making requests.
    """
    # Find free local port
    logger.info(f"Finding free local port for pod {pod_name}")
    sock = socket.socket()
    sock.bind(("", 0))
    local_port = sock.getsockname()[1]
    sock.close()

    # Start port-forward process
    logger.info(
        f"Starting port-forward for pod {pod_name}: localhost:{local_port}->{remote_port}"
    )
    cmd = [
        "kubectl",
        "port-forward",
        f"pod/{pod_name}",
        f"{local_port}:{remote_port}",
        "-n",
        namespace,
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        # Wait for readiness
        logger.info(f"Waiting for port-forward to be ready on localhost:{local_port}")
        if not wait_for_port("localhost", local_port):
            raise RuntimeError(f"Failed to forward port for {pod_name}")
        logger.info(f"Port-forward ready on localhost:{local_port} for pod {pod_name}")
        yield local_port
    # Guaranteed close afterwards
    finally:
        logger.info(f"Closing port-forward for pod {pod_name}")
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def _execute_query(
    pod_name: str,
    api_key: Optional[str],
    path: str,
    port: int,
    output_file: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    """
    Perform requests.get on localhost:port{path}, save JSON to file.
    """
    url = f"http://localhost:{port}{path}"
    headers = {"api-key": api_key} if api_key else {}

    try:
        resp = requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
        data = resp.json()

        if output_file:
            _create_output_file(data, output_file, path)

        return data
    except Exception as e:
        logger.error(f"{pod_name} → request to {path} failed: {e}")
        return None


def _create_output_file(data: Dict[str, Any], output_file: str, path: str) -> None:
    base_dir = os.path.dirname(output_file) or '.'
    os.makedirs(base_dir, exist_ok=True)
    
    with open(output_file, "w") as f:
        json.dump(data, f, indent=2)
    logger.info(f"Data saved to {output_file}")


def fetch_telemetry(pod_name: str, namespace: str, api_key: Optional[str], port: int, output_file: str) -> Optional[Dict[str, Any]]:
    """
    Fetch telemetry data for the pod through the forwarded port.
    """
    return _execute_query(
        pod_name,
        api_key,
        path=Endpoint.TELEMETRY.value,
        port=port,
        output_file=output_file,
    )


def fetch_collections(pod_name: str, namespace: str, api_key: Optional[str], port: int) -> List[str]:
    """
    Fetch collections list from the pod.
    Returns a list of collection names or an empty list.
    If there are more than 10 collections, only returns the first 10.
    """
    data = _execute_query(pod_name, api_key, Endpoint.COLLECTIONS.value, port)
    if not data:
        logger.warning(f"No data received from collections endpoint for pod {pod_name}")
        return []
    
    collections = [c["name"] for c in data.get("result", {}).get("collections", [])]
    
    # TODO: Store all collections in the cache, but limit saving to files to the first 10 collections.
    # If there are more than 10 collections, log a warning and return only the first 10
    if len(collections) > 10:
        logger.info(f"Found {len(collections)} collections on pod {pod_name}, limiting to first 10")
        return collections[:10]
    
    return collections


def fetch_collection_info(
    pod_name: str,
    namespace: str,
    api_key: Optional[str],
    collection: str,
    port: int,
    output_file: str,
) -> Optional[Dict[str, Any]]:
    """
    Fetch per-collection settings via Endpoint.COLLECTION.
    """
    path = Endpoint.COLLECTION.value.format(name=collection)
    return _execute_query(pod_name, api_key, path, port, output_file)


def fetch_cluster_info(
    pod_name: str,
    namespace: str,
    api_key: Optional[str],
    collection: str,
    port: int,
    output_file: str,
) -> Optional[Dict[str, Any]]:
    """
    Fetch cluster info via Endpoint.CLUSTER.
    """
    path = Endpoint.CLUSTER.value.format(name=collection)
    return _execute_query(pod_name, api_key, path, port, output_file)

def fetch_clr_info(
    pod_name: str,
    namespace: str,
    api_key: Optional[str],
    port: int,
    output_file: str,
) -> Optional[Dict[str, Any]]:
    """
    Fetch general cluster info via Endpoint.CLR.
    """
    path = Endpoint.CLR.value
    return _execute_query(pod_name, api_key, path, port, output_file)

def process_pod(
    pod_name: str,
    namespace: str,
    api_key: Optional[str],
    pod_index: int,
    output_dir: str,
    collection_cache: CollectionCache
) -> None:
    """
    Create one port-forward session for the pod, run all queries, and close it.
    """
    with port_forward_context(pod_name, namespace) as port:
        # Fetch telemetry for the current pod
        telemetry_filename = os.path.join(output_dir, f"telemetry/telemetry_{pod_name}.json")
        fetch_telemetry(pod_name, namespace, api_key, port, telemetry_filename)

        # Fetch general cluster info for the current pod
        general_cluster_file = os.path.join(output_dir, "cluster", "cluster-general", f"{pod_name}-cluster.json")
        fetch_clr_info(pod_name, namespace, api_key, port, general_cluster_file)

        # Fetch collections using the cache
        collections = collection_cache.get_collections(pod_name, namespace, api_key, port, fetch_collections)
        # TODO: Handle case when there's no pod with index 0
        if pod_index == 0:
            for coll in collections:
                collection_filename = os.path.join(output_dir, f"collection/collection-{coll}.json")
                fetch_collection_info(pod_name, namespace, api_key, coll, port, collection_filename)

        # Fetch cluster info for each collection
        for coll in collections:
            cluster_filename = os.path.join(output_dir, f"cluster/cluster-{pod_index}-{coll}.json")
            fetch_cluster_info(pod_name, namespace, api_key, coll, port, cluster_filename)