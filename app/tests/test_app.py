import pytest

from taskboard.app import app


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("TASKBOARD_DB", str(tmp_path / "test.db"))
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_health_ok(client):
    body = client.get("/health").get_json()
    assert body["status"] == "ok"
    assert body["version"]


def test_index_renders(client):
    r = client.get("/")
    assert r.status_code == 200
    assert b"Taskboard" in r.data


def test_add_then_list(client):
    client.post("/tasks", data={"title": "ship the pipeline"})
    tasks = client.get("/api/tasks").get_json()
    assert [t["title"] for t in tasks] == ["ship the pipeline"]
    assert tasks[0]["done"] == 0


def test_blank_title_rejected(client):
    client.post("/tasks", data={"title": "   "})
    assert client.get("/api/tasks").get_json() == []


def test_toggle_flips_done(client):
    client.post("/tasks", data={"title": "flip me"})
    tid = client.get("/api/tasks").get_json()[0]["id"]
    client.post(f"/tasks/{tid}/toggle")
    assert client.get("/api/tasks").get_json()[0]["done"] == 1
    client.post(f"/tasks/{tid}/toggle")
    assert client.get("/api/tasks").get_json()[0]["done"] == 0
