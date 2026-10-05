"""Weather providers.

`OpenMeteoWeather` pulls a free, key-less hourly forecast and aggregates it into
daily agro-climatic indicators (including a leaf-wetness proxy = hours with RH >= 90%).
`MockWeather` produces deterministic, location-seeded data for offline use and tests.
"""

from __future__ import annotations

import hashlib
import logging
import math
from dataclasses import asdict, dataclass
from datetime import date, timedelta
from typing import Protocol

import httpx

from ..config import settings

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class DailyWeather:
    day: date
    t_min: float
    t_max: float
    t_mean: float
    rh_mean: float
    rh_max: float
    rain_mm: float
    wet_hours: int  # hours with RH >= 90% or rain > 0 (leaf wetness proxy)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["day"] = self.day.isoformat()
        return d


class WeatherProvider(Protocol):
    name: str

    async def forecast(self, lat: float, lon: float, days: int) -> list[DailyWeather]: ...


class MockWeather:
    """Deterministic synthetic forecast seeded by location (no network)."""

    name = "mock"

    async def forecast(self, lat: float, lon: float, days: int) -> list[DailyWeather]:
        seed = int(hashlib.sha256(f"{lat:.2f},{lon:.2f}".encode()).hexdigest()[:8], 16)
        # Warm, humid baseline typical of monsoon South Asia; vary by seed/day.
        base_t = 24 + (seed % 7)
        base_rh = 78 + (seed % 15)
        out: list[DailyWeather] = []
        today = date.today()
        for i in range(days):
            wobble = math.sin((seed % 13) + i * 1.3)
            t_mean = base_t + 2.5 * wobble
            rh = min(99.0, max(45.0, base_rh + 8 * math.cos(i * 0.9 + seed % 5)))
            rain = max(0.0, 6 * math.sin(i * 1.7 + seed % 3)) if rh > 82 else 0.0
            wet_hours = int(max(0, min(24, (rh - 70) / 1.4 + (6 if rain > 0 else 0))))
            out.append(
                DailyWeather(
                    day=today + timedelta(days=i),
                    t_min=round(t_mean - 4, 1),
                    t_max=round(t_mean + 5, 1),
                    t_mean=round(t_mean, 1),
                    rh_mean=round(rh, 1),
                    rh_max=round(min(100.0, rh + 8), 1),
                    rain_mm=round(rain, 1),
                    wet_hours=wet_hours,
                )
            )
        return out


class OpenMeteoWeather:
    name = "open-meteo"
    URL = "https://api.open-meteo.com/v1/forecast"

    def __init__(self, timeout: float = settings.weather_timeout_seconds) -> None:
        self._timeout = timeout
        self._fallback = MockWeather()

    async def forecast(self, lat: float, lon: float, days: int) -> list[DailyWeather]:
        params = {
            "latitude": lat,
            "longitude": lon,
            "hourly": "temperature_2m,relative_humidity_2m,precipitation",
            "forecast_days": days,
            "timezone": "auto",
        }
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                resp = await client.get(self.URL, params=params)
                resp.raise_for_status()
                return self._aggregate(resp.json())
        except Exception as exc:  # network down, API change, etc.
            log.warning("Open-Meteo unavailable (%s); using mock weather", exc)
            return await self._fallback.forecast(lat, lon, days)

    @staticmethod
    def _aggregate(payload: dict) -> list[DailyWeather]:
        hourly = payload["hourly"]
        times, temps, rhs, rain = (
            hourly["time"],
            hourly["temperature_2m"],
            hourly["relative_humidity_2m"],
            hourly["precipitation"],
        )
        buckets: dict[str, list[tuple[float, float, float]]] = {}
        for t, temp, rh, pr in zip(times, temps, rhs, rain):
            if temp is None or rh is None:
                continue
            buckets.setdefault(t[:10], []).append((temp, rh, pr or 0.0))

        out: list[DailyWeather] = []
        for day_str, rows in sorted(buckets.items()):
            ts = [r[0] for r in rows]
            hs = [r[1] for r in rows]
            ps = [r[2] for r in rows]
            out.append(
                DailyWeather(
                    day=date.fromisoformat(day_str),
                    t_min=round(min(ts), 1),
                    t_max=round(max(ts), 1),
                    t_mean=round(sum(ts) / len(ts), 1),
                    rh_mean=round(sum(hs) / len(hs), 1),
                    rh_max=round(max(hs), 1),
                    rain_mm=round(sum(ps), 1),
                    wet_hours=sum(1 for h, p in zip(hs, ps) if h >= 90 or p > 0),
                )
            )
        return out


def get_weather_provider() -> WeatherProvider:
    if settings.weather_provider.lower() == "mock":
        return MockWeather()
    return OpenMeteoWeather()
