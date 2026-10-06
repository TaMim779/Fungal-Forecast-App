"""Lightweight SQLite persistence (stdlib only).

Tables: farmers, diagnoses, reviews, ledger_entries. A single connection with
a lock is sufficient for a prototype; swap for SQLAlchemy/Postgres in production.
"""

from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

SCHEMA = """
CREATE TABLE IF NOT EXISTS farmers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT NOT NULL UNIQUE,
    language TEXT NOT NULL DEFAULT 'en',
    country TEXT NOT NULL DEFAULT 'BD',
    crop TEXT NOT NULL DEFAULT 'rice',
    field_size_ha REAL NOT NULL DEFAULT 1.0,
    lat REAL, lon REAL,
    password_hash TEXT,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    farmer_id TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_farmer ON sessions(farmer_id);
CREATE TABLE IF NOT EXISTS diagnoses (
    id TEXT PRIMARY KEY,
    farmer_id TEXT,
    crop TEXT NOT NULL,
    disease_id TEXT NOT NULL,
    confidence REAL NOT NULL,
    severity TEXT NOT NULL,
    lesion_fraction REAL,
    lat REAL, lon REAL,
    status TEXT NOT NULL DEFAULT 'confirmed',  -- confirmed | pending_review | reviewed
    risk_level TEXT,
    peak_risk REAL,
    forecast_json TEXT,
    plan_json TEXT,
    model_version TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_diag_created ON diagnoses(created_at);
CREATE INDEX IF NOT EXISTS idx_diag_farmer ON diagnoses(farmer_id);
CREATE TABLE IF NOT EXISTS reviews (
    id TEXT PRIMARY KEY,
    diagnosis_id TEXT NOT NULL,
    reviewer TEXT NOT NULL,
    disease_id TEXT NOT NULL,
    severity TEXT NOT NULL,
    notes TEXT,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ledger_entries (
    id TEXT PRIMARY KEY,
    farmer_id TEXT NOT NULL,
    diagnosis_id TEXT NOT NULL,
    treatment_id TEXT NOT NULL,
    disease_id TEXT NOT NULL,
    crop TEXT NOT NULL,
    field_size_ha REAL NOT NULL,
    cost_local REAL NOT NULL,
    loss_averted_local REAL NOT NULL,
    currency TEXT NOT NULL,
    applied_on TEXT NOT NULL,
    created_at TEXT NOT NULL
);
"""


def utcnow() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


