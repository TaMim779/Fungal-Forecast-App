"""Community outbreak map & alerts, agro-dealer stock, agronomist queue, impact ledger."""

from __future__ import annotations

import csv
import io
from collections import Counter, defaultdict
from datetime import date
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from ..config import currency_for, settings
from ..database import Database
from ..deps import get_db, get_kb
from ..schemas import (
    DealerOut,
    DiagnosisOut,
    LedgerEntry,
    LedgerEntryIn,
    LedgerSummary,
    OutbreakAlert,
    OutbreakCell,
    ReviewIn,
)
from ..services import risk_engine
from ..services.diagnosis import present_diagnosis
from ..services.geo import grid_cell, haversine_km
from ..services.knowledge import KnowledgeBase, localized, normalize_lang
from ..services.treatment_planner import EFFICACY, build_plan, expected_loss_usd

router = APIRouter()

SEVERITY_RANK = {"none": 0, "low": 1, "moderate": 2, "high": 3, "severe": 4}

ALERT_MESSAGE = {
    "en": "{disease} reported on {n} farm(s) within {km} km of you in the last {days} days.",
    "bn": "গত {days} দিনে আপনার {km} কিমি এর মধ্যে {n} টি জমিতে {disease} ধরা পড়েছে।",
    "hi": "पिछले {days} दिनों में आपके {km} किमी के भीतर {n} खेत(ों) में {disease} पाया गया।",
}


# ---- outbreaks ---------------------------------------------------------------
@router.get("/outbreaks", response_model=list[OutbreakCell], tags=["community"])
def outbreaks(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(50.0, gt=0, le=500),
    lang: str = "en",
    db: Database = Depends(get_db),
    kb: KnowledgeBase = Depends(get_kb),
):
    """Grid-aggregated recent disease reports (privacy-preserving: no exact farm points)."""
    lang = normalize_lang(lang)
    cells: dict[tuple[float, float], list[dict[str, Any]]] = defaultdict(list)
    for d in db.recent_diagnoses(settings.outbreak_window_days):
        if haversine_km(lat, lon, d["lat"], d["lon"]) <= radius_km:
            cells[grid_cell(d["lat"], d["lon"])].append(d)

    out = []
    for (clat, clon), rows in cells.items():
        dominant = Counter(r["disease_id"] for r in rows).most_common(1)[0][0]
        worst = max(rows, key=lambda r: SEVERITY_RANK.get(r["severity"], 0))["severity"]
        out.append(
            {
                "lat": clat,
                "lon": clon,
                "reports": len(rows),
                "dominant_disease_id": dominant,
                "dominant_disease_name": localized((kb.disease(dominant) or {}).get("name"), lang),
                "max_severity": worst,
                "distance_km": round(haversine_km(lat, lon, clat, clon), 1),
                "last_report_at": max(r["created_at"] for r in rows),
            }
        )
    out.sort(key=lambda c: c["distance_km"])
    return out


@router.get("/outbreaks/alerts", response_model=list[OutbreakAlert], tags=["community"])
def outbreak_alerts(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    crop: str | None = None,
    farmer_id: str | None = None,
    lang: str = "en",
    db: Database = Depends(get_db),
    kb: KnowledgeBase = Depends(get_kb),
):
    """Pre-emptive alerts: diseases confirmed nearby that this farmer has NOT yet reported."""
    lang = normalize_lang(lang)
    radius = settings.outbreak_radius_km
    own = {d["disease_id"] for d in db.list_diagnoses(farmer_id)} if farmer_id else set()

    nearby: dict[str, list[float]] = defaultdict(list)
    for d in db.recent_diagnoses(settings.outbreak_window_days):
        if farmer_id and d["farmer_id"] == farmer_id:
            continue
        if crop and d["crop"] != crop:
            continue
        dist = haversine_km(lat, lon, d["lat"], d["lon"])
        if dist <= radius:
            nearby[d["disease_id"]].append(dist)

    alerts = []
    for disease_id, dists in nearby.items():
        if disease_id in own:
            continue
        disease = kb.disease(disease_id)
        if not disease:
            continue
        name = localized(disease["name"], lang)
        level = "high" if len(dists) >= 3 else "moderate"
        alerts.append(
            {
                "disease_id": disease_id,
                "disease_name": name,
                "crop": disease["crop"],
                "reports": len(dists),
                "nearest_km": round(min(dists), 1),
                "message": ALERT_MESSAGE[lang].format(
                    disease=name, n=len(dists), km=int(radius), days=settings.outbreak_window_days
                ),
                "recommended_action": risk_engine.action_for(level, lang),
            }
        )
    alerts.sort(key=lambda a: (-a["reports"], a["nearest_km"]))
    return alerts


