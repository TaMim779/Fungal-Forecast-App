"""Geospatial helpers."""

from __future__ import annotations

import math

EARTH_RADIUS_KM = 6371.0088


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance between two WGS84 points, in kilometres."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlmb / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def grid_cell(lat: float, lon: float, size_deg: float = 0.05) -> tuple[float, float]:
    """Snap a coordinate to the centre of a grid cell (~5.5 km at the equator for 0.05°)."""
    clat = math.floor(lat / size_deg) * size_deg + size_deg / 2
    clon = math.floor(lon / size_deg) * size_deg + size_deg / 2
    return round(clat, 5), round(clon, 5)
