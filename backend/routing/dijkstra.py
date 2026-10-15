"""Directed shortest paths from plain node/edge records; no I/O or ML imports."""

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from heapq import heappop, heappush


@dataclass(frozen=True)
class Route:
    distance_meters: Decimal
    node_ids: list[str]


def shortest_routes(nodes: list[dict], edges: list[dict], source_id: str) -> dict[str, Route]:
    """Return routes to reachable nodes only; reject malformed active graph data.

    Decimal preserves the database's numeric distances. Sorted neighbours and
    node IDs in the heap give deterministic paths when distances are tied.
    """
    graph = {node["id"]: [] for node in nodes}
    if len(graph) != len(nodes):
        raise ValueError("Graph node IDs must be unique.")
    if source_id not in graph:
        raise ValueError("The source node does not exist.")
    for edge in edges:
        if not edge["is_active"]:
            continue
        start, end = edge["from_node_id"], edge["to_node_id"]
        if start not in graph or end not in graph:
            raise ValueError("An active edge references an unknown node.")
        try:
            distance = Decimal(str(edge["distance_meters"]))
        except InvalidOperation:
            raise ValueError("Edge distances must be finite nonnegative numbers.") from None
        if not distance.is_finite() or distance < 0:
            raise ValueError("Edge distances must be finite nonnegative numbers.")
        graph[start].append((end, distance))
    for neighbours in graph.values():
        neighbours.sort()

    distances = {source_id: Decimal(0)}
    predecessors = {}
    pending = [(Decimal(0), source_id)]
    while pending:
        distance, current = heappop(pending)
        if distance != distances[current]:
            continue
        for neighbour, weight in graph[current]:
            candidate = distance + weight
            if neighbour not in distances or candidate < distances[neighbour]:
                distances[neighbour] = candidate
                predecessors[neighbour] = current
                heappush(pending, (candidate, neighbour))

    routes = {}
    for destination, distance in distances.items():
        path = [destination]
        while path[-1] != source_id:
            path.append(predecessors[path[-1]])
        routes[destination] = Route(distance, list(reversed(path)))
    return routes
