# Jenkins CI/CD — Demo Script & Practice Guide

Two documents in one.

- **Presenter:** run the numbered acts top to bottom. Every command is
  copy-paste. **SAY** blocks are what to explain at that moment.
- **Learner:** read the **SAY** and **WHY** blocks as the lesson, then run the
  same commands yourself. Exercises are at the end.

Total demo time: **25–30 minutes**. Acts 1–6 alone make a solid 15-minute version.

> Commands are written for **macOS**. On Linux, change every `sed -i ''` to
> `sed -i` (no quotes). Everything else is identical.

---

## Pre-flight (do this 5 minutes before, not in front of your audience)

```bash
cd ~/workspace/local/teaching/personal/jenkins-demo
docker compose up -d --build
```

Wait for Jenkins, then confirm it is answering:

```bash
curl -s -o /dev/null -w "jenkins: %{http_code}\n" http://localhost:8080/login
```

`200` means ready. Get the unlock password (first run only):

```bash
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Finish the wizard at http://localhost:8080 → paste password → **Select plugins
to install → None** → create your admin user. Leave the browser on the Jenkins
dashboard.

**Have two browser tabs open:** Jenkins (`:8080`) and the app (`:8000`), plus one
terminal. That is the whole stage setup.

---

## Act 0 — Framing (2 min, no commands)

> **SAY:** "Right now, when you finish a code change, what happens? You test it
> by hand, you copy files to a server, you restart something, you hope. Every
> one of those steps is a place a human forgets something at 6pm on a Friday.
>
> CI/CD is: a machine does those steps, the same way, every time. **CI** is
> *continuous integration* — every change gets built and tested automatically.
> **CD** is *continuous deployment* — if it passes, it goes live automatically.
>
> Jenkins is the machine that runs those steps. That is all it is: a thing that
> runs your scripts when something happens, and shows you the result.
>
> In the next 25 minutes we will take a real Python web app, build it, deploy
> it, and then I am going to deliberately break it twice to show you what stops
> broken code from reaching users."

---

## Act 1 — Jenkins is just a container (2 min)

```bash
cat docker-compose.yml
```

> **SAY:** "Jenkins is installed here. That is the whole installation — no
> installer, no server to provision. Port 8080 is the Jenkins UI. Port 8000 is
> where our app will be live. The `jenkins_home` volume is Jenkins' memory: jobs,
> build history, and our deployed releases live there, so they survive a restart."

```bash
cat jenkins/Dockerfile
```

> **SAY:** "We extend the official image for one reason: our app is Python, so
> the machine that builds it needs `python3`. Plugins are baked in too, so the
> setup wizard doesn't make us wait."
>
> **WHY:** In a real shop you rarely run builds on the Jenkins server itself —
> you attach *agents* (separate machines or containers) and Jenkins farms work
> out to them. One box is fine for learning; the pipeline code is identical.

---

## Act 2 — The app we are shipping (3 min)

```bash
ls app/
cat app/pyproject.toml
```

> **SAY:** "A small Flask web app — a task list. What matters is
> `pyproject.toml`. This makes the app *buildable*: it has a name, a **version**,
> and its dependencies. This is what turns a folder of files into something you
> can ship."

Show the health endpoint in the code:

```bash
grep -A 5 '@app.get("/health")' app/src/taskboard/app.py
```

> **SAY:** "Remember this endpoint. It is how the deploy script asks the running
> app 'are you actually alive?' — and it reports which version is live. A deploy
> you can't verify isn't a deploy, it's a hope."
>
> **WHY — the `.pyc` question people always ask:** Python does not deploy `.pyc`
> files. The Python equivalent of a Java `.war` is a **wheel** (`.whl`) — a
> versioned, installable archive with its dependencies declared. That is the
> artifact we build.

---

## Act 3 — The pipeline is a shell script (3 min) ★ key idea

```bash
grep -E '^\s*(setup|lint|test_|build|deploy|rollback)\(\)' ci/ci.sh
```

> **SAY:** "Here is every stage of our pipeline. It is a plain shell script.
> Lint, test, build, deploy, rollback."

```bash
cat Jenkinsfile
```

> **SAY:** "And here is the Jenkins pipeline — about 40 lines, and notice what it
> does *not* contain. No build logic. Every stage just calls the shell script.
>
> This is the most important design decision in the whole demo."

**Now prove it — run the entire production pipeline with no Jenkins at all:**

```bash
./ci/ci.sh all
```

> This comes up on **port 8081**, not 8000. The Jenkins container already
> publishes 8000 on your Mac, so the script defaults to 8081 for local runs and
> the Jenkinsfile overrides it to 8000 for the real deploy. Same script, port
> taken from the environment — which is its own small lesson.

> **SAY:** "That just did everything Jenkins is about to do — on my laptop, no
> job, no commit, no waiting in a queue. Same script, same commands.
>
> **WHY this matters:** if your build logic lives inside Jenkins, then debugging
> a build means pushing a commit and waiting. Every fix is a guess with a
> five-minute feedback loop. Keep the logic in scripts and you debug locally in
> seconds. And if you ever move to GitLab CI or GitHub Actions, the script comes
> with you — you only rewrite the 40-line orchestration file.
>
> The anti-pattern is 300 lines of Groovy in a Jenkinsfile that can only ever run
> inside Jenkins. You will see it in the wild. Don't write it."

Open **http://localhost:8081** — the app is live, deployed by that one command.
Add a task in the browser.

Now stop it, because Jenkins is about to deploy the real thing on port 8000:

```bash
./ci/ci.sh stop
```

---

## Act 4 — Create the Jenkins job (4 min, in the UI)

In Jenkins: **New Item** → name `taskboard-deploy` → **Pipeline** → **OK**.

Scroll to the **Pipeline** section:

| Field | Value |
|---|---|
| Definition | **Pipeline script from SCM** |
| SCM | **Git** |
| Repository URL | `file:///srv/repo` |
| Branch Specifier | `*/main` |
| Script Path | `Jenkinsfile` |

