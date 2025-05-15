from typing import Optional, Any, List
import logging

logger = logging.getLogger(__name__)

class CollectionCache:
    """
    A simple cache for collections fetched from the first pod.
    Ensures collections are fetched only once.
    """
    def __init__(self):
        self._collections = None

    def get_collections(self, pod_name: str, namespace: str, api_key: Optional[str], port: int, fetch_func) -> List[str]:
        """
        Fetch collections if not already cached.
        """
        if self._collections is None:
            logger.info(f"Fetching collections from pod {pod_name}")
            self._collections = fetch_func(pod_name, namespace, api_key, port)
            logger.info(f"Cached collections: {self._collections}")
        else:
            logger.debug(f"Using cached collections: {self._collections}")
        return self._collections