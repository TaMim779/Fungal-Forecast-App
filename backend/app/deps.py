"""FastAPI dependency wiring (single place to swap implementations)."""

from __future__ import annotations

from fastapi import Depends, Header, HTTPException, Request

from .database import Database
from .services.classifier import LeafClassifier
from .services.knowledge import KnowledgeBase
from .services.weather import WeatherProvider


def get_db(request: Request) -> Database:
    return request.app.state.db


def get_kb(request: Request) -> KnowledgeBase:
    return request.app.state.kb


def get_classifier_dep(request: Request) -> LeafClassifier:
    return request.app.state.classifier


def get_weather(request: Request) -> WeatherProvider:
    return request.app.state.weather


def bearer_token(authorization: str | None = Header(default=None)) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Login required")
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(401, "Login required")
    return token


def current_farmer(token: str = Depends(bearer_token), db: Database = Depends(get_db)) -> dict:
    farmer = db.farmer_by_token(token)
    if not farmer:
        raise HTTPException(401, "Login required")
    return farmer
