#!/usr/bin/env bash
# CI/CD entrypoint. Jenkins calls this once per stage:  ci/ci.sh <stage>
# All real logic lives here, so the identical commands run on your laptop:
#   ./ci/ci.sh all
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_VENV="$ROOT/.venv"                       # tooling: pytest, ruff, build
PY="$BUILD_VENV/bin/python"
DIST="$ROOT/dist"

# Where releases land. Jenkins overrides this to a path on its persistent
# volume; locally it defaults inside the repo.
DEPLOY_ROOT="${DEPLOY_ROOT:-$ROOT/.deploy}"
RELEASES="$DEPLOY_ROOT/releases"
SHARED="$DEPLOY_ROOT/shared"                   # the DB: survives every release
CURRENT="$DEPLOY_ROOT/current"
PREVIOUS="$DEPLOY_ROOT/previous"
PIDFILE="$DEPLOY_ROOT/gunicorn.pid"
APP_PORT="${APP_PORT:-8000}"
KEEP_RELEASES=5

BUILD="${BUILD_NUMBER:-local-$(date +%Y%m%d%H%M%S)}"

log()  { echo "--- $*"; }
fail() { echo "!!! $*" >&2; exit 1; }

# ---------------------------------------------------------------- CI stages

setup() {
  log "setup: build toolchain"
  [ -d "$BUILD_VENV" ] || python3 -m venv "$BUILD_VENV"
  "$PY" -m pip install --quiet --upgrade pip
  "$PY" -m pip install --quiet -r "$ROOT/requirements-dev.txt"
  "$PY" --version
}

lint() {
  log "lint: ruff"
  "$PY" -m ruff check "$ROOT/app"
}

test_() {
  log "test: pytest"
  cd "$ROOT/app"
  # Install the app itself so tests import it exactly as production will.
  "$PY" -m pip install --quiet -e .
  "$PY" -m pytest tests -q --junitxml="$ROOT/test-results.xml"
}

build() {
  log "build: wheel"
  rm -rf "$DIST"
  "$PY" -m build --wheel --outdir "$DIST" "$ROOT/app"
  ls -lh "$DIST"
}

# ------------------------------------------------------------------- deploy

wheel_path() {
  local w
  w="$(ls -1 "$DIST"/taskboard-*.whl 2>/dev/null | head -1)" || true
  [ -n "$w" ] || fail "no wheel in $DIST - run './ci/ci.sh build' first"
  echo "$w"
}

stop_app() {
  [ -f "$PIDFILE" ] || return 0
  local pid; pid="$(cat "$PIDFILE")"
  if kill -0 "$pid" 2>/dev/null; then
    log "stopping gunicorn (pid $pid)"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  fi
  rm -f "$PIDFILE"
}

start_app() {
  local release="$1"
  # Jenkins' ProcessTreeKiller murders any process a build leaves running.
  # This cookie is the documented opt-out - without it the site dies the
  # moment the job goes green.
  export JENKINS_NODE_COOKIE=dontKillMe
  export TASKBOARD_DB="$SHARED/taskboard.db"
  log "starting gunicorn from $(basename "$release") on :$APP_PORT"
  "$release/venv/bin/gunicorn" \
      --bind "0.0.0.0:$APP_PORT" --workers 2 --daemon \
      --pid "$PIDFILE" \
      --access-logfile "$DEPLOY_ROOT/access.log" \
      --error-logfile "$DEPLOY_ROOT/error.log" \
      "taskboard.app:app"
}

port_free() {
  # python3 is guaranteed present (the Dockerfile installs it); lsof is not.
  python3 -c "
import socket, sys
s = socket.socket()
try:
    s.bind(('0.0.0.0', $APP_PORT))
except OSError:
    sys.exit(1)
finally:
    s.close()
" 2>/dev/null
}

health_check() {
  log "health check: http://localhost:$APP_PORT/health"
  for _ in $(seq 30); do
    if out="$(curl -fsS "http://localhost:$APP_PORT/health" 2>/dev/null)"; then
      echo "    $out"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

deploy() {
  local wheel release
  wheel="$(wheel_path)"
  release="$RELEASES/$BUILD"

  log "deploy: build $BUILD"
  mkdir -p "$RELEASES" "$SHARED"
  rm -rf "$release" && mkdir -p "$release"

  # A release is a self-contained venv with the wheel installed into it.
  # Immutable: never patched in place, only replaced.
  python3 -m venv "$release/venv"
  "$release/venv/bin/pip" install --quiet --upgrade pip
  "$release/venv/bin/pip" install --quiet "$wheel"

  # Remember what was live, so a failed health check can go back.
  if [ -L "$CURRENT" ]; then
    ln -sfn "$(readlink "$CURRENT")" "$PREVIOUS"
  fi

  stop_app
  # Our own app is stopped now, so anything still holding the port is a
  # foreign process. Catch it BEFORE flipping the symlink.
  if ! port_free; then
    fail "port $APP_PORT is already in use by another process.
    Common cause: the Jenkins container publishes $APP_PORT, so a deploy on
    the host collides with it. Use a different port, e.g.
        APP_PORT=8001 ./ci/ci.sh all"
  fi
  ln -sfn "$release" "$CURRENT"
  start_app "$CURRENT"

  if health_check; then
    log "release $BUILD is live at http://localhost:$APP_PORT"
    prune
  else
    log "health check FAILED - last lines of the app error log:"
    tail -15 "$DEPLOY_ROOT/error.log" 2>/dev/null | sed 's/^/    /' || true
    if [ -L "$PREVIOUS" ]; then
      log "rolling back"
      rollback
      fail "deploy of build $BUILD rolled back"
    else
      stop_app
      rm -f "$CURRENT"
      fail "build $BUILD would not start and there is no previous release to fall back to (see log above)"
    fi
  fi
}

rollback() {
  [ -L "$PREVIOUS" ] || fail "no previous release to roll back to"
  local target; target="$(readlink "$PREVIOUS")"
  log "rollback: -> $(basename "$target")"
  stop_app
  ln -sfn "$target" "$CURRENT"
  start_app "$CURRENT"
  health_check || fail "rollback target is also unhealthy - site is DOWN"
  log "rolled back to $(basename "$target")"
}

prune() {
  local live; live="$(basename "$(readlink "$CURRENT")")"
  ls -1t "$RELEASES" 2>/dev/null | tail -n "+$((KEEP_RELEASES + 1))" | while read -r old; do
    [ "$old" = "$live" ] && continue
    log "pruning old release $old"
    rm -rf "${RELEASES:?}/$old"
  done
}

status() {
  if [ -L "$CURRENT" ]; then echo "current: $(basename "$(readlink "$CURRENT")")"; else echo "current: none"; fi
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "gunicorn: running (pid $(cat "$PIDFILE")) on :$APP_PORT"
  else
    echo "gunicorn: not running"
  fi
  curl -fsS "http://localhost:$APP_PORT/health" 2>/dev/null && echo || echo "health: unreachable"
}

case "${1:-all}" in
  setup)    setup ;;
  lint)     lint ;;
  test)     test_ ;;
  build)    build ;;
  deploy)   deploy ;;
  rollback) rollback ;;
  status)   status ;;
  stop)     stop_app ;;
  all)      setup; lint; test_; build; deploy ;;
  *)        echo "usage: $0 {setup|lint|test|build|deploy|rollback|status|stop|all}" >&2; exit 2 ;;
esac
