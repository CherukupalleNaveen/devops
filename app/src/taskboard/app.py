"""Taskboard: a deliberately small Flask app, so the pipeline is the lesson."""
import os
import sqlite3
from importlib.metadata import PackageNotFoundError, version

from flask import Flask, g, jsonify, redirect, render_template, request, url_for

app = Flask(__name__)

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT    NOT NULL,
    done  INTEGER NOT NULL DEFAULT 0
)
"""


def app_version():
    """Read the version from the installed wheel's metadata.

    This is the whole point of the demo: the running site reports which
    build is live, so a deploy is visible in the browser.
    """
    try:
        return version("taskboard")
    except PackageNotFoundError:
        return "dev"


def get_db():
    # DB path is read per-request, never at import, so releases share one
    # database while the code itself stays immutable per release.
    db = getattr(g, "_db", None)
    if db is None:
        path = os.environ.get("TASKBOARD_DB", "taskboard.db")
        db = g._db = sqlite3.connect(path)
        db.row_factory = sqlite3.Row
        db.execute(SCHEMA)
        db.commit()
    return db


@app.teardown_appcontext
def close_db(_exc):
    db = getattr(g, "_db", None)
    if db is not None:
        db.close()


@app.get("/")
def index():
    rows = get_db().execute("SELECT * FROM tasks ORDER BY done, id DESC").fetchall()
    return render_template("index.html", tasks=rows, version=app_version())


@app.post("/tasks")
def add_task():
    title = (request.form.get("title") or "").strip()
    if not title:
        return redirect(url_for("index"))
    db = get_db()
    db.execute("INSERT INTO tasks (title) VALUES (?)", (title,))
    db.commit()
    return redirect(url_for("index"))


@app.post("/tasks/<int:task_id>/toggle")
def toggle_task(task_id):
    db = get_db()
    db.execute("UPDATE tasks SET done = 1 - done WHERE id = ?", (task_id,))
    db.commit()
    return redirect(url_for("index"))


@app.get("/api/tasks")
def api_tasks():
    rows = get_db().execute("SELECT * FROM tasks ORDER BY id").fetchall()
    return jsonify([dict(r) for r in rows])


@app.get("/health")
def health():
    """What the deploy script polls before declaring a release good."""
    get_db().execute("SELECT 1")
    return jsonify(status="ok", version=app_version())