**Save**.

> **SAY:** "Two things to notice. First, the pipeline is read *from the
> repository*, not typed into this text box. Your pipeline is code, it is
> reviewed in pull requests, and it is versioned with the app it builds —
> 'pipeline as code'.
>
> Second, that `file:///srv/repo` URL. Normally this is a GitHub URL. I've
> mounted our project into the container instead so we can see the whole
> mechanism with no accounts, no tokens, no network. Swapping in a GitHub URL
> plus a webhook is a five-minute change — and that is genuinely the only
> difference between this and production."

---

## Act 5 — First build → the site goes live (3 min)

Click **Build Now**. Open the build → **Console Output**.

> **SAY while it runs:** "Watch the stages: Setup, Lint, Test, Build, Deploy.
> Setup installs the build tools. Lint checks style. Test runs the test suite.
> Build produces the wheel. Deploy puts it live.
>
> Order matters and it is not arbitrary — the cheap, fast checks run first.
> There is no point building an artifact from code that fails its tests."

When it goes green, open **http://localhost:8000**.

> **SAY:** "That is a real web app, built and deployed by Jenkins, with zero
> manual steps. Note the version in the footer — the running site is telling us
> which build it is."

Show what the deploy actually did:

```bash
docker compose exec jenkins ls -l /var/jenkins_home/deploy /var/jenkins_home/deploy/releases
```

> **SAY:** "This is the deployment pattern, and it is the same one Capistrano and
> Ansible have used on servers for fifteen years.
>
> - `releases/` — each build gets its own directory with its own Python
>   environment. **Immutable.** We never edit a release in place, we replace it.
> - `shared/` — the database. It lives *outside* the releases, so it survives
>   every deploy.
> - `current` — a symlink pointing at the live release.
> - `previous` — a symlink pointing at the last one. That is our undo button.
>
> Going live is: build a new release directory, then move one symlink and
> restart. Going back is: move the symlink the other way. That is why a rollback
> takes one second instead of twenty minutes."

Also point at the Jenkins build page sidebar:

