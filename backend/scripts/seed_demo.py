"""Seed a running FungalForecast API with realistic demo data.

Creates one demo farmer plus three neighbouring farms near Savar (Dhaka), runs
synthetic leaf photos through /diagnose so the outbreak map, community alerts,
agronomist queue and impact ledger all have content, and prints the demo
farmer's profile (paste-able into the app's Settings screen).

Usage:
    python scripts/seed_demo.py [--base-url http://127.0.0.1:8000]
"""

from __future__ import annotations

import argparse
import io
import json
import sys

import httpx
from PIL import Image, ImageDraw

DEMO_LAT, DEMO_LON = 23.86, 90.27


def leaf_image(lesion_fraction: float, seed: int = 0, size: int = 256) -> bytes:
    """Synthetic leaf: green background with brown blotches covering ~lesion_fraction."""
    img = Image.new("RGB", (size, size), (46, 139, 50))
    draw = ImageDraw.Draw(img)
    # Vary the lesion colour/shape per seed so each photo hashes differently.
    n = int(lesion_fraction * 40) + 1
    for i in range(n):
        x = (seed * 37 + i * 53) % (size - 40)
        y = (seed * 91 + i * 29) % (size - 40)
        r = 14 + (i + seed) % 12
        draw.ellipse((x, y, x + r * 2, y + r * 2), fill=(150 + seed % 40, 90 + (i * 7) % 30, 30))
    draw.text((8, 8), f"demo-{seed}", fill=(230, 230, 230))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def register(client: httpx.Client, **farmer) -> dict:
    r = client.post("/api/v1/farmers", json=farmer)
    r.raise_for_status()
    return r.json()


def diagnose(client: httpx.Client, farmer: dict, image: bytes, lang: str = "en") -> dict:
    r = client.post(
        "/api/v1/diagnose",
        files={"image": ("leaf.png", image, "image/png")},
        data={
            "crop": farmer["crop"], "lang": lang, "country": farmer["country"],
            "field_size_ha": str(farmer["field_size_ha"]), "farmer_id": farmer["id"],
        },
    )
    r.raise_for_status()
    return r.json()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:8000")
    args = ap.parse_args()

    with httpx.Client(base_url=args.base_url, timeout=30) as c:
        health = c.get("/api/v1/health")
        health.raise_for_status()
        print("API:", health.json())

        demo = register(
            c, name="Rahim Uddin", phone="+8801711223344", language="bn", country="BD",
            crop="rice", field_size_ha=1.5, lat=DEMO_LAT, lon=DEMO_LON,
        )
        print(f"Demo farmer: {demo['id']} ({demo['name']})")

        # Neighbouring farms report disease -> community outbreak + pre-emptive alert.
        neighbours = []
        for i, (name, phone, dlat, dlon) in enumerate([
            ("Karim Mia", "+8801711000101", 0.004, 0.002),
            ("Salma Begum", "+8801711000102", -0.006, 0.005),
            ("Joynal Abedin", "+8801711000103", 0.002, -0.007),
            ("Fatema Khatun", "+8801711000104", 0.031, 0.028),
        ]):
            f = register(
                c, name=name, phone=phone, language="bn", country="BD", crop="rice",
                field_size_ha=0.8 + i * 0.3, lat=DEMO_LAT + dlat, lon=DEMO_LON + dlon,
            )
            dx = diagnose(c, f, leaf_image(0.45, seed=10 + i))
            neighbours.append((f, dx))
            print(f"  neighbour {name}: {dx['disease_name']} ({dx['confidence']:.0%}, {dx['severity']})")

        # Demo farmer: one healthy scan, one confirmed disease, one low-confidence case for the agronomist.
        healthy = diagnose(c, demo, leaf_image(0.0, seed=1))
        print(f"Demo farmer healthy scan: {healthy['disease_name']}")

        sick = None
        routed = None
        for seed in range(100, 160):
            dx = diagnose(c, demo, leaf_image(0.38, seed=seed))
            if dx["routed_to_agronomist"] and routed is None:
                routed = dx
            elif not dx["routed_to_agronomist"] and sick is None:
                sick = dx
            if sick and routed:
                break
        assert sick is not None
        print(f"Demo farmer disease: {sick['disease_name']} ({sick['confidence']:.0%}, {sick['severity']}) "
              f"risk={sick['forecast']['summary']['overall_level']}")
        if routed:
            print(f"Queued for agronomist: {routed['disease_name']} ({routed['confidence']:.0%})")

        # Farmer applied the recommended treatment -> impact ledger entry.
        rec = sick["plan"]["recommended_treatment_id"]
        led = c.post("/api/v1/ledger/entries", json={
            "farmer_id": demo["id"], "diagnosis_id": sick["id"], "treatment_id": rec,
        })
        led.raise_for_status()
        e = led.json()
        print(f"Ledger: cost {e['cost_local']:.0f} {e['currency']}, loss averted {e['loss_averted_local']:.0f} {e['currency']}")

        print("\nDemo farmer profile (JSON):")
        print(json.dumps(demo, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
