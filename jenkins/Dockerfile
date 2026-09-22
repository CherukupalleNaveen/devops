FROM jenkins/jenkins:lts-jdk17

USER root
# ci/ci.sh needs python3 for the build and per-release venvs.
# (curl and git already ship in the base image.)
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv python3-pip \
 && rm -rf /var/lib/apt/lists/*
USER jenkins

# Pre-install plugins so the setup wizard stays fast.
# Kept above cheaper layers on purpose: this is the slow one, protect its cache.
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Cloning the bind-mounted repo trips git's "dubious ownership" check otherwise.
RUN git config --global --add safe.directory '*'
