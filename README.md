# Jenkins CI/CD Demo — shell-driven pipeline, GitHub webhook on merge to main

A word-frequency Python app. Jenkins runs in Docker Compose. The pipeline is a
thin `Jenkinsfile` that shells out to `ci/ci.sh` — all real logic lives in the
shell script, which calls Python. Same script runs locally and in CI.

```
docker-compose.yml   Jenkins (+ optional ngrok tunnel)
jenkins/Dockerfile   jenkins:lts-jdk17 + python3 + plugins
app/                 the app under test (app.py, test_app.py)
ci/ci.sh             the CI/CD logic: setup | test | build | deploy | all
Jenkinsfile          stage orchestration only
```

Prove the script works with no Jenkins at all:

```bash
./ci/ci.sh all
```

---

## 1. Install Jenkins

```bash
docker compose up -d --build
```

First boot takes ~2 min (plugin download). Get the unlock password:

```bash
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Open http://localhost:8080 → paste the password → **Select plugins to install**
→ **None** (the image already ships them) → create your admin user.

## 2. Expose Jenkins to GitHub

GitHub can't reach `localhost`. Start the tunnel:

```bash
cp .env.example .env     # put your ngrok authtoken in it
docker compose --profile tunnel up -d
open http://localhost:4040    # copy the https URL shown
```

Put that URL in `.env` as `JENKINS_URL`, then:

```bash
docker compose up -d
```

Also set it in the UI: **Manage Jenkins → System → Jenkins URL**.

## 3. Push this project to GitHub

```bash
git init -b main && git add -A && git commit -m "Jenkins CI/CD demo"
gh repo create jenkins-cicd-demo --private --source=. --push
```

## 4. Create the pipeline job

**New Item** → name `demo-pipeline` → **Pipeline** → OK.

- **GitHub project**: your repo URL
- **Build Triggers**: ✅ *GitHub hook trigger for GITScm polling*
- **Pipeline** → Definition: *Pipeline script from SCM*
  - SCM: Git, Repository URL: your repo, Credentials: a GitHub PAT (`repo` scope)
  - Branch Specifier: `*/main`
  - Script Path: `Jenkinsfile`
- Save, then **Build Now** once (Jenkins must read the `Jenkinsfile` before the
  `triggers` block is registered — this is the classic "first build is manual").

## 5. Wire the webhook

GitHub repo → **Settings → Webhooks → Add webhook**

- Payload URL: `https://your-id.ngrok-free.app/github-webhook/`  ← trailing slash matters
- Content type: `application/json`
- Events: *Just the push event*

Green check on **Recent Deliveries** = wired.

## 6. Demo the merge → build

```bash
git checkout -b feature/better-tokenizer
# edit app/app.py or app/test_app.py
git commit -am "tweak tokenizer" && git push -u origin feature/better-tokenizer
gh pr create --fill && gh pr merge --squash --delete-branch
```

The merge is a push to `main` → GitHub fires the webhook → Jenkins builds:
Setup → Test → Build → **Deploy** (only on main).

**Show the failure path too:** break a test on a branch, merge it, watch the
pipeline go red and Deploy get skipped.

---

## Talking points

- `Jenkinsfile` is orchestration; `ci/ci.sh` is the build. Keeps CI portable —
  if you leave Jenkins, the script comes with you.
- `set -euo pipefail` — any failing command fails the stage.
- Jenkins injects `BUILD_NUMBER` / `GIT_BRANCH`; the script falls back to
  `local` so the same commands work on your laptop.
- The `when { IS_MAIN }` guard is why a PR branch can test but never deploy.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Webhook 403 | Jenkins URL in **Manage Jenkins → System** must match the ngrok URL |
| Push ignored | Run **Build Now** once so the `githubPush()` trigger registers |
| `python3: not found` | Rebuild: `docker compose up -d --build` |
| ngrok URL changed | Free ngrok rotates URLs on restart — update `.env` + the webhook |

```bash
docker compose logs -f jenkins
```
