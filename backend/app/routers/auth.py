"""Phone + password registration and login."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ..database import Database
from ..deps import bearer_token, current_farmer, get_db, get_kb
from ..schemas import AuthOut, Farmer, LoginIn, RegisterIn
from ..security import hash_password, verify_password
from ..services.knowledge import KnowledgeBase, normalize_lang

router = APIRouter(prefix="/auth", tags=["auth"])


def _prepare(body: RegisterIn, kb: KnowledgeBase) -> dict:
    if body.crop not in kb.crops():
        raise HTTPException(422, f"Unknown crop '{body.crop}'")
    data = body.model_dump(exclude={"password"})
    data["language"] = normalize_lang(body.language)
    data["country"] = body.country.upper()
    data["phone"] = body.phone.strip()
    return data


@router.post("/register", response_model=AuthOut)
def register(body: RegisterIn, db: Database = Depends(get_db), kb: KnowledgeBase = Depends(get_kb)):
    data = _prepare(body, kb)
    existing = db.farmer_secret_by_phone(data["phone"])
    if existing and existing.get("password_hash"):
        raise HTTPException(409, "This phone number is already registered")
    if existing:
        # Profile saved before accounts existed: attach a password and sign in.
        try:
            farmer = db.update_farmer(existing["id"], data)
        except ValueError as exc:
            raise HTTPException(409, "This phone number is already registered") from exc
        db.set_password(existing["id"], hash_password(body.password))
    else:
        farmer = db.create_account(data, hash_password(body.password))
    token = db.create_session(farmer["id"])
    return {"token": token, "farmer": farmer}


@router.post("/login", response_model=AuthOut)
def login(body: LoginIn, db: Database = Depends(get_db)):
    row = db.farmer_secret_by_phone(body.phone.strip())
    if not row or not verify_password(body.password, row.get("password_hash")):
        raise HTTPException(401, "Wrong phone number or password")
    farmer = db.get_farmer(row["id"])
    token = db.create_session(row["id"])
    return {"token": token, "farmer": farmer}


@router.get("/me", response_model=Farmer)
def me(farmer: dict = Depends(current_farmer)):
    return farmer


@router.post("/logout")
def logout(token: str = Depends(bearer_token), db: Database = Depends(get_db)):
    db.revoke_session(token)
    return {"ok": True}
