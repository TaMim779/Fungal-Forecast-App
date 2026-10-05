"""Leaf-photo classifier interface.

The production system runs an on-device TFLite/ONNX model inside the mobile app
(<3 s on a $60 Android phone) and only sends the *prediction* to the server.
This module defines the contract the server expects, plus a `HeuristicClassifier`
placeholder that lets the whole pipeline (forecast, costing, outbreaks, ledger)
run end-to-end without the ML model.

To plug in a real model: implement `LeafClassifier.predict` and register it in
`get_classifier()`. Nothing else in the backend needs to change.
"""

from __future__ import annotations

import hashlib
import io
from dataclasses import dataclass, field
from typing import Protocol

from PIL import Image

from .knowledge import HEALTHY_ID, KnowledgeBase

SEVERITIES = ("low", "moderate", "high", "severe")


@dataclass(frozen=True)
class Prediction:
    disease_id: str  # one of the knowledge-base ids or "healthy"
    confidence: float  # 0..1
    severity: str  # none|low|moderate|high|severe
    lesion_fraction: float  # fraction of leaf pixels that look diseased
    alternatives: list[tuple[str, float]] = field(default_factory=list)
    model_version: str = "heuristic-0.1"


class LeafClassifier(Protocol):
    model_version: str

    def predict(self, image_bytes: bytes, crop_hint: str | None = None) -> Prediction: ...


class HeuristicClassifier:
    """Colour-statistics placeholder. NOT a disease model.

    * Lesion fraction = share of pixels that are brown/yellow/grey rather than green.
    * Severity is derived from the lesion fraction.
    * The disease label is chosen deterministically from the image hash among the
      diseases for the hinted crop, so the same photo always yields the same answer.
    """

    model_version = "heuristic-0.1"

    def __init__(self, kb: KnowledgeBase) -> None:
        self._kb = kb

    def predict(self, image_bytes: bytes, crop_hint: str | None = None) -> Prediction:
        lesion = self._lesion_fraction(image_bytes)
        digest = hashlib.sha256(image_bytes).digest()

        if lesion < 0.08:
            conf = 0.80 + (digest[0] / 255) * 0.17
            return Prediction(HEALTHY_ID, round(conf, 3), "none", round(lesion, 3))

        candidates = self._kb.diseases(crop_hint) or self._kb.diseases()
        primary = candidates[digest[1] % len(candidates)]
        # Confidence spans 0.55-0.97 so a share of cases exercise the agronomist queue.
        conf = 0.55 + (digest[2] / 255) * 0.42
        severity = self._severity(lesion)
        alts = [
            (d["id"], round(max(0.02, (1 - conf) / max(1, len(candidates) - 1)), 3))
            for d in candidates
            if d["id"] != primary["id"]
        ][:2]
        return Prediction(primary["id"], round(conf, 3), severity, round(lesion, 3), alts)

    @staticmethod
    def _severity(lesion: float) -> str:
        if lesion < 0.18:
            return "low"
        if lesion < 0.35:
            return "moderate"
        if lesion < 0.55:
            return "high"
        return "severe"

    @staticmethod
    def _lesion_fraction(image_bytes: bytes) -> float:
        try:
            img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except Exception as exc:
            raise ValueError("Unreadable image") from exc
        img.thumbnail((128, 128))
        pixels = list(img.getdata())
        if not pixels:
            return 0.0
        leaf = 0
        lesion = 0
        for r, g, b in pixels:
            brightness = (r + g + b) / 3
            if brightness < 25 or brightness > 240:  # background / glare
                continue
            leaf += 1
            is_green = g > r * 1.08 and g > b * 1.08
            if not is_green:
                lesion += 1
        return lesion / leaf if leaf else 0.0


def get_classifier(kb: KnowledgeBase) -> LeafClassifier:
    return HeuristicClassifier(kb)