> **SAY:** "Jenkins archived the `.whl` file and the test results. Every build
> keeps its artifact, so you can always answer 'what exactly is running in
> production?' — and redeploy that exact thing."

---

## Act 6 — A code change goes live (5 min) ★

Add two or three tasks in the browser first, so you can show they survive.

> **SAY:** "Now the thing you actually care about: I change the code, and the
> change appears on the site without me touching a server."

Open **`demo/01-search-box.md`** and follow it — four small copy-paste edits that
add a **search box** to the page:

| # | File | Change |
|---|---|---|
| 1 | `app/pyproject.toml` | version `1.0.0` → `1.1.0` |
| 2 | `app/src/taskboard/app.py` | filter the task list by a search term |
| 3 | `.../templates/index.html` | the text box itself + a little CSS |
| 4 | `app/tests/test_app.py` | a test for the new behaviour |

> **SAY while typing edit 4:** "Notice I am writing a test for the feature. That
> is not ceremony — in a minute the pipeline will run it, and that is what lets
> me say the new feature was verified before it shipped."

Commit:

```bash
git commit -am "add task search box"
```

> **SAY:** "In a real setup, merging this as a pull request would trigger the
> build on its own. Here I click the button."

**Build Now** → watch it go green → refresh **http://localhost:8000**.

> **SAY:** "There is the search box — new UI, live, and I never touched a server.
> The footer went 1.0.0 → 1.1.0, so I know exactly which build I am looking at.
>
> And the tasks I added before the deploy are still here. New code, same
> database. That is the `shared/` directory earning its keep.
>
> This is the single most common thing that goes wrong in homemade deploy
> scripts: someone puts the database inside the release folder, and every deploy
> quietly wipes production data."

Try the box: search a word, then click **clear**.

```bash
docker compose exec jenkins ls /var/jenkins_home/deploy/releases
```

> **SAY:** "Two releases now. The old one is kept, sitting there ready to roll
> back to — which we are about to need."

**If a live edit goes wrong mid-demo**, the identical change is saved as a patch:

```bash
git checkout -- app && git apply demo/01-search-box.patch
```

## Act 7 — Breaking a test blocks the deploy (3 min) ★

```bash
sed -i '' 's/assert tasks\[0\]\["done"\] == 0/assert tasks[0]["done"] == 99/' app/tests/test_app.py
git commit -am "break a test"
```

> **SAY:** "Now I'm going to do what happens on every real team every week —
> ship a change with a bug in it."

**Build Now** → the build goes **red** at **Test**.

> **SAY:** "Test failed. Now look at the stages: Build never ran. Deploy never
> ran. Jenkins stopped at the first failure.
>
> Refresh the site — still 1.1.0, still up, still serving users. **Broken code
> physically could not reach the site.** That is continuous integration doing its
> actual job.
>
> Click **Test Result** — Jenkins parsed the test report and tells you exactly
> which assertion failed. Nobody has to read the console log."

Fix it:

```bash
git revert --no-edit HEAD
```

> **SAY:** "Reverted. In a real team this is the moment you'd fix forward or
> revert the PR."

---

## Act 8 — Auto-rollback when tests can't save you (4 min) ★★ the money moment

```bash
sed -i '' 's/^import os$/import os\nimport module_that_does_not_exist/' app/src/taskboard/app.py
git commit -am "runtime breakage"
```

> **SAY:** "Tests catch a lot. They do not catch everything. This bug is the kind
> that passes every test and still takes the site down — a missing dependency, a
> bad config value, something that only fails when the real app actually starts.
>
> Watch what happens."

**Build Now.** Narrate the console output as it scrolls:

> **SAY:** "Lint passes. Tests pass. The wheel builds fine. Deploy starts —
> new release created, symlink flipped, gunicorn started...
>
> ...and now the health check. Jenkins is asking the app 'are you alive?' over
> and over. No answer. The app started and immediately died.
>
> **Rolling back.** Symlink goes back to the previous release, restart, health
> check — green. Site is back on the good version.
>
> The build is red, so I know something is wrong. But the site never went down."