class Database:
    def __init__(self, path: str) -> None:
        self._conn = sqlite3.connect(path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._lock = threading.Lock()
        with self._lock:
            self._conn.executescript(SCHEMA)
            self._ensure_password_column()

    def close(self) -> None:
        self._conn.close()

    def _ensure_password_column(self) -> None:
        cols = {row[1] for row in self._conn.execute("PRAGMA table_info(farmers)")}
        if "password_hash" not in cols:
            self._conn.execute("ALTER TABLE farmers ADD COLUMN password_hash TEXT")
            self._conn.commit()

    @staticmethod
    def _public_farmer(row: dict[str, Any] | None) -> dict[str, Any] | None:
        if row is None:
            return None
        data = dict(row)
        data.pop("password_hash", None)
        return data

    # ---- helpers ------------------------------------------------------------
    def _execute(self, sql: str, params: tuple = ()) -> sqlite3.Cursor:
        with self._lock:
            cur = self._conn.execute(sql, params)
            self._conn.commit()
            return cur

    def _fetchall(self, sql: str, params: tuple = ()) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(r) for r in self._conn.execute(sql, params).fetchall()]

    def _fetchone(self, sql: str, params: tuple = ()) -> dict[str, Any] | None:
        with self._lock:
            row = self._conn.execute(sql, params).fetchone()
            return dict(row) if row else None

    # ---- farmers ------------------------------------------------------------
    def upsert_farmer(self, data: dict[str, Any]) -> dict[str, Any]:
        existing = self._fetchone("SELECT * FROM farmers WHERE phone = ?", (data["phone"],))
        if existing:
            self._execute(
                """UPDATE farmers SET name=?, language=?, country=?, crop=?, field_size_ha=?, lat=?, lon=?
                   WHERE id=?""",
                (
                    data["name"], data["language"], data["country"], data["crop"],
                    data["field_size_ha"], data.get("lat"), data.get("lon"), existing["id"],
                ),
            )
            return self.get_farmer(existing["id"])  # type: ignore[return-value]
        fid = new_id("frm")
        self._execute(
            """INSERT INTO farmers (id,name,phone,language,country,crop,field_size_ha,lat,lon,created_at)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (
                fid, data["name"], data["phone"], data["language"], data["country"], data["crop"],
                data["field_size_ha"], data.get("lat"), data.get("lon"), utcnow(),
            ),
        )
        return self.get_farmer(fid)  # type: ignore[return-value]

    def phone_taken(self, phone: str, except_id: str | None = None) -> bool:
        row = self._fetchone("SELECT id FROM farmers WHERE phone = ?", (phone,))
        return bool(row) and row["id"] != except_id

    def create_account(self, data: dict[str, Any], password_hash: str) -> dict[str, Any]:
        if self.phone_taken(data["phone"]):
            raise ValueError("phone_taken")
        fid = new_id("frm")
        self._execute(
            """INSERT INTO farmers (id,name,phone,language,country,crop,field_size_ha,lat,lon,password_hash,created_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
            (
                fid, data["name"], data["phone"], data["language"], data["country"], data["crop"],
                data["field_size_ha"], data.get("lat"), data.get("lon"), password_hash, utcnow(),
            ),
        )
        return self.get_farmer(fid)  # type: ignore[return-value]

    def update_farmer(self, farmer_id: str, data: dict[str, Any]) -> dict[str, Any] | None:
        if not self.get_farmer(farmer_id):
            return None
        if self.phone_taken(data["phone"], except_id=farmer_id):
            raise ValueError("phone_taken")
        self._execute(
            """UPDATE farmers SET name=?, phone=?, language=?, country=?, crop=?, field_size_ha=?, lat=?, lon=?
               WHERE id=?""",
            (
                data["name"], data["phone"], data["language"], data["country"], data["crop"],
                data["field_size_ha"], data.get("lat"), data.get("lon"), farmer_id,
            ),
        )
        return self.get_farmer(farmer_id)

    def set_password(self, farmer_id: str, password_hash: str) -> None:
        self._execute("UPDATE farmers SET password_hash=? WHERE id=?", (password_hash, farmer_id))

    def farmer_secret_by_phone(self, phone: str) -> dict[str, Any] | None:
        return self._fetchone("SELECT * FROM farmers WHERE phone = ?", (phone,))

    def create_session(self, farmer_id: str) -> str:
        from .security import new_token

        token = new_token()
        self._execute(
            "INSERT INTO sessions (token, farmer_id, created_at) VALUES (?,?,?)",
            (token, farmer_id, utcnow()),
        )
        return token

    def revoke_session(self, token: str) -> None:
        self._execute("DELETE FROM sessions WHERE token = ?", (token,))

    def farmer_by_token(self, token: str) -> dict[str, Any] | None:
        row = self._fetchone(
            """SELECT f.* FROM farmers f
               JOIN sessions s ON s.farmer_id = f.id
               WHERE s.token = ?""",
            (token,),
        )
        return self._public_farmer(row)
        fid = new_id("frm")
        self._execute(
            """INSERT INTO farmers (id,name,phone,language,country,crop,field_size_ha,lat,lon,created_at)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (
                fid, data["name"], data["phone"], data["language"], data["country"], data["crop"],
                data["field_size_ha"], data.get("lat"), data.get("lon"), utcnow(),
            ),
        )
        return self.get_farmer(fid)  # type: ignore[return-value]

    def get_farmer(self, farmer_id: str) -> dict[str, Any] | None:
        return self._public_farmer(self._fetchone("SELECT * FROM farmers WHERE id = ?", (farmer_id,)))

    # ---- diagnoses ----------------------------------------------------------
    def insert_diagnosis(self, d: dict[str, Any]) -> str:
        did = new_id("dx")
        self._execute(
            """INSERT INTO diagnoses (id,farmer_id,crop,disease_id,confidence,severity,lesion_fraction,lat,lon,
               status,risk_level,peak_risk,forecast_json,plan_json,model_version,created_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                did, d.get("farmer_id"), d["crop"], d["disease_id"], d["confidence"], d["severity"],
                d.get("lesion_fraction"), d.get("lat"), d.get("lon"), d["status"], d.get("risk_level"),
                d.get("peak_risk"), json.dumps(d.get("forecast")), json.dumps(d.get("plan")),
                d.get("model_version"), utcnow(),
            ),
        )
        return did

    def get_diagnosis(self, diagnosis_id: str) -> dict[str, Any] | None:
        row = self._fetchone("SELECT * FROM diagnoses WHERE id = ?", (diagnosis_id,))
        return self._inflate(row) if row else None

    def list_diagnoses(self, farmer_id: str, limit: int = 50) -> list[dict[str, Any]]:
        rows = self._fetchall(
            "SELECT * FROM diagnoses WHERE farmer_id = ? ORDER BY created_at DESC LIMIT ?",
            (farmer_id, limit),
        )
        return [self._inflate(r) for r in rows]

    def recent_diagnoses(self, days: int) -> list[dict[str, Any]]:
        since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
        rows = self._fetchall(
            """SELECT * FROM diagnoses WHERE created_at >= ? AND disease_id != 'healthy'
               AND lat IS NOT NULL AND lon IS NOT NULL ORDER BY created_at DESC""",
            (since,),
        )
        return [self._inflate(r) for r in rows]

    def pending_reviews(self) -> list[dict[str, Any]]:
        rows = self._fetchall(
            "SELECT * FROM diagnoses WHERE status = 'pending_review' ORDER BY created_at ASC"
        )
        return [self._inflate(r) for r in rows]

    def apply_review(self, diagnosis_id: str, review: dict[str, Any]) -> dict[str, Any] | None:
        if not self.get_diagnosis(diagnosis_id):
            return None
        self._execute(
            "INSERT INTO reviews (id,diagnosis_id,reviewer,disease_id,severity,notes,created_at) VALUES (?,?,?,?,?,?,?)",
            (
                new_id("rv"), diagnosis_id, review["reviewer"], review["disease_id"],
                review["severity"], review.get("notes"), utcnow(),
            ),
        )
        self._execute(
            "UPDATE diagnoses SET status='reviewed', disease_id=?, severity=?, confidence=1.0 WHERE id=?",
            (review["disease_id"], review["severity"], diagnosis_id),
        )
        return self.get_diagnosis(diagnosis_id)

    def update_diagnosis_plan(self, diagnosis_id: str, plan: dict[str, Any], forecast: list[dict]) -> None:
        self._execute(
            "UPDATE diagnoses SET plan_json=?, forecast_json=? WHERE id=?",
            (json.dumps(plan), json.dumps(forecast), diagnosis_id),
        )

    @staticmethod
    def _inflate(row: dict[str, Any]) -> dict[str, Any]:
        row = dict(row)
        row["forecast"] = json.loads(row.pop("forecast_json") or "null")
        row["plan"] = json.loads(row.pop("plan_json") or "null")
        return row

    # ---- ledger -------------------------------------------------------------
    def insert_ledger_entry(self, e: dict[str, Any]) -> dict[str, Any]:
        lid = new_id("led")
        self._execute(
            """INSERT INTO ledger_entries (id,farmer_id,diagnosis_id,treatment_id,disease_id,crop,field_size_ha,
               cost_local,loss_averted_local,currency,applied_on,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                lid, e["farmer_id"], e["diagnosis_id"], e["treatment_id"], e["disease_id"], e["crop"],
                e["field_size_ha"], e["cost_local"], e["loss_averted_local"], e["currency"],
                e["applied_on"], utcnow(),
            ),
        )
        return self._fetchone("SELECT * FROM ledger_entries WHERE id = ?", (lid,))  # type: ignore[return-value]

    def ledger_entries(self, farmer_id: str | None = None) -> list[dict[str, Any]]:
        if farmer_id:
            return self._fetchall(
                "SELECT * FROM ledger_entries WHERE farmer_id = ? ORDER BY applied_on DESC", (farmer_id,)
            )
        return self._fetchall("SELECT * FROM ledger_entries ORDER BY applied_on DESC")
