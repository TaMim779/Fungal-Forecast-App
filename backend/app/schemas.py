"""Pydantic request/response models (the public API contract)."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

Severity = Literal["none", "low", "moderate", "high", "severe"]
RiskLevel = Literal["low", "moderate", "high", "severe"]


# ---- farmers -----------------------------------------------------------------
class FarmerIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    phone: str = Field(min_length=6, max_length=20)
    language: str = "en"
    country: str = Field(default="BD", min_length=2, max_length=2)
    crop: str = "rice"
    field_size_ha: float = Field(default=1.0, gt=0, le=1000)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)


class Farmer(FarmerIn):
    id: str
    created_at: str


class RegisterIn(FarmerIn):
    password: str = Field(min_length=4, max_length=72)


class LoginIn(BaseModel):
    phone: str = Field(min_length=6, max_length=20)
    password: str = Field(min_length=1, max_length=72)


class AuthOut(BaseModel):
    token: str
    farmer: Farmer


# ---- forecast ----------------------------------------------------------------
class DayRiskOut(BaseModel):
    day: str
    risk: float
    level: RiskLevel
    weather_component: float
    diagnosis_component: float
    weather: dict[str, Any]


class ForecastSummary(BaseModel):
    peak_risk: float
    peak_level: RiskLevel
    peak_day: str | None
    mean_risk: float | None = None
    overall_level: RiskLevel


class ForecastOut(BaseModel):
    disease_id: str
    disease_name: str
    crop: str
    lat: float
    lon: float
    weather_provider: str
    days: list[DayRiskOut]
    summary: ForecastSummary
    action: str


# ---- treatment plan ----------------------------------------------------------
class TreatmentOption(BaseModel):
    treatment_id: str
    type: Literal["organic", "chemical"]
    product: str
    dose_per_ha: float
    unit: str
    quantity_per_application: float
    applications: int
    interval_days: int
    total_quantity: float
    pre_harvest_interval_days: int
    cost_usd: float
    cost_local: float
    value_protected_local: float
    net_benefit_local: float
    roi: float | None
    notes: str


class TreatmentPlan(BaseModel):
    disease_id: str
    disease_name: str
    crop: str
    field_size_ha: float
    currency: dict[str, str]
    expected_loss_local: float
    recommended_treatment_id: str
    options: list[TreatmentOption]


# ---- diagnosis ---------------------------------------------------------------
class DiagnosisOut(BaseModel):
    id: str
    farmer_id: str | None
    crop: str
    disease_id: str
    disease_name: str
    pathogen: str | None
    symptoms: str
    confidence: float
    severity: Severity
    lesion_fraction: float | None
    status: Literal["confirmed", "pending_review", "reviewed"]
    routed_to_agronomist: bool
    alternatives: list[dict[str, Any]] = []
    forecast: ForecastOut | None
    plan: TreatmentPlan | None
    explanation: str  # localized, read aloud by the app
    model_version: str | None
    created_at: str


# ---- outbreaks ---------------------------------------------------------------
class OutbreakCell(BaseModel):
    lat: float
    lon: float
    reports: int
    dominant_disease_id: str
    dominant_disease_name: str
    max_severity: Severity
    distance_km: float
    last_report_at: str


class OutbreakAlert(BaseModel):
    disease_id: str
    disease_name: str
    crop: str
    reports: int
    nearest_km: float
    message: str
    recommended_action: str


# ---- dealers -----------------------------------------------------------------
class DealerStockItem(BaseModel):
    treatment_id: str
    product: str
    in_stock: bool
    stock_qty: int
    price_local: float


class DealerOut(BaseModel):
    id: str
    name: str
    address: str
    phone: str
    lat: float
    lon: float
    distance_km: float
    opening_hours: str
    currency: str
    items: list[DealerStockItem]


# ---- agronomist --------------------------------------------------------------
class ReviewIn(BaseModel):
    reviewer: str = Field(min_length=1, max_length=80)
    disease_id: str
    severity: Severity
    notes: str | None = None


# ---- ledger ------------------------------------------------------------------
class LedgerEntryIn(BaseModel):
    farmer_id: str
    diagnosis_id: str
    treatment_id: str
    applied_on: str | None = None  # ISO date; defaults to today


class LedgerEntry(BaseModel):
    id: str
    farmer_id: str
    diagnosis_id: str
    treatment_id: str
    disease_id: str
    crop: str
    field_size_ha: float
    cost_local: float
    loss_averted_local: float
    currency: str
    applied_on: str
    created_at: str


class LedgerSummary(BaseModel):
    farmer_id: str | None
    entries: int
    total_cost_local: float
    total_loss_averted_local: float
    net_value_local: float
    currency: str | None
    by_disease: dict[str, dict[str, float]]
