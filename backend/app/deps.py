"""FastAPI dependency wiring (single place to swap implementations)."""

from __future__ import annotations

from fastapi import Request

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