# ---- dealers -----------------------------------------------------------------
@router.get("/dealers/nearby", response_model=list[DealerOut], tags=["dealers"])
def dealers_nearby(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    treatment_ids: str | None = Query(None, description="Comma-separated treatment ids to filter stock"),
    radius_km: float = Query(50.0, gt=0, le=1000),
    limit: int = Query(10, ge=1, le=50),
    kb: KnowledgeBase = Depends(get_kb),
):
    wanted = {t.strip() for t in treatment_ids.split(",")} if treatment_ids else None
    out = []
    for dealer in kb.dealers():
        dist = haversine_km(lat, lon, dealer["lat"], dealer["lon"])
        if dist > radius_km:
            continue
        items = []
        for inv in dealer["inventory"]:
            if wanted and inv["treatment_id"] not in wanted:
                continue
            t = kb.treatment(inv["treatment_id"])
            items.append(
                {
                    "treatment_id": inv["treatment_id"],
                    "product": t["product"] if t else inv["treatment_id"],
                    "in_stock": inv["in_stock"],
                    "stock_qty": inv["stock_qty"],
                    "price_local": inv["price_local"],
                }
            )
        if wanted and not items:
            continue
        out.append(
            {
                "id": dealer["id"],
                "name": dealer["name"],
                "address": dealer["address"],
                "phone": dealer["phone"],
                "lat": dealer["lat"],
                "lon": dealer["lon"],
                "distance_km": round(dist, 1),
                "opening_hours": dealer["opening_hours"],
                "currency": str(currency_for(dealer["country"])["code"]),
                "items": items,
            }
        )
    # In-stock matches first, then nearest.
    out.sort(key=lambda d: (0 if any(i["in_stock"] for i in d["items"]) else 1, d["distance_km"]))
    return out[:limit]


# ---- agronomist queue --------------------------------------------------------
@router.get("/agronomist/queue", response_model=list[DiagnosisOut], tags=["agronomist"])
def agronomist_queue(lang: str = "en", db: Database = Depends(get_db), kb: KnowledgeBase = Depends(get_kb)):
    lang = normalize_lang(lang)
    return [present_diagnosis(r, kb, lang) for r in db.pending_reviews()]


@router.post("/agronomist/queue/{diagnosis_id}/review", response_model=DiagnosisOut, tags=["agronomist"])
def review_case(
    diagnosis_id: str,
    body: ReviewIn,
    lang: str = "en",
    db: Database = Depends(get_db),
    kb: KnowledgeBase = Depends(get_kb),
):
    lang = normalize_lang(lang)
    if body.disease_id != "healthy" and not kb.disease(body.disease_id):
        raise HTTPException(422, "Unknown disease")
    row = db.get_diagnosis(diagnosis_id)
    if not row:
        raise HTTPException(404, "Diagnosis not found")
    updated = db.apply_review(diagnosis_id, body.model_dump())
    assert updated is not None
    # Re-plan if the agronomist changed the disease or severity.
    if body.disease_id != "healthy":
        plan_prev = row.get("plan") or {}
        country = _country_from_plan(plan_prev)
        plan = build_plan(
            kb, body.disease_id, field_size_ha=plan_prev.get("field_size_ha", 1.0), country=country,
            lang=lang, severity=body.severity, risk_level=row.get("risk_level") or "moderate",
        )
        db.update_diagnosis_plan(diagnosis_id, plan, row.get("forecast") or [])
        updated = db.get_diagnosis(diagnosis_id)
    return present_diagnosis(updated, kb, lang)  # type: ignore[arg-type]


