"""Loads and indexes the disease / treatment / dealer knowledge base (JSON files)."""

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from ..config import DATA_DIR, SUPPORTED_LANGUAGES

HEALTHY_ID = "healthy"


def localized(text: dict[str, str] | str | None, lang: str) -> str:
    """Return the string in `lang`, falling back to English, then any value."""
    if text is None:
        return ""
    if isinstance(text, str):
        return text
    if lang in text and text[lang]:
        return text[lang]
    if "en" in text:
        return text["en"]
    return next(iter(text.values()), "")


def normalize_lang(lang: str | None) -> str:
    lang = (lang or "en").lower().split("-")[0]
    return lang if lang in SUPPORTED_LANGUAGES else "en"


class KnowledgeBase:
    def __init__(self, diseases: dict[str, Any], dealers: dict[str, Any]) -> None:
        self._diseases: dict[str, dict[str, Any]] = {d["id"]: d for d in diseases["diseases"]}
        self._crops: dict[str, dict[str, Any]] = diseases["crops"]
        self._dealers: list[dict[str, Any]] = dealers["dealers"]
        self._treatments: dict[str, dict[str, Any]] = {}
        for disease in self._diseases.values():
            for t in disease["treatments"]:
                self._treatments[t["id"]] = {**t, "disease_id": disease["id"]}

    # ---- diseases ---------------------------------------------------------
    def diseases(self, crop: str | None = None) -> list[dict[str, Any]]:
        items = list(self._diseases.values())
        if crop:
            items = [d for d in items if d["crop"] == crop]
        return items

    def disease(self, disease_id: str) -> dict[str, Any] | None:
        return self._diseases.get(disease_id)

    def disease_ids(self) -> list[str]:
        return list(self._diseases)

    # ---- crops ------------------------------------------------------------
    def crops(self) -> dict[str, dict[str, Any]]:
        return self._crops

    def crop(self, crop_id: str) -> dict[str, Any] | None:
        return self._crops.get(crop_id)

    # ---- treatments -------------------------------------------------------
    def treatment(self, treatment_id: str) -> dict[str, Any] | None:
        return self._treatments.get(treatment_id)

    # ---- dealers ----------------------------------------------------------
    def dealers(self, country: str | None = None) -> list[dict[str, Any]]:
        if country:
            return [d for d in self._dealers if d["country"] == country.upper()]
        return list(self._dealers)


@lru_cache(maxsize=1)
def get_knowledge_base() -> KnowledgeBase:
    with open(DATA_DIR / "diseases.json", encoding="utf-8") as f:
        diseases = json.load(f)
    with open(DATA_DIR / "dealers.json", encoding="utf-8") as f:
        dealers = json.load(f)
    return KnowledgeBase(diseases, dealers)
