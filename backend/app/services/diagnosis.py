"""Orchestrates a diagnosis: classify -> forecast -> plan -> route -> persist -> explain."""

from __future__ import annotations

from typing import Any

from ..config import settings
from ..database import Database
from . import risk_engine
from .classifier import LeafClassifier, Prediction
from .knowledge import HEALTHY_ID, KnowledgeBase, localized
from .treatment_planner import build_plan
from .weather import WeatherProvider

EXPLANATION = {
    "healthy": {
        "en": "Good news: your {crop} leaf looks healthy ({conf}% confidence). Keep checking your field every few days.",
        "bn": "সুখবর: আপনার {crop} পাতা সুস্থ দেখাচ্ছে ({conf}% নিশ্চয়তা)। কয়েক দিন পর পর জমি দেখতে থাকুন।",
        "hi": "अच्छी खबर: आपकी {crop} की पत्ती स्वस्थ दिख रही है ({conf}% विश्वास)। हर कुछ दिन में खेत देखते रहें।",
    },
    "disease": {
        "en": "Your {crop} leaf shows signs of {disease} ({conf}% confidence, {severity} severity). "
              "Infection risk over the next 5 days is {level}. {action} "
              "Recommended: {product}, about {qty} {unit} for your {size} hectare field, costing around {symbol}{cost}.",
        "bn": "আপনার {crop} পাতায় {disease} এর লক্ষণ দেখা যাচ্ছে ({conf}% নিশ্চয়তা, তীব্রতা: {severity})। "
              "আগামী ৫ দিনে সংক্রমণের ঝুঁকি {level}। {action} "
              "সুপারিশ: {product}, আপনার {size} হেক্টর জমির জন্য প্রায় {qty} {unit}, খরচ প্রায় {symbol}{cost}।",
        "hi": "आपकी {crop} की पत्ती पर {disease} के लक्षण दिख रहे हैं ({conf}% विश्वास, गंभीरता: {severity})। "
              "अगले 5 दिनों में संक्रमण का जोखिम {level} है। {action} "
              "सुझाव: {product}, आपके {size} हेक्टेयर खेत के लिए लगभग {qty} {unit}, लागत लगभग {symbol}{cost}।",
    },
    "review": {
        "en": " The photo was unclear, so an agronomist will double-check this result within 24 hours.",
        "bn": " ছবিটি অস্পষ্ট ছিল, তাই একজন কৃষিবিদ ২৪ ঘণ্টার মধ্যে ফলাফলটি পুনরায় যাচাই করবেন।",
        "hi": " फ़ोटो स्पष्ट नहीं थी, इसलिए एक कृषि विशेषज्ञ 24 घंटे में इस परिणाम की दोबारा जाँच करेंगे।",
    },
}

LEVEL_WORDS = {
    "low": {"en": "low", "bn": "কম", "hi": "कम"},
    "moderate": {"en": "moderate", "bn": "মাঝারি", "hi": "मध्यम"},
    "high": {"en": "high", "bn": "বেশি", "hi": "अधिक"},
    "severe": {"en": "severe", "bn": "অত্যন্ত বেশি", "hi": "बहुत अधिक"},
    "none": {"en": "none", "bn": "নেই", "hi": "कोई नहीं"},
}


def _word(key: str, lang: str) -> str:
    return LEVEL_WORDS.get(key, LEVEL_WORDS["low"]).get(lang, key)


