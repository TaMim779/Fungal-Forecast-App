# FungalForecast

Smallholder farmers lose 20–40% of staple crops to fungal disease. FungalForecast turns a phone
photo of a leaf plus hyperlocal humidity/temperature into a same-day disease-risk forecast and a
costed treatment plan, in the farmer's own language.

```
┌─────────────────────────┐        HTTPS/JSON        ┌─────────────────────────────┐
│  Flutter mobile app     │ ───────────────────────▶ │  FastAPI backend (Python)   │
│  Android / iOS / Web    │ ◀─────────────────────── │  SQLite · Open-Meteo        │
│  voice-first, offline   │                          │  risk engine · planner      │
│  cache, en/bn/hi        │                          │  outbreak map · ledger      │
└─────────────────────────┘                          └─────────────────────────────┘
```

| Part | Path | Stack | Tests |
|------|------|-------|-------|
| Mobile app | `mobile/` | Flutter 3.x, Dart 3, provider, go_router, flutter_map, flutter_tts | 18 widget/unit tests |
| Backend API | `backend/` | Python 3.11+, FastAPI, Pydantic v2, SQLite, httpx | 27 pytest tests |

> The ML model is intentionally **not** included. The backend ships a deterministic heuristic
> `LeafClassifier` so the whole product works end-to-end today; drop in a TFLite/ONNX model later
> (see [Swapping in a real model](#swapping-in-a-real-model)).

---

## Quick start (VS Code / Cursor)

### 0. Prerequisites

| Tool | Check | Notes |
|------|-------|-------|
| Python 3.11+ | `python --version` | <https://python.org> — tick *Add to PATH* |
| Flutter 3.x | `flutter doctor` | <https://docs.flutter.dev/get-started/install/windows> |
| Chrome | — | fastest way to run the app |
| Android Studio (optional) | `flutter doctor` shows Android toolchain ✓ | needed only for emulator / phone |

Open the folder in VS Code: **File → Open Folder → `D:\FungalForecast`**.
Accept the prompt to install the recommended extensions (Dart, Flutter, Python).

### 1. Start the backend

Terminal in VS Code (`` Ctrl+` ``):

```powershell
cd D:\FungalForecast\backend
python -m venv .venv                      # first time only
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt           # first time only
uvicorn app.main:app --reload --port 8000
```

or just run `.\run_backend.ps1` from the project root, or use **Terminal → Run Task → "Backend: run API"**.

- API: <http://localhost:8000/api/v1/health>
- Swagger docs: <http://localhost:8000/docs>

If PowerShell refuses to activate the venv:
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` (one time).

### 2. (Optional) Seed demo data

In a second terminal, with the backend running:

```powershell
cd D:\FungalForecast\backend
.\.venv\Scripts\python.exe scripts\seed_demo.py
```

This creates a demo farmer (Rahim Uddin, Savar, Bangladesh), neighbours with infected leaves
(so the outbreak map and community alert light up), a healthy case, a confirmed rice-blast case,
a low-confidence case in the agronomist queue and a ledger entry.

### 3. Run the mobile app

**Option A – Chrome (no Android setup needed)**

```powershell
cd D:\FungalForecast\mobile
flutter pub get
flutter run -d chrome
```

Or press **F5** in VS Code and pick **"Mobile: Chrome"** (or **"Full stack: Backend + Chrome"**
to start both at once). Hot reload: press `r` in the terminal or save a file.

**Option B – Android emulator**

```powershell
flutter emulators                  # list
flutter emulators --launch Pixel_9 # or create one in Android Studio > Device Manager
cd D:\FungalForecast\mobile
flutter run --dart-define=FF_API_URL=http://10.0.2.2:8000
```

`10.0.2.2` is how the emulator reaches your PC's `localhost`. In VS Code use the
**"Mobile: Android emulator"** launch config, or `.\run_mobile.ps1 android`.

**Option C – Real Android phone (USB)**

1. Enable *Developer options → USB debugging* on the phone, connect by USB, `flutter devices`.
2. Phone and PC must be on the same Wi-Fi. Find your PC IP: `ipconfig` → IPv4 Address.
3. `flutter run --dart-define=FF_API_URL=http://<PC-IP>:8000`
   (the backend is already bound to `0.0.0.0`; allow port 8000 through Windows Firewall).
4. You can also change the server URL at runtime in **Settings → Server URL**.

If `flutter doctor` complains about Android:

```powershell
# Android Studio > SDK Manager > SDK Tools > tick "Android SDK Command-line Tools", then:
flutter doctor --android-licenses
```

### 4. Run the tests

```powershell
cd D:\FungalForecast\backend; .\.venv\Scripts\python.exe -m pytest -q      # 27 passed
cd D:\FungalForecast\mobile;  flutter analyze; flutter test                # No issues, 18 passed
```

Or **Terminal → Run Test Task** in VS Code.

---

## Feature map

| # | Differentiator | Where it lives |
|---|----------------|----------------|
| 1 | On-device/offline leaf classifier (<3 s on a $60 Android) | `backend/app/services/classifier.py` defines the `LeafClassifier` protocol + heuristic stub; the app caches last diagnoses & forecasts in `mobile/lib/core/storage/local_store.dart` so Home works offline |
| 2 | Hyperlocal 5-day infection-risk forecast fusing photo + weather | `backend/app/services/weather.py` (Open-Meteo hourly → daily, leaf-wetness proxy) + `risk_engine.py` (temperature/humidity/wetness response, noisy-OR fusion with diagnosis prior) |
| 3 | Costed, locally sourced treatments with dosage by field size | `backend/app/services/treatment_planner.py`, `data/diseases.json`; UI in `mobile/lib/features/diagnose/result_screen.dart` |
| 4 | Voice-first, low-literacy, regional-language UI | `mobile/lib/core/services/tts_service.dart`, ARB files in `mobile/lib/l10n/` (en/bn/hi), big-button layouts, "Listen" on every result |
| 5 | Community outbreak map + pre-emptive alerts | `backend/app/routers/community.py` (`/outbreaks`, `/outbreaks/alerts`, 0.05° grid cells), `mobile/lib/features/outbreaks/outbreak_map_screen.dart` (OSM tiles) |
| 6 | Agro-dealer integration (stock + price nearby) | `backend/app/data/dealers.json`, `/dealers/nearby`, `mobile/lib/features/dealers/dealers_screen.dart` |
| 7 | Confidence scoring → human agronomist queue | `FF_AGRONOMIST_THRESHOLD` (0.70), `/agronomist/queue`, review endpoint, `mobile/lib/features/agronomist/agronomist_screen.dart` (Field-officer mode) |
| 8 | Yield-loss-averted ledger for microfinance/insurers | `/ledger/*` incl. CSV export, `mobile/lib/features/ledger/ledger_screen.dart` |

---

## Architecture

### Backend (`backend/app`)

```
main.py            create_app(): lifespan wiring, CORS, routers under /api/v1
config.py          Settings from FF_* env vars, supported languages, currency table
database.py        SQLite (WAL) – farmers, diagnoses, reviews, ledger_entries
schemas.py         Pydantic request/response contract
routers/
  core.py          /health /catalog /farmers /diagnose /diagnoses /forecast /treatments/plan
  community.py     /outbreaks /dealers/nearby /agronomist/queue /ledger
services/
  knowledge.py     disease / crop / treatment / dealer knowledge base (data/*.json)
  classifier.py    LeafClassifier protocol + HeuristicClassifier (non-ML placeholder)
  weather.py       OpenMeteoWeather (live) and MockWeather (offline, deterministic)
  risk_engine.py   per-disease infection risk model and 5-day forecast
  treatment_planner.py  dose × area × price → local currency, ROI, organic-first
  diagnosis.py     orchestration: image → prediction → forecast → plan → routing
  geo.py           haversine, grid cells
```

Diagnosis flow:

1. `POST /api/v1/diagnose` (multipart: `image`, `crop`, `lang`, `country`, `field_size_ha`, `lat`, `lon`, `farmer_id`)
2. Classifier returns `(disease_id, confidence, severity)` + alternatives
3. Weather provider fetches the 5-day hourly forecast for `lat/lon` (falls back to mock if offline)
4. Risk engine fuses weather risk with the diagnosis prior → daily risk, level, action text
5. Planner prices every treatment for the field size in the farmer's currency
6. Confidence < threshold → status `pending_review` and the case appears in the agronomist queue
7. Everything is stored in SQLite; the response is localized (`lang`)

Configuration: see `backend/.env.example`.

### Mobile (`mobile/lib`)

```
main.dart, app/            MaterialApp.router, go_router StatefulShellRoute, Material 3 theme
core/api/api_client.dart   typed HTTP client (multipart upload, timeouts, ApiException)
core/models/               Farmer, Diagnosis, Forecast, TreatmentPlan, OutbreakCell, Dealer, Ledger…
core/storage/local_store.dart  SharedPreferences: server URL, language, farmer, offline caches
core/services/tts_service.dart flutter_tts wrapper (language-aware)
core/state/                AppState (session/settings), HomeController (dashboard loading)
features/
  shell/        bottom-nav shell (Home · Diagnose · Outbreaks · Ledger · Settings)
  home/         risk outlook, community alert, recent diagnoses, big "Scan a leaf" CTA
  diagnose/     camera/gallery picker, crop & field size, result screen (voice, chart, plan)
  dealers/      nearby dealers with stock & prices for the recommended treatment
  outbreaks/    flutter_map with grid-cell heat markers and alerts
  ledger/       value-protected summary, entries, "I applied this" logging
  agronomist/   review queue (visible in Field-officer mode)
  settings/     language, server URL, farmer profile, field-officer toggle
l10n/           app_en.arb, app_bn.arb, app_hi.arb (gen-l10n)
```

---

## API reference (summary)

Base URL: `http://localhost:8000/api/v1` — interactive docs at `/docs`.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | liveness + version |
| GET | `/catalog?lang=` | crops, diseases, treatments, languages |
| POST | `/farmers` · GET `/farmers/{id}` | register / fetch farmer |
| POST | `/diagnose` | multipart leaf photo → diagnosis + forecast + plan |
| GET | `/diagnoses/{id}` · `/farmers/{id}/diagnoses` | fetch results |
| GET | `/forecast?disease=&lat=&lon=` | 5-day risk for one disease |
| GET | `/forecast/crop?crop=&lat=&lon=` | risk outlook for all diseases of a crop |
| GET | `/treatments/plan?disease=&field_size_ha=&country=` | costed plan without a photo |
| GET | `/outbreaks?lat=&lon=` · `/outbreaks/alerts` | community grid cells / alerts |
| GET | `/dealers/nearby?lat=&lon=&treatment_ids=` | dealers with stock and price |
| GET | `/agronomist/queue` · POST `/agronomist/queue/{id}/review` | human review loop |
| POST/GET | `/ledger/entries` · GET `/ledger/summary` · `/ledger/export.csv` | yield-loss-averted ledger |

---

## Swapping in a real model

`backend/app/services/classifier.py`:

```python
class LeafClassifier(Protocol):
    def predict(self, image_bytes: bytes, crop_hint: str | None = None) -> Prediction: ...
```

Implement this protocol with your TFLite/ONNX runtime (a `Prediction` carries the disease id,
confidence, severity and ranked alternatives) and return your class from `get_classifier()`. Nothing else changes — routing, forecast, planning and the
mobile app all work off the `Prediction` objects. For true on-device inference, add the same model
to the Flutter app (e.g. `tflite_flutter`) and call `/diagnose` with the predicted label so the
server only does weather fusion and planning.

---

## Project layout

```
D:\FungalForecast
├─ backend/           FastAPI service, tests, seed script, .env.example
├─ mobile/            Flutter app (android/, ios/, web/, lib/, test/)
├─ .vscode/           launch configs, tasks, recommended extensions
├─ run_backend.ps1    one-command backend start
├─ run_mobile.ps1     one-command app start (chrome | android | deviceId)
└─ README.md
```