def _country_from_plan(plan: dict[str, Any]) -> str:
    code = (plan.get("currency") or {}).get("code")
    from ..config import CURRENCIES

    for country, cur in CURRENCIES.items():
        if cur["code"] == code:
            return country
    return "BD"


# ---- ledger ------------------------------------------------------------------
@router.post("/ledger/entries", response_model=LedgerEntry, tags=["ledger"])
def add_ledger_entry(body: LedgerEntryIn, db: Database = Depends(get_db), kb: KnowledgeBase = Depends(get_kb)):
    farmer = db.get_farmer(body.farmer_id)
    if not farmer:
        raise HTTPException(404, "Farmer not found")
    dx = db.get_diagnosis(body.diagnosis_id)
    if not dx:
        raise HTTPException(404, "Diagnosis not found")
    disease = kb.disease(dx["disease_id"])
    treatment = kb.treatment(body.treatment_id)
    if not disease or not treatment or treatment["disease_id"] != disease["id"]:
        raise HTTPException(422, "Treatment does not match the diagnosed disease")

    plan = dx.get("plan") or {}
    field_size = float(plan.get("field_size_ha") or farmer["field_size_ha"])
    cur = currency_for(farmer["country"])
    rate = float(cur["rate"])
    option = next((o for o in plan.get("options", []) if o["treatment_id"] == body.treatment_id), None)
    cost_local = option["cost_local"] if option else round(
        treatment["dose_per_ha"] * field_size * treatment["applications"] * treatment["unit_price_usd"] * rate, 0
    )
    loss_usd = expected_loss_usd(kb, disease, dx["severity"], field_size)
    averted_local = round(loss_usd * EFFICACY[treatment["type"]] * rate, 0)

    return db.insert_ledger_entry(
        {
            "farmer_id": body.farmer_id,
            "diagnosis_id": body.diagnosis_id,
            "treatment_id": body.treatment_id,
            "disease_id": disease["id"],
            "crop": disease["crop"],
            "field_size_ha": field_size,
            "cost_local": cost_local,
            "loss_averted_local": averted_local,
            "currency": str(cur["code"]),
            "applied_on": body.applied_on or date.today().isoformat(),
        }
    )


@router.get("/ledger/entries", response_model=list[LedgerEntry], tags=["ledger"])
def list_ledger(farmer_id: str | None = None, db: Database = Depends(get_db)):
    return db.ledger_entries(farmer_id)


@router.get("/ledger/summary", response_model=LedgerSummary, tags=["ledger"])
def ledger_summary(farmer_id: str | None = None, db: Database = Depends(get_db)):
    entries = db.ledger_entries(farmer_id)
    by_disease: dict[str, dict[str, float]] = defaultdict(lambda: {"entries": 0, "cost": 0.0, "averted": 0.0})
    cost = averted = 0.0
    for e in entries:
        cost += e["cost_local"]
        averted += e["loss_averted_local"]
        b = by_disease[e["disease_id"]]
        b["entries"] += 1
        b["cost"] += e["cost_local"]
        b["averted"] += e["loss_averted_local"]
    return {
        "farmer_id": farmer_id,
        "entries": len(entries),
        "total_cost_local": round(cost, 0),
        "total_loss_averted_local": round(averted, 0),
        "net_value_local": round(averted - cost, 0),
        "currency": entries[0]["currency"] if entries else None,
        "by_disease": dict(by_disease),
    }


@router.get("/ledger/export.csv", tags=["ledger"])
def export_ledger(farmer_id: str | None = None, db: Database = Depends(get_db)):
    """Partner export (microfinance / crop insurance)."""
    entries = db.ledger_entries(farmer_id)
    buf = io.StringIO()
    writer = csv.writer(buf)
    cols = [
        "id", "farmer_id", "diagnosis_id", "disease_id", "crop", "treatment_id", "field_size_ha",
        "cost_local", "loss_averted_local", "currency", "applied_on", "created_at",
    ]
    writer.writerow(cols)
    for e in entries:
        writer.writerow([e[c] for c in cols])
    buf.seek(0)
    return StreamingResponse(
        iter([buf.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=fungalforecast_ledger.csv"},
    )
