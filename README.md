# Jenkins CI/CD Demo — build a Python web app, deploy it, roll it back

**Taskboard** is a small Flask app. Jenkins lints it, tests it, builds a
**wheel** (`.whl` — the Python equivalent of a `.war`), installs that wheel into
a fresh release directory, flips a symlink, restarts gunicorn, and polls
`/health`. If health fails, it rolls back automatically.

No GitHub needed — Jenkins clones from the local git repo over a `file://` URL.

```
docker-compose.yml   Jenkins, ports 8080 (UI) + 8000 (the deployed site)
jenkins/Dockerfile   jenkins:lts-jdk17 + python3 + plugins
app/                 the Flask app + tests + pyproject.toml (the buildable unit)
ci/ci.sh             ALL the CI/CD logic - setup|lint|test|build|deploy|rollback
Jenkinsfile          stage orchestration only, ~40 lines
```

## Why it is shaped this way

**Nobody deploys `.pyc` files.** The real Python deployable is a wheel: a
versioned, installable archive with declared dependencies and metadata. That is
what `./ci/ci.sh build` produces and what Jenkins archives as the build artifact.

**Jenkins orchestrates; the shell script builds.** The `Jenkinsfile` only names
stages and calls `ci/ci.sh`. That is deliberate and it is what mature shops do:

- you can run the exact production pipeline on your laptop — `./ci/ci.sh all`
- debugging does not require a Jenkins job, a commit, or a queue slot
- if you migrate to GitLab CI / GitHub Actions, the script comes with you and
  only the ~40-line orchestration file is rewritten

The anti-pattern is 300 lines of Groovy in a `Jenkinsfile` that can only ever
run inside Jenkins.

**The deploy is the classic release-directory pattern**, the same one Capistrano
and Ansible have used on VMs for fifteen years:

```
deploy/
  releases/
    12/venv/...      <- immutable: a venv with the wheel installed
    13/venv/...
  shared/taskboard.db  <- the database, outlives every release
  current -> releases/13
  previous -> releases/12
```

Releases are never patched in place, only replaced. Data lives outside them.
Rollback is a symlink flip plus a restart, which is why it takes a second.

---

## 1. Start Jenkins

```bash
docker compose up -d --build
```

Unlock password:

```bash
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

http://localhost:8080 → paste it → **Select plugins to install → None**
(they are already baked into the image) → create your admin user.

## 2. Create the pipeline job

**New Item** → name `taskboard-deploy` → **Pipeline** → OK.

- ✅ **This project is parameterised** is set automatically by the `Jenkinsfile`
  after the first run.
- **Pipeline** → Definition: **Pipeline script from SCM**
  - SCM: **Git**
  - Repository URL: `file:///srv/repo`   ← the bind-mounted project, no credentials
  - Branch Specifier: `*/main`
  - Script Path: `Jenkinsfile`
- Save → **Build Now**

Watch the stages: Setup → Lint → Test → Build → Deploy.

Then open **http://localhost:8000** — Taskboard is live, and the page footer
shows the deployed version.

## 3. Demo a code change going live

```bash
# bump the version so the change is visible in the browser
sed -i '' 's/version = "1.0.0"/version = "1.1.0"/' app/pyproject.toml
git commit -am "release 1.1.0"
```

**Build Now** again. Add a task before rebuilding and note it is still there
afterwards — new code, same database. That is the `shared/` directory doing its
job.

## 4. Demo the safety net (the part that sells it)

Break a test and build:

```bash
sed -i '' 's/assert tasks\[0\]\["done"\] == 0/assert tasks[0]["done"] == 99/' app/tests/test_app.py
git commit -am "break a test"
```

Build Now → **Test fails, Deploy never runs, the site stays on the last good
release.** Bad code cannot reach the site.

Now break it at *runtime* instead — something tests cannot catch:

```bash
git revert --no-edit HEAD                       # fix the test
sed -i '' '1a import module_that_does_not_exist' app/src/taskboard/app.py
git commit -am "runtime breakage"
```

Build Now → tests pass, the wheel builds, gunicorn starts and dies, `/health`
never answers → **automatic rollback to the previous release**, and the job goes
red. The site never goes down. Verified working.

Manual rollback is also a button: **Build with Parameters → ROLLBACK ✅**.

## 5. Useful commands

```bash
./ci/ci.sh all        # run the whole pipeline locally, no Jenkins
./ci/ci.sh status     # what is live right now
docker compose exec jenkins /var/jenkins_home/workspace/taskboard-deploy/ci/ci.sh status
docker compose logs -f jenkins
```

---

## How this maps to real industry setups

This demo is rung one. The ladder above it, in the order shops actually climb it:

| Rung | What changes | Why |
|---|---|---|
| **This demo** | wheel → release dir → gunicorn restart on one box | the mechanics, visible end to end |
| **+ SCM trigger** | webhook or poll replaces *Build Now* | merges deploy themselves |
| **+ artifact repo** | wheel pushed to Nexus/Artifactory/CodeArtifact | one build, promoted across envs — never rebuilt per environment |
| **+ containers** | `docker build` → registry → `docker run` | the venv-on-a-box step disappears |
| **+ orchestrator** | `kubectl set image` / Helm / ECS | rollback and health checks become the platform's job |
| **+ environments** | dev → staging → prod, prod behind manual approval | `input` step in the `Jenkinsfile` |

Two things stay identical at every rung, which is the real lesson:

1. **Build the artifact exactly once**, then promote that same artifact forward.
   Rebuilding per environment means prod runs bits nobody tested.
2. **Every deploy is health-checked and reversible.** The rollback path must be
   tested, not theoretical — that is why step 4 above is in the demo.

## Gotchas worth calling out while teaching

- **Jenkins kills background processes.** `ProcessTreeKiller` reaps anything a
  build leaves running, so gunicorn would die the moment the job goes green.
  `ci/ci.sh` exports `JENKINS_NODE_COOKIE=dontKillMe` to opt out. This bites
  everyone once.
- **Named volumes mask image files.** `git config --global` baked into the image
  vanished under the `jenkins_home` volume; it had to be `--system`.
- **The first build of an SCM pipeline is always manual** — Jenkins has to read
  the `Jenkinsfile` before it knows what triggers or parameters exist.
- **`set -euo pipefail`** is why a failing command fails the stage instead of
  silently continuing into a deploy.
