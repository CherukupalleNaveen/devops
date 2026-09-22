# Demo change #1 — add a search box, ship it through the pipeline

A visible UI change your audience can see land in the browser. Four small edits,
all copy-paste. No database changes, so nothing can go sideways on stage.

**Rehearse this once before presenting.** Total typing time: about 2 minutes.

---

## Edit 1 of 4 — bump the version

**File: `app/pyproject.toml`** — so the footer visibly changes when it deploys.

Find:

```toml
version = "1.0.0"
```

Replace with:

```toml
version = "1.1.0"
```

---

## Edit 2 of 4 — filter the task list

**File: `app/src/taskboard/app.py`** — replace the whole `index()` function.

Find:

```python
@app.get("/")
def index():
    rows = get_db().execute("SELECT * FROM tasks ORDER BY done, id DESC").fetchall()
    return render_template("index.html", tasks=rows, version=app_version())
```

Replace with:

```python
@app.get("/")
def index():
    q = (request.args.get("q") or "").strip()
    if q:
        rows = get_db().execute(
            "SELECT * FROM tasks WHERE title LIKE ? ORDER BY done, id DESC", (f"%{q}%",)
        ).fetchall()
    else:
        rows = get_db().execute("SELECT * FROM tasks ORDER BY done, id DESC").fetchall()
    return render_template("index.html", tasks=rows, version=app_version(), q=q)
```

> The `?` placeholder is not decoration — it is how you avoid SQL injection.
> Never build SQL by pasting user input into a string.

---

## Edit 3 of 4 — the text box itself

**File: `app/src/taskboard/templates/index.html`**

**(a)** Find this line:

```html
  <form class="add" method="post" action="/tasks">
```

Paste this **directly above** it (leave the `form class="add"` line in place):

```html
  <form class="search" method="get" action="/">
    <input type="text" name="q" value="{{ q }}" placeholder="Search tasks...">
    <button type="submit">Search</button>
    {% if q %}<a href="/">clear</a>{% endif %}
  </form>

```

**(b)** Find this CSS line:

```css
    form.add { display: flex; gap: .5rem; margin-bottom: 1.5rem; }
```

Replace with:

```css
    form.add, form.search { display: flex; gap: .5rem; margin-bottom: 1.5rem; align-items: center; }
    form.search a { font-size: .85rem; color: #888; }
```

---

## Edit 4 of 4 — a test for the new behaviour

**File: `app/tests/test_app.py`** — append at the end of the file:

```python
def test_search_filters_list(client):
    client.post("/tasks", data={"title": "buy milk"})
    client.post("/tasks", data={"title": "write pipeline"})
    assert b"buy milk" in client.get("/?q=milk").data
    assert b"write pipeline" not in client.get("/?q=milk").data
    # no query returns everything
    assert b"write pipeline" in client.get("/").data
```

> Adding the test matters for the demo, not just for correctness: it is what
> lets you say "the pipeline verified my new feature before shipping it."

---

## Ship it

```bash
./ci/ci.sh all        # optional: prove it locally on :8081 first
git commit -am "add task search box"
```

Then in Jenkins: **Build Now** → watch the stages go green → open
**http://localhost:8000** and the search box is there, footer reads **1.1.0**.

Add a few tasks, search for one, click **clear**. The tasks you added before the
deploy are still there — new code, same database.

---

## If you would rather not type it live

The identical change is saved as a patch:

```bash
git apply demo/01-search-box.patch
```

Handy as a fallback if a live edit goes wrong mid-demo.

## Undo afterwards

```bash
git reset --hard demo-start
```
