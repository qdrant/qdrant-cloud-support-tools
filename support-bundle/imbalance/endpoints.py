from enum import Enum

class Endpoint(Enum):
    """
    The endpoints are used to fetch telemetry, collections, and cluster information.
    """

    TELEMETRY = "/telemetry?details_level=10"
    COLLECTIONS = "/collections"
    COLLECTION = "/collections/{name}"
    CLUSTER = "/collections/{name}/cluster"
    CLR = "/cluster"
