"""Infection-risk engine.

Fuses (a) the disease's known environmental response (temperature window,
humidity threshold, leaf-wetness requirement) with the daily weather forecast,
and (b) the photo diagnosis (confidence + severity), which raises the prior
because inoculum is already present in the field.

The output is a 5-day risk curve with discrete levels and recommended actions.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .weather import DailyWeather

LEVELS = ("low", "moderate", "high", "severe")

ACTIONS: dict[str, dict[str, str]] = {
    "low": {
        "en": "No action needed. Keep scouting the field every 2-3 days.",
        "bn": "কোনো ব্যবস্থা লাগবে না। ২-৩ দিন পর পর জমি পর্যবেক্ষণ করুন।",
        "hi": "कोई कार्रवाई आवश्यक नहीं। हर 2-3 दिन में खेत की निगरानी करें।",
    },
    "moderate": {
        "en": "Apply a preventive (organic) spray and avoid excess nitrogen.",
        "bn": "প্রতিরোধমূলক (জৈব) স্প্রে দিন এবং অতিরিক্ত ইউরিয়া এড়িয়ে চলুন।",
        "hi": "रोकथाम हेतु (जैविक) छिड़काव करें और अधिक नाइट्रोजन से बचें।",
    },
    "high": {
        "en": "Treat within 48 hours. Use the recommended plan and inform neighbours.",
        "bn": "৪৮ ঘণ্টার মধ্যে চিকিৎসা করুন। সুপারিশকৃত পরিকল্পনা মেনে চলুন ও প্রতিবেশীদের জানান।",
        "hi": "48 घंटे के भीतर उपचार करें। सुझाई गई योजना अपनाएँ और पड़ोसियों को सूचित करें।",
    },
    "severe": {
        "en": "Urgent: spray today with a curative fungicide and remove badly infected plants.",
        "bn": "জরুরি: আজই নিরাময়মূলক ছত্রাকনাশক স্প্রে করুন এবং বেশি আক্রান্ত গাছ তুলে ফেলুন।",
        "hi": "अत्यावश्यक: आज ही उपचारात्मक फफूंदनाशी छिड़कें और गंभीर संक्रमित पौधे हटाएँ।",
    },
}


@dataclass(frozen=True)
class DayRisk:
    day: str
    risk: float  # 0..1
    level: str
    weather_component: float
    diagnosis_component: float
    weather: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "day": self.day,
            "risk": round(self.risk, 3),
            "level": self.level,
            "weather_component": round(self.weather_component, 3),
            "diagnosis_component": round(self.diagnosis_component, 3),
            "weather": self.weather,
        }


def level_for(risk: float) -> str:
    if risk < 0.25:
        return "low"
    if risk < 0.50:
        return "moderate"
    if risk < 0.75:
        return "high"
    return "severe"


def _clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def temperature_score(t: float, env: dict[str, float]) -> float:
    """Trapezoidal response: 0 outside [t_min,t_max], 1 within [t_opt_lo,t_opt_hi]."""
    t_min, lo, hi, t_max = env["t_min"], env["t_opt_lo"], env["t_opt_hi"], env["t_max"]
    if t <= t_min or t >= t_max:
        return 0.0
    if t < lo:
        return (t - t_min) / (lo - t_min)
    if t <= hi:
        return 1.0
    return (t_max - t) / (t_max - hi)


def humidity_score(rh: float, threshold: float) -> float:
    """Linear ramp from (threshold-12) -> 0 to (threshold+3) -> 1."""
    return _clamp((rh - (threshold - 12)) / 15.0)


def wetness_score(wet_hours: float, required_hours: float) -> float:
    if required_hours <= 0:
        return 1.0
    return _clamp(wet_hours / required_hours)


def weather_risk(day: DailyWeather, env: dict[str, float]) -> float:
    ts = temperature_score(day.t_mean, env)
    hs = humidity_score(day.rh_mean, env["rh_threshold"])
    ws = wetness_score(day.wet_hours, env["wetness_hours"])
    moisture = 0.6 * hs + 0.4 * ws
    return _clamp(ts * moisture)


SEVERITY_WEIGHT = {"none": 0.0, "low": 0.35, "moderate": 0.55, "high": 0.75, "severe": 0.9}


def diagnosis_prior(confidence: float, severity: str, spread_rate: float, day_index: int) -> float:
    """Inoculum already present raises risk; effect persists but decays slightly over days."""
    base = _clamp(confidence) * SEVERITY_WEIGHT.get(severity, 0.5)
    persistence = 0.85 + 0.15 * spread_rate  # fast-spreading pathogens persist longer
    return _clamp(base * persistence**day_index)


def build_forecast(
    disease: dict[str, Any],
    weather: list[DailyWeather],
    *,
    confidence: float = 0.0,
    severity: str = "none",
) -> list[DayRisk]:
    env = disease["environment"]
    spread = float(disease.get("spread_rate", 0.7))
    out: list[DayRisk] = []
    for i, day in enumerate(weather):
        w = weather_risk(day, env)
        d = diagnosis_prior(confidence, severity, spread, i)
        # Noisy-OR fusion: independent sources of infection pressure.
        risk = 1.0 - (1.0 - w) * (1.0 - d)
        out.append(
            DayRisk(
                day=day.day.isoformat(),
                risk=risk,
                level=level_for(risk),
                weather_component=w,
                diagnosis_component=d,
                weather=day.to_dict(),
            )
        )
    return out


def summarize(forecast: list[DayRisk]) -> dict[str, Any]:
    if not forecast:
        return {"peak_risk": 0.0, "peak_level": "low", "peak_day": None, "overall_level": "low"}
    peak = max(forecast, key=lambda d: d.risk)
    mean_risk = sum(d.risk for d in forecast) / len(forecast)
    # Overall is the worse of the mean level and the peak-minus-one-step, so a single
    # severe day is not hidden by four low days.
    overall_idx = max(LEVELS.index(level_for(mean_risk)), LEVELS.index(peak.level) - 1)
    return {
        "peak_risk": round(peak.risk, 3),
        "peak_level": peak.level,
        "peak_day": peak.day,
        "mean_risk": round(mean_risk, 3),
        "overall_level": LEVELS[overall_idx],
    }


def action_for(level: str, lang: str) -> str:
    return ACTIONS.get(level, ACTIONS["low"]).get(lang, ACTIONS[level]["en"])
