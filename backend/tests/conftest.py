import io
import os

import pytest
from fastapi.testclient import TestClient
from PIL import Image

# Force deterministic offline weather before the app module is imported.
os.environ["FF_WEATHER_PROVIDER"] = "mock"

from app.main import create_app  # noqa: E402
from app.services.knowledge import get_knowledge_base  # noqa: E402


@pytest.fixture()
def kb():
    return get_knowledge_base()


@pytest.fixture()
def client(tmp_path):
    app = create_app(database_path=str(tmp_path / "test.db"))
    with TestClient(app) as c:
        yield c


def make_leaf(lesion_fraction: float, seed: int = 0, size: int = 64) -> bytes:
    """Synthetic 'leaf': green pixels with a brown patch covering `lesion_fraction` of the area."""
    img = Image.new("RGB", (size, size), (40, 150, 40))
    n_lesion = int(size * size * lesion_fraction)
    px = img.load()
    count = 0
    for y in range(size):
        for x in range(size):
            if count >= n_lesion:
                break
            px[x, y] = (150 + seed % 20, 90, 30)
            count += 1
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture()
def healthy_leaf():
    return make_leaf(0.0)


@pytest.fixture()
def sick_leaf():
    return make_leaf(0.40, seed=3)
