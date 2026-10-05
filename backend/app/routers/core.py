"""Health, catalogue, farmers, diagnosis, forecast and treatment-plan endpoints."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile

from .. import __version__
from ..config import settings
from ..database import Database
from ..deps import get_classifier_dep, get_db, get_kb, get_weather
from ..schemas import DiagnosisOut, Farmer, FarmerIn, ForecastOut, TreatmentPlan
from ..services import risk_engine
from ..services.classifier import LeafClassifier
from ..services.diagnosis import present_diagnosis, run_diagnosis
from ..services.knowledge import KnowledgeBase, localized, normalize_lang
from ..services.treatment_planner import build_plan
from ..services.weather import WeatherProvider

router = APIRouter()

MAX_IMAGE_BYTES = 8 * 1024 * 1024


@router.get("/health", tags=["system"])
def health() -> dict[str, Any]:
    return {"status": "ok", "version": __version__, "weather_provider": settings.weather_provider}


@router.get("/catalog", tags=["catalog"])
def catalog(lang: str = "en", kb: KnowledgeBase = Depends(get_kb)) -> dict[str, Any]:
    lang = normalize_lang(lang)
    return {
        "languages": ["en", "bn", "hi"],
        "crops": [
            {"id": cid, "name": localized(c["name"], lang)} for cid, c in kb.crops().items()
        ],
        "diseases": [
            {
                "id": d["id"],
                "crop": d["crop"],
                "name": localized(d["name"], lang),
                "pathogen": d["pathogen"],
                "symptoms": localized(d["symptoms"], lang),
            }
            for d in kb.diseases()
        ],
    }


# ---- farmers -----------------------------------------------------------------
@router.post("/farmers", response_model=Farmer, tags=["farmers"])
def register_farmer(body: FarmerIn, db: Database = Depends(get_db), kb: KnowledgeBase = Depends(get_kb)):
    if body.crop not in kb.crops():
        raise HTTPException(422, f"Unknown crop '{body.crop}'")
    data = body.model_dump()
    data["language"] = normalize_lang(body.language)
    data["country"] = body.country.upper()
    return db.upsert_farmer(data)


@router.get("/farmers/{farmer_id}", response_model=Farmer, tags=["farmers"])
def get_farmer(farmer_id: str, db: Database = Depends(get_db)):
    farmer = db.get_farmer(farmer_id)
    if not farmer:
        raise HTTPException(404, "Farmer not found")
    return farmer


# ---- diagnosis ---------------------------------------------------------------
@router.post("/diagnose", response_model=DiagnosisOut, tags=["diagnosis"])
async def diagnose(
    image: UploadFile = File(..., description="Leaf photo (JPEG/PNG)"),
    crop: str = Form("rice"),
    lang: str = Form("en"),
    country: str = Form("BD"),
    field_size_ha: float = Form(1.0, gt=0, le=1000),
    lat: float | None = Form(None),
    lon: float | None = Form(None),
    farmer_id: str | None = Form(None),
    db: Database = Depends(get_db),
    kb: KnowledgeBase = Depends(get_kb),
    classifier: LeafClassifier = Depends(get_classifier_dep),
    weather: WeatherProvider = Depends(get_weather),
):
    if crop not in kb.crops():
        raise HTTPException(422, f"Unknown crop '{crop}'")
    data = await image.read()
    if not data:
        raise HTTPException(422, "Empty image")
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "Image larger than 8 MB")

    # Farmer profile fills in defaults when provided.
    if farmer_id:
        farmer = db.get_farmer(farmer_id)
        if not farmer:
            raise HTTPException(404, "Farmer not found")
        lat = lat if lat is not None else farmer["lat"]
        lon = lon if lon is not None else farmer["lon"]

    try:
        return await run_diagnosis(
            image_bytes=data, kb=kb, db=db, classifier=classifier, weather=weather,
            crop=crop, lang=normalize_lang(lang), country=country.upper(),
            field_size_ha=field_size_ha, lat=lat, lon=lon, farmer_id=farmer_id,
        )
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc


@router.get("/diagnoses/{diagnosis_id}", response_model=DiagnosisOut, tags=["diagnosis"])
def get_diagnosis(diagnosis_id: str, lang: str = "en", db: Database = Depends(get_db), kb: KnowledgeBase = Depends(get_kb)):
    row = db.get_diagnosis(diagnosis_id)
    if not row:
        raise HTTPException(404, "Diagnosis not found")
    return present_diagnosis(row, kb, normalize_lang(lang))


@router.get("/farmers/{farmer_id}/diagnoses", response_model=list[DiagnosisOut], tags=["diagnosis"])
def list_diagnoses(farmer_id: str, lang: str = "en", db: Database = Depends(get_db), kb: KnowledgeBase = Depends(get_kb)):
    lang = normalize_lang(lang)
    return [present_diagnosis(r, kb, lang) for r in db.list_diagnoses(farmer_id)]


# ---- forecast ----------------------------------------------------------------
@router.get("/forecast", response_model=ForecastOut, tags=["forecast"])
async def forecast(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    disease_id: str = Query(...),
    lang: str = "en",
    kb: KnowledgeBase = Depends(get_kb),
    weather: WeatherProvider = Depends(get_weather),
):
    lang = normalize_lang(lang)
    disease = kb.disease(disease_id)
    if not disease:
        raise HTTPException(404, "Unknown disease")
    daily = await weather.forecast(lat, lon, settings.forecast_days)
    days = risk_engine.build_forecast(disease, daily)
    summary = risk_engine.summarize(days)
    return {
        "disease_id": disease_id,
        "disease_name": localized(disease["name"], lang),
        "crop": disease["crop"],
        "lat": lat,
        "lon": lon,
        "weather_provider": weather.name,
        "days": [d.to_dict() for d in days],
        "summary": summary,
        "action": risk_engine.action_for(summary["overall_level"], lang),
    }


@router.get("/forecast/crop", tags=["forecast"])
async def crop_forecast(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    crop: str = "rice",
    lang: str = "en",
    kb: KnowledgeBase = Depends(get_kb),
    weather: WeatherProvider = Depends(get_weather),
) -> dict[str, Any]:
    """Risk outlook for every disease of a crop at one location (home-screen widget)."""
    lang = normalize_lang(lang)
    diseases = kb.diseases(crop)
    if not diseases:
        raise HTTPException(404, "Unknown crop")
    daily = await weather.forecast(lat, lon, settings.forecast_days)
    items = []
    for d in diseases:
        days = risk_engine.build_forecast(d, daily)
        summary = risk_engine.summarize(days)
        items.append(
            {
                "disease_id": d["id"],
                "disease_name": localized(d["name"], lang),
                "summary": summary,
                "daily_risk": [round(x.risk, 3) for x in days],
                "action": risk_engine.action_for(summary["overall_level"], lang),
            }
        )
    items.sort(key=lambda x: -x["summary"]["peak_risk"])
    return {
        "crop": crop,
        "lat": lat,
        "lon": lon,
        "weather_provider": weather.name,
        "weather": [d.to_dict() for d in daily],
        "diseases": items,
    }


# ---- treatment plan ----------------------------------------------------------
@router.get("/treatments/plan", response_model=TreatmentPlan, tags=["treatments"])
def treatment_plan(
    disease_id: str,
    field_size_ha: float = Query(1.0, gt=0, le=1000),
    country: str = "BD",
    lang: str = "en",
    severity: str = "moderate",
    risk_level: str = "moderate",
    kb: KnowledgeBase = Depends(get_kb),
):
    try:
        return build_plan(
            kb, disease_id, field_size_ha=field_size_ha, country=country.upper(),
            lang=normalize_lang(lang), severity=severity, risk_level=risk_level,
        )
    except KeyError:
        raise HTTPException(404, "Unknown disease")
