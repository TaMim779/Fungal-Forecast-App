from datetime import date

import pytest

from app.services import risk_engine
from app.services.classifier import HeuristicClassifier
from app.services.geo import grid_cell, haversine_km
from app.services.treatment_planner import build_plan
from app.services.weather import DailyWeather, MockWeather

from .conftest import make_leaf


def _day(t_mean: float, rh: float, wet: int, rain: float = 0.0) -> DailyWeather:
    return DailyWeather(date(2026, 10, 6), t_mean - 4, t_mean + 4, t_mean, rh, min(100, rh + 6), rain, wet)


# ---- geo ---------------------------------------------------------------------
def test_haversine_known_distance():
    # Dhaka -> Chattogram is ~215 km
    assert 205 < haversine_km(23.8103, 90.4125, 22.3569, 91.7832) < 225


def test_grid_cell_snaps_to_centre():
    assert grid_cell(23.8583, 90.2667) == (23.875, 90.275)
    assert grid_cell(23.8583, 90.2667) == grid_cell(23.86, 90.27)


# ---- risk engine ---------------------------------------------------------------
def test_temperature_trapezoid(kb):
    env = kb.disease("rice_blast")["environment"]
    assert risk_engine.temperature_score(26, env) == 1.0
    assert risk_engine.temperature_score(10, env) == 0.0
    assert 0 < risk_engine.temperature_score(20, env) < 1


def test_hot_humid_wet_days_are_high_risk(kb):
    blast = kb.disease("rice_blast")
    days = [_day(26, 95, 14, 8.0) for _ in range(5)]
    fc = risk_engine.build_forecast(blast, days)
    assert all(d.level in ("high", "severe") for d in fc)


def test_dry_cool_days_are_low_risk(kb):
    blast = kb.disease("rice_blast")
    days = [_day(14, 50, 0) for _ in range(5)]
    fc = risk_engine.build_forecast(blast, days)
    assert all(d.level == "low" for d in fc)


def test_diagnosis_raises_risk(kb):
    blast = kb.disease("rice_blast")
    days = [_day(22, 75, 3) for _ in range(5)]
    without = risk_engine.build_forecast(blast, days)
    with_dx = risk_engine.build_forecast(blast, days, confidence=0.9, severity="high")
    assert with_dx[0].risk > without[0].risk
    assert with_dx[0].diagnosis_component > with_dx[4].diagnosis_component  # decays


def test_summary_flags_single_severe_day(kb):
    blast = kb.disease("rice_blast")
    days = [_day(14, 50, 0)] * 4 + [_day(26, 97, 16, 12.0)]
    fc = risk_engine.build_forecast(blast, days)
    s = risk_engine.summarize(fc)
    assert s["peak_level"] in ("high", "severe")
    assert s["overall_level"] != "low"


def test_actions_localized():
    assert "ঘণ্টার" in risk_engine.action_for("high", "bn")
    assert risk_engine.action_for("high", "xx") == risk_engine.action_for("high", "en")


# ---- weather -----------------------------------------------------------------
@pytest.mark.anyio
async def test_mock_weather_is_deterministic():
    w = MockWeather()
    a = await w.forecast(23.8, 90.4, 5)
    b = await w.forecast(23.8, 90.4, 5)
    assert len(a) == 5 and a == b
    assert all(0 <= d.wet_hours <= 24 and 0 <= d.rh_mean <= 100 for d in a)


# ---- treatment planner ---------------------------------------------------------
def test_plan_scales_with_field_size_and_currency(kb):
    p1 = build_plan(kb, "rice_blast", field_size_ha=1.0, country="BD", lang="en")
    p2 = build_plan(kb, "rice_blast", field_size_ha=2.0, country="BD", lang="en")
    assert p1["currency"]["code"] == "BDT"
    o1 = {o["treatment_id"]: o for o in p1["options"]}
    o2 = {o["treatment_id"]: o for o in p2["options"]}
    for tid in o1:
        assert o2[tid]["total_quantity"] == pytest.approx(o1[tid]["total_quantity"] * 2, rel=0.01)
        assert o2[tid]["cost_local"] == pytest.approx(o1[tid]["cost_local"] * 2, rel=0.01)


def test_plan_prefers_organic_when_risk_low_and_chemical_when_severe(kb):
    low = build_plan(kb, "rice_blast", field_size_ha=1, country="BD", lang="en", risk_level="low")
    sev = build_plan(kb, "rice_blast", field_size_ha=1, country="BD", lang="en", risk_level="severe", severity="severe")
    assert kb.treatment(low["recommended_treatment_id"])["type"] == "organic"
    assert kb.treatment(sev["recommended_treatment_id"])["type"] == "chemical"
    assert low["options"][0]["type"] == "organic"  # organic listed first


def test_plan_localizes_notes(kb):
    p = build_plan(kb, "rice_blast", field_size_ha=1, country="IN", lang="hi")
    assert p["currency"]["code"] == "INR"
    assert p["disease_name"] == "धान का ब्लास्ट रोग"


def test_plan_rejects_bad_input(kb):
    with pytest.raises(KeyError):
        build_plan(kb, "nope", field_size_ha=1, country="BD", lang="en")
    with pytest.raises(ValueError):
        build_plan(kb, "rice_blast", field_size_ha=0, country="BD", lang="en")


# ---- classifier stub -------------------------------------------------------------
def test_classifier_healthy_vs_sick(kb):
    clf = HeuristicClassifier(kb)
    healthy = clf.predict(make_leaf(0.0), "rice")
    sick = clf.predict(make_leaf(0.5), "rice")
    assert healthy.disease_id == "healthy" and healthy.severity == "none"
    assert sick.disease_id in {d["id"] for d in kb.diseases("rice")}
    assert sick.severity in ("high", "severe")
    assert 0.5 <= sick.confidence <= 1.0


def test_classifier_is_deterministic(kb):
    clf = HeuristicClassifier(kb)
    img = make_leaf(0.3, seed=7)
    assert clf.predict(img, "wheat") == clf.predict(img, "wheat")


def test_classifier_rejects_garbage(kb):
    with pytest.raises(ValueError):
        HeuristicClassifier(kb).predict(b"not an image")
