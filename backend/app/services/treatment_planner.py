"""Costed treatment plan generator.

Scales label dosages by field size, prices them in the farmer's currency, and
estimates the economic value protected (yield loss averted) so the farmer sees
the return on each option. Organic options are listed first.
"""

from __future__ import annotations

from typing import Any

from ..config import currency_for
from .knowledge import KnowledgeBase, localized

# Fraction of the expected disease loss that a timely treatment is assumed to prevent.
EFFICACY = {"organic": 0.55, "chemical": 0.80}


def _round_qty(qty: float) -> float:
    return round(qty, 2) if qty < 10 else round(qty, 1)


def expected_loss_usd(
    kb: KnowledgeBase, disease: dict[str, Any], severity: str, field_size_ha: float
) -> float:
    crop = kb.crop(disease["crop"]) or {"yield_t_per_ha": 3.0, "price_usd_per_t": 250}
    loss_pct = disease["yield_loss_pct"].get(severity, disease["yield_loss_pct"]["moderate"])
    gross_value = crop["yield_t_per_ha"] * crop["price_usd_per_t"] * field_size_ha
    return gross_value * loss_pct / 100.0


def build_plan(
    kb: KnowledgeBase,
    disease_id: str,
    *,
    field_size_ha: float,
    country: str,
    lang: str,
    severity: str = "moderate",
    risk_level: str = "moderate",
) -> dict[str, Any]:
    disease = kb.disease(disease_id)
    if disease is None:
        raise KeyError(disease_id)
    if field_size_ha <= 0:
        raise ValueError("field_size_ha must be positive")

    cur = currency_for(country)
    rate = float(cur["rate"])
    loss_usd = expected_loss_usd(kb, disease, severity, field_size_ha)

    options: list[dict[str, Any]] = []
    for t in disease["treatments"]:
        qty_per_app = t["dose_per_ha"] * field_size_ha
        total_qty = qty_per_app * t["applications"]
        cost_usd = total_qty * t["unit_price_usd"]
        protected_usd = loss_usd * EFFICACY[t["type"]]
        net_usd = protected_usd - cost_usd
        options.append(
            {
                "treatment_id": t["id"],
                "type": t["type"],
                "product": t["product"],
                "dose_per_ha": t["dose_per_ha"],
                "unit": t["unit"],
                "quantity_per_application": _round_qty(qty_per_app),
                "applications": t["applications"],
                "interval_days": t["interval_days"],
                "total_quantity": _round_qty(total_qty),
                "pre_harvest_interval_days": t["phi_days"],
                "cost_usd": round(cost_usd, 2),
                "cost_local": round(cost_usd * rate, 0),
                "value_protected_local": round(protected_usd * rate, 0),
                "net_benefit_local": round(net_usd * rate, 0),
                "roi": round(protected_usd / cost_usd, 1) if cost_usd > 0 else None,
                "notes": localized(t.get("notes"), lang),
            }
        )

    # Organic first, then by cost.
    options.sort(key=lambda o: (0 if o["type"] == "organic" else 1, o["cost_usd"]))

    # Recommend: for high/severe risk prefer the best chemical by net benefit,
    # otherwise the cheapest organic option.
    if risk_level in ("high", "severe"):
        candidates = [o for o in options if o["type"] == "chemical"] or options
    else:
        candidates = [o for o in options if o["type"] == "organic"] or options
    recommended = max(candidates, key=lambda o: o["net_benefit_local"])

    return {
        "disease_id": disease_id,
        "disease_name": localized(disease["name"], lang),
        "crop": disease["crop"],
        "field_size_ha": field_size_ha,
        "currency": {"code": cur["code"], "symbol": cur["symbol"]},
        "expected_loss_local": round(loss_usd * rate, 0),
        "recommended_treatment_id": recommended["treatment_id"],
        "options": options,
    }