Prove it:

```bash
curl -s http://localhost:8000/health; echo
```

> **SAY:** "Still serving 1.1.0. Users never saw the broken build.
>
> **This is the difference between CI and CD.** CI is 'don't merge broken code.'
> CD is 'even when broken code gets through — and it will — the system catches it
> and puts things back.' Every deploy is health-checked and every deploy is
> reversible. If your rollback has never been tested, you don't have one."

Clean up:

```bash
git revert --no-edit HEAD
```

---

## Act 9 — The rollback button (2 min)

> **SAY:** "Rollback is also a button, for when you need it and no build is
> running."

In Jenkins: **Build with Parameters** → tick **ROLLBACK** → **Build**.

> **SAY:** "No build, no tests, no wheel — it just moves the symlink back and
> restarts. Seconds, not minutes. This is the button you want to exist *before*
> the day you need it at 2am."

Roll forward again with a normal **Build Now**.

---

## Act 10 — How this maps to real companies (3 min, no commands)

> **SAY:** "What we built is rung one of a ladder. Here is how shops climb it:"

| Rung | What changes | Why they do it |
|---|---|---|
| **This demo** | wheel → release dir → restart, one box | the mechanics, end to end |
| **+ SCM trigger** | a merged PR triggers the build, no button | humans stop being the trigger |
| **+ artifact repo** | wheel pushed to Nexus / Artifactory | one build, promoted across environments |
| **+ containers** | `docker build` → registry → run | the "install Python on the server" problem disappears |
| **+ orchestrator** | Kubernetes / ECS does the rollout | health checks and rollback become the platform's job |
| **+ environments** | dev → staging → prod, prod needs approval | a human approves *promotion*, not the mechanics |

> **SAY:** "Two rules hold at every single rung, and they are the real lesson:
>
> **One — build the artifact once, then promote that same artifact forward.**
> Never rebuild per environment. If you build separately for staging and prod,
> production is running bits that nobody ever tested.
>
> **Two — every deploy is health-checked and reversible.** We did that today with
> a symlink and a curl loop. Kubernetes does it with readiness probes. Same idea,
> different budget.
>
> Everything else — which tool, which cloud, YAML or Groovy — is detail."

---

## Q&A cheat sheet

**"Why not just GitHub Actions?"**
Same concepts, different host. Jenkins wins when you need to run inside your own
network, on your own hardware, or against legacy systems. Actions/GitLab win on
convenience. The shell script we wrote runs unchanged on all three — that is
exactly why we kept the logic out of the Jenkinsfile.

**"Does the app have to run on the Jenkins machine?"**
No, and in production it never does. `ci/ci.sh deploy` would `ssh` to an app
server, or push an image to a registry. We run it locally so the whole mechanism
is visible in one place.

**"What about secrets — passwords, API keys?"**
Jenkins has a built-in **Credentials** store; you inject them into the build as
environment variables with `withCredentials`. Never in the repo, never in the
Jenkinsfile.

**"What if two builds run at once?"**
They'd fight over the deploy directory. Real setups use a `lock` step or
`disableConcurrentBuilds()`. Out of scope today, but a genuine production
concern — good instinct if someone asks it.

**"How does this scale to a big team?"**
Jenkins *agents*. The controller schedules; agents do the work. You add agents,
not bigger servers.

**"Why did the first build have to be manual?"**
Jenkins has to read the `Jenkinsfile` once before it knows what triggers and
parameters the job has. Classic confusion — it bites everyone.

---

## Reset between rehearsals

Back to a clean slate:

```bash
git reset --hard demo-start
docker compose exec jenkins bash -c 'DEPLOY_ROOT=/var/jenkins_home/deploy /srv/repo/ci/ci.sh stop 2>/dev/null; rm -rf /var/jenkins_home/deploy'
```

Then **Build Now** in Jenkins to get back to a deployed 1.0.0.

To also clear build history: job page → **Configure** → or just delete and
recreate the job (Act 4 takes 90 seconds).

Full teardown, including Jenkins itself:

```bash
docker compose down -v    # -v also deletes the jenkins_home volume
```

---

## Gotchas worth mentioning while teaching

These are real problems that were hit building this demo. They land well because
they are honest.

- **Jenkins kills your background processes.** `ProcessTreeKiller` reaps anything
  a build leaves running — gunicorn would die the instant the job went green.
  `ci/ci.sh` exports `JENKINS_NODE_COOKIE=dontKillMe` to opt out. This bites
  everyone exactly once, and the error is baffling until you know.
- **Docker volumes mask files baked into the image.** A `git config --global`
  written into the image vanished under the `jenkins_home` volume; it had to be
  `--system`.
- **`set -euo pipefail`** at the top of the script is why a failing command fails
  the stage instead of silently continuing into a deploy.
- **The trailing slash matters** on webhook URLs (`/github-webhook/`) when you
  add GitHub later.
- **Jenkins refuses `file://` checkouts by default.** The Git plugin treats a
  local-directory remote as insecure, and the build dies at *Declarative:
  Checkout SCM*. `docker-compose.yml` sets
  `-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true` to permit it. This is
  a demo-only setting — you would never enable it on a shared controller, and
  the moment you point the job at GitHub instead, it stops being needed.
- **Put `junit` and `archiveArtifacts` in the stage that produces them, not in
  the pipeline-level `post`.** If the build fails *before* a workspace exists
  (bad checkout, bad Jenkinsfile), a pipeline-level `post` running `junit`
  throws `Required context class hudson.FilePath is missing` — a stack trace
  that tells you nothing about the actual failure. Stage-level `post` blocks
  only run when that stage ran, so the real error stays visible.
- **A missing plugin fails the build before a single stage runs.** `timestamps()`
  needs the Timestamper plugin and `junit` needs the JUnit plugin; without them
  the pipeline will not even compile, and the error names the step, not the
  plugin. Both are listed in `jenkins/plugins.txt`. If you ever see
  `Invalid option type "..."`, it is a missing plugin, not a syntax error.
- **Port collisions look like application crashes.** The Jenkins container
  publishes 8000, so a *host* deploy on 8000 failed with a health-check timeout
  that looked like a broken app. Two fixes: local runs now default to 8081, and
  the script checks the port up front instead of letting it present as a crash.
  This is the class of bug where the symptom and the cause are nowhere near each
  other. Good thing to say out loud.

---

## Practice exercises (for the learner, after the demo)

Work through these in order. Each one is a real pipeline skill.

1. **Change the app, ship it.** Work through `demo/01-search-box.md` yourself:
   four edits, commit, Build Now, see it live. Then do one of your own — show a
   task count in the heading. *Goal: the full loop feels routine.*

2. **Write a failing test on purpose, then fix it.** Watch the build go red and
   Deploy get skipped. *Goal: internalise that CI gates deployment.*

3. **Add a pipeline stage.** Add a `security` stage to `ci/ci.sh` that runs
   `pip install pip-audit && pip-audit`, and wire it into the `Jenkinsfile`
   between Test and Build. *Goal: pipelines are just scripts you extend.*

4. **Make a stage non-blocking.** Make Lint report problems without failing the
   build (`catchError` in the Jenkinsfile, or `|| true` in the script). Then
   argue with yourself about whether that is a good idea. *Goal: there is a real
   trade-off between strictness and velocity.*

5. **Break the health check.** Change `/health` to always return HTTP 500, then
   deploy. Watch the auto-rollback. *Goal: see the safety net catch a failure
   tests cannot.*

6. **Keep only 3 releases instead of 5.** Find `KEEP_RELEASES` in `ci/ci.sh`,
   change it, deploy four times, confirm old releases get pruned. *Goal: read and
   modify deploy logic confidently.*

7. **Connect it to GitHub.** Push the repo, point the job at the GitHub URL, add
   a webhook via ngrok, tick *GitHub hook trigger*. Merge a PR and watch a build
   start on its own. *Goal: the last mile to a real-world setup.*

Exercise 7 is the graduation. Everything before it is the mechanism; that one
makes it automatic.
