"""FungalForecast API entrypoint.

Run locally:  uvicorn app.main:app --reload --port 8000
Docs:         http://localhost:8000/docs
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import __version__
from .config import settings
from .database import Database
from .routers import community, core
from .services.classifier import get_classifier
from .services.knowledge import get_knowledge_base
from .services.weather import get_weather_provider

logging.basicConfig(level=logging.DEBUG if settings.debug else logging.INFO)


def create_app(database_path: str | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        kb = get_knowledge_base()
        app.state.kb = kb
        app.state.db = Database(database_path or settings.database_path)
        app.state.classifier = get_classifier(kb)
        app.state.weather = get_weather_provider()
        try:
            yield
        finally:
            app.state.db.close()

    app = FastAPI(
        title=settings.app_name,
        version=__version__,
        description=(
            "Turns a leaf photo + hyperlocal weather into a same-day fungal disease risk "
            "forecast and a costed treatment plan for smallholder farmers."
        ),
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(core.router, prefix="/api/v1")
    app.include_router(community.router, prefix="/api/v1")
    return app


app = create_app()
