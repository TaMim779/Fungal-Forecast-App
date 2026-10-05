"""Application settings, loaded from environment variables with sensible defaults."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    try:
        return float(raw) if raw is not None else default
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    app_name: str = "FungalForecast API"
    version: str = "0.1.0"
    database_path: str = os.getenv("FF_DATABASE_PATH", str(BASE_DIR.parent / "fungalforecast.db"))

    # Weather: "open-meteo" (live, no API key) or "mock" (deterministic, offline).
    weather_provider: str = os.getenv("FF_WEATHER_PROVIDER", "open-meteo")
    weather_timeout_seconds: float = _env_float("FF_WEATHER_TIMEOUT", 6.0)

    # Diagnoses below this confidence are routed to the human agronomist queue.
    agronomist_confidence_threshold: float = _env_float("FF_AGRONOMIST_THRESHOLD", 0.70)

    # Community outbreak alerts.
    outbreak_radius_km: float = _env_float("FF_OUTBREAK_RADIUS_KM", 10.0)
    outbreak_window_days: int = int(os.getenv("FF_OUTBREAK_WINDOW_DAYS", "14"))

    forecast_days: int = 5
    cors_origins: list[str] = field(default_factory=lambda: ["*"])
    debug: bool = _env_bool("FF_DEBUG", False)


settings = Settings()

# Supported UI / explanation languages. The server falls back to English.
SUPPORTED_LANGUAGES = ("en", "bn", "hi")

# Currency table (ISO country -> code, symbol, USD rate). Rates are indicative
# and should be refreshed from a live FX source in production.
CURRENCIES: dict[str, dict[str, float | str]] = {
    "BD": {"code": "BDT", "symbol": "৳", "rate": 120.0},
    "IN": {"code": "INR", "symbol": "₹", "rate": 84.0},
    "PK": {"code": "PKR", "symbol": "₨", "rate": 278.0},
    "NP": {"code": "NPR", "symbol": "रू", "rate": 134.0},
    "KE": {"code": "KES", "symbol": "KSh", "rate": 129.0},
    "NG": {"code": "NGN", "symbol": "₦", "rate": 1550.0},
    "TZ": {"code": "TZS", "symbol": "TSh", "rate": 2650.0},
    "UG": {"code": "UGX", "symbol": "USh", "rate": 3700.0},
    "ID": {"code": "IDR", "symbol": "Rp", "rate": 16200.0},
    "VN": {"code": "VND", "symbol": "₫", "rate": 25400.0},
    "PH": {"code": "PHP", "symbol": "₱", "rate": 58.0},
    "US": {"code": "USD", "symbol": "$", "rate": 1.0},
}


def currency_for(country: str | None) -> dict[str, float | str]:
    return CURRENCIES.get((country or "US").upper(), CURRENCIES["US"])