async def run_diagnosis(
    *,
    image_bytes: bytes,
    kb: KnowledgeBase,
    db: Database,
    classifier: LeafClassifier,
    weather: WeatherProvider,
    crop: str,
    lang: str,
    country: str,
    field_size_ha: float,
    lat: float | None,
    lon: float | None,
    farmer_id: str | None,
) -> dict[str, Any]:
    pred: Prediction = classifier.predict(image_bytes, crop_hint=crop)
    routed = pred.disease_id != HEALTHY_ID and pred.confidence < settings.agronomist_confidence_threshold

    forecast_out: dict[str, Any] | None = None
    plan: dict[str, Any] | None = None
    risk_level = "low"
    peak_risk = 0.0

    if pred.disease_id != HEALTHY_ID:
        disease = kb.disease(pred.disease_id)
        assert disease is not None
        if lat is not None and lon is not None:
            daily = await weather.forecast(lat, lon, settings.forecast_days)
            days = risk_engine.build_forecast(
                disease, daily, confidence=pred.confidence, severity=pred.severity
            )
            summary = risk_engine.summarize(days)
            risk_level = summary["overall_level"]
            peak_risk = summary["peak_risk"]
            forecast_out = {
                "disease_id": disease["id"],
                "disease_name": localized(disease["name"], lang),
                "crop": disease["crop"],
                "lat": lat,
                "lon": lon,
                "weather_provider": weather.name,
                "days": [d.to_dict() for d in days],
                "summary": summary,
                "action": risk_engine.action_for(risk_level, lang),
            }
        else:
            # No location: infer risk from severity alone.
            risk_level = {"low": "moderate", "moderate": "high", "high": "high", "severe": "severe"}[pred.severity]
        plan = build_plan(
            kb, pred.disease_id, field_size_ha=field_size_ha, country=country, lang=lang,
            severity=pred.severity, risk_level=risk_level,
        )

    diagnosis_id = db.insert_diagnosis(
        {
            "farmer_id": farmer_id,
            "crop": crop,
            "disease_id": pred.disease_id,
            "confidence": pred.confidence,
            "severity": pred.severity,
            "lesion_fraction": pred.lesion_fraction,
            "lat": lat,
            "lon": lon,
            "status": "pending_review" if routed else "confirmed",
            "risk_level": risk_level,
            "peak_risk": peak_risk,
            "forecast": forecast_out,
            "plan": plan,
            "model_version": pred.model_version,
        }
    )
    stored = db.get_diagnosis(diagnosis_id)
    assert stored is not None
    return present_diagnosis(stored, kb, lang, alternatives=pred.alternatives)


def present_diagnosis(
    row: dict[str, Any], kb: KnowledgeBase, lang: str, *, alternatives: list[tuple[str, float]] | None = None
) -> dict[str, Any]:
    """Shape a stored diagnosis row into the API response, with a localized explanation."""
    disease = kb.disease(row["disease_id"])
    crop_name = localized((kb.crop(row["crop"]) or {}).get("name"), lang) or row["crop"]
    conf_pct = int(round(row["confidence"] * 100))
    routed = row["status"] == "pending_review"

    if disease is None:  # healthy
        explanation = EXPLANATION["healthy"][lang].format(crop=crop_name, conf=conf_pct)
        disease_name = {"en": "Healthy", "bn": "সুস্থ", "hi": "स्वस्थ"}[lang]
        symptoms = ""
        pathogen = None
    else:
        plan = row.get("plan") or {}
        rec = next(
            (o for o in plan.get("options", []) if o["treatment_id"] == plan.get("recommended_treatment_id")),
            None,
        )
        forecast = row.get("forecast") or {}
        level = row.get("risk_level") or "moderate"
        explanation = EXPLANATION["disease"][lang].format(
            crop=crop_name,
            disease=localized(disease["name"], lang),
            conf=conf_pct,
            severity=_word(row["severity"], lang),
            level=_word(level, lang),
            action=forecast.get("action") or "",
            product=rec["product"] if rec else "-",
            qty=rec["total_quantity"] if rec else "-",
            unit=rec["unit"] if rec else "",
            size=plan.get("field_size_ha", "-"),
            symbol=(plan.get("currency") or {}).get("symbol", ""),
            cost=int(rec["cost_local"]) if rec else "-",
        )
        disease_name = localized(disease["name"], lang)
        symptoms = localized(disease["symptoms"], lang)
        pathogen = disease["pathogen"]

    if routed:
        explanation += EXPLANATION["review"][lang]

    alts = [
        {"disease_id": aid, "disease_name": localized((kb.disease(aid) or {}).get("name"), lang), "confidence": c}
        for aid, c in (alternatives or [])
    ]
    return {
        **row,
        "disease_name": disease_name,
        "pathogen": pathogen,
        "symptoms": symptoms,
        "routed_to_agronomist": routed,
        "alternatives": alts,
        "explanation": explanation,
    }
