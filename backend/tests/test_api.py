"""End-to-end API tests covering the farmer journey."""

from .conftest import make_leaf

DHAKA = {"lat": 23.86, "lon": 90.27}


def _register(client, **over):
    body = {
        "name": "Rahim", "phone": "+8801700000000", "language": "bn", "country": "BD",
        "crop": "rice", "field_size_ha": 1.5, **DHAKA, **over,
    }
    r = client.post("/api/v1/farmers", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def _diagnose(client, image: bytes, farmer_id: str | None = None, **form):
    data = {"crop": "rice", "lang": "bn", "country": "BD", "field_size_ha": "1.5", **form}
    if farmer_id:
        data["farmer_id"] = farmer_id
    r = client.post("/api/v1/diagnose", files={"image": ("leaf.png", image, "image/png")}, data=data)
    assert r.status_code == 200, r.text
    return r.json()


def test_health_and_catalog(client):
    assert client.get("/api/v1/health").json()["status"] == "ok"
    cat = client.get("/api/v1/catalog", params={"lang": "bn"}).json()
    assert {c["id"] for c in cat["crops"]} >= {"rice", "wheat", "potato"}
    assert any(d["name"] == "ধানের ব্লাস্ট রোগ" for d in cat["diseases"])


def test_farmer_registration_is_idempotent_by_phone(client):
    a = _register(client)
    b = _register(client, name="Rahim Uddin")
    assert a["id"] == b["id"] and b["name"] == "Rahim Uddin"
    assert client.get("/api/v1/farmers/nope").status_code == 404


def test_healthy_leaf_flow(client, healthy_leaf):
    dx = _diagnose(client, healthy_leaf)
    assert dx["disease_id"] == "healthy"
    assert dx["plan"] is None and dx["forecast"] is None
    assert dx["routed_to_agronomist"] is False
    assert "সুস্থ" in dx["explanation"]


def test_sick_leaf_full_pipeline(client, sick_leaf):
    farmer = _register(client)
    dx = _diagnose(client, sick_leaf, farmer_id=farmer["id"])
    assert dx["disease_id"] != "healthy"
    assert dx["forecast"]["weather_provider"] == "mock"
    assert len(dx["forecast"]["days"]) == 5
    assert dx["plan"]["currency"]["code"] == "BDT"
    assert dx["plan"]["field_size_ha"] == 1.5
    assert dx["plan"]["recommended_treatment_id"] in {o["treatment_id"] for o in dx["plan"]["options"]}
    assert dx["explanation"]  # localized voice text
    # retrievable later, in another language
    again = client.get(f"/api/v1/diagnoses/{dx['id']}", params={"lang": "en"}).json()
    assert again["id"] == dx["id"] and again["disease_name"] != dx["disease_name"]
    hist = client.get(f"/api/v1/farmers/{farmer['id']}/diagnoses").json()
    assert [h["id"] for h in hist] == [dx["id"]]


def test_low_confidence_routes_to_agronomist_and_review_updates(client, kb):
    # Find a synthetic leaf whose stub confidence falls below the threshold.
    routed = None
    for seed in range(60):
        dx = _diagnose(client, make_leaf(0.4, seed=seed), lat=DHAKA["lat"], lon=DHAKA["lon"])
        if dx["routed_to_agronomist"]:
            routed = dx
            break
    assert routed is not None, "expected at least one low-confidence case"
    assert routed["status"] == "pending_review"

    queue = client.get("/api/v1/agronomist/queue").json()
    assert routed["id"] in {q["id"] for q in queue}

    r = client.post(
        f"/api/v1/agronomist/queue/{routed['id']}/review",
        json={"reviewer": "Dr. Karim", "disease_id": "rice_sheath_blight", "severity": "high", "notes": "ok"},
    )
    assert r.status_code == 200, r.text
    reviewed = r.json()
    assert reviewed["status"] == "reviewed"
    assert reviewed["disease_id"] == "rice_sheath_blight"
    assert reviewed["plan"]["disease_id"] == "rice_sheath_blight"
    assert reviewed["confidence"] == 1.0
    assert client.get("/api/v1/agronomist/queue").json() == [] or routed["id"] not in {
        q["id"] for q in client.get("/api/v1/agronomist/queue").json()
    }


def test_forecast_endpoints(client):
    r = client.get("/api/v1/forecast", params={**DHAKA, "disease_id": "rice_blast", "lang": "hi"})
    assert r.status_code == 200
    body = r.json()
    assert len(body["days"]) == 5 and body["summary"]["overall_level"] in ("low", "moderate", "high", "severe")
    assert body["disease_name"] == "धान का ब्लास्ट रोग"

    r = client.get("/api/v1/forecast/crop", params={**DHAKA, "crop": "rice"})
    assert r.status_code == 200
    items = r.json()["diseases"]
    assert {i["disease_id"] for i in items} == {"rice_blast", "rice_brown_spot", "rice_sheath_blight"}
    assert client.get("/api/v1/forecast", params={**DHAKA, "disease_id": "nope"}).status_code == 404


def test_treatment_plan_endpoint(client):
    r = client.get("/api/v1/treatments/plan", params={"disease_id": "wheat_leaf_rust", "field_size_ha": 2, "country": "IN"})
    assert r.status_code == 200
    plan = r.json()
    assert plan["currency"]["code"] == "INR" and len(plan["options"]) == 3


def test_outbreaks_and_alerts(client, sick_leaf):
    # Three neighbouring farms report disease; a fourth farmer nearby gets a pre-emptive alert.
    for i, phone in enumerate(["+880170000001", "+880170000002", "+880170000003"]):
        f = _register(client, phone=phone, lat=23.86 + i * 0.001, lon=90.27)
        _diagnose(client, sick_leaf, farmer_id=f["id"])

    cells = client.get("/api/v1/outbreaks", params={**DHAKA, "radius_km": 20}).json()
    assert cells and cells[0]["reports"] == 3
    assert cells[0]["dominant_disease_id"] != "healthy"

    newcomer = _register(client, phone="+880170000009", lat=23.87, lon=90.28)
    alerts = client.get(
        "/api/v1/outbreaks/alerts", params={**DHAKA, "farmer_id": newcomer["id"], "crop": "rice", "lang": "bn"}
    ).json()
    assert len(alerts) == 1 and alerts[0]["reports"] == 3
    assert "কিমি" in alerts[0]["message"]

    # Outside the radius: nothing.
    far = client.get("/api/v1/outbreaks", params={"lat": 30.9, "lon": 75.85, "radius_km": 20}).json()
    assert far == []


def test_dealers_nearby_with_stock_filter(client):
    r = client.get(
        "/api/v1/dealers/nearby",
        params={**DHAKA, "treatment_ids": "rb_chem_tricyclazole,rb_org_trichoderma", "radius_km": 30},
    )
    assert r.status_code == 200
    dealers = r.json()
    assert dealers and all(d["currency"] == "BDT" for d in dealers)
    assert all({i["treatment_id"] for i in d["items"]} <= {"rb_chem_tricyclazole", "rb_org_trichoderma"} for d in dealers)
    assert dealers == sorted(dealers, key=lambda d: (0 if any(i["in_stock"] for i in d["items"]) else 1, d["distance_km"]))


def test_ledger_flow(client, sick_leaf):
    farmer = _register(client)
    dx = _diagnose(client, sick_leaf, farmer_id=farmer["id"])
    tid = dx["plan"]["recommended_treatment_id"]

    r = client.post("/api/v1/ledger/entries", json={"farmer_id": farmer["id"], "diagnosis_id": dx["id"], "treatment_id": tid})
    assert r.status_code == 200, r.text
    entry = r.json()
    assert entry["currency"] == "BDT" and entry["loss_averted_local"] > 0

    summary = client.get("/api/v1/ledger/summary", params={"farmer_id": farmer["id"]}).json()
    assert summary["entries"] == 1
    assert summary["net_value_local"] == summary["total_loss_averted_local"] - summary["total_cost_local"]

    csv_text = client.get("/api/v1/ledger/export.csv").text
    assert csv_text.splitlines()[0].startswith("id,farmer_id")
    assert entry["id"] in csv_text

    # Mismatched treatment rejected.
    bad = client.post(
        "/api/v1/ledger/entries",
        json={"farmer_id": farmer["id"], "diagnosis_id": dx["id"], "treatment_id": "lr_org_sulfur"},
    )
    assert bad.status_code == 422


def test_diagnose_validation(client):
    r = client.post("/api/v1/diagnose", files={"image": ("x.png", b"garbage", "image/png")}, data={"crop": "rice"})
    assert r.status_code == 422
    r = client.post("/api/v1/diagnose", files={"image": ("x.png", make_leaf(0.1), "image/png")}, data={"crop": "banana"})
    assert r.status_code == 422
