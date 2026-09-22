pipeline {
  agent any

  environment {
    // Releases live on the Jenkins volume, so the site survives job runs
    // and container restarts. Port is published by docker-compose.
    DEPLOY_ROOT = '/var/jenkins_home/deploy'
    APP_PORT    = '8000'
  }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }

  parameters {
    booleanParam(
      name: 'ROLLBACK',
      defaultValue: false,
      description: 'Skip the build and roll the site back to the previous release'
    )
  }

  stages {
    stage('Rollback') {
      when { expression { params.ROLLBACK } }
      steps { sh './ci/ci.sh rollback' }
    }

    stage('Setup') {
      when { not { expression { params.ROLLBACK } } }
      steps { sh './ci/ci.sh setup' }
    }

    stage('Lint') {
      when { not { expression { params.ROLLBACK } } }
      steps { sh './ci/ci.sh lint' }
    }

    stage('Test') {
      when { not { expression { params.ROLLBACK } } }
      steps { sh './ci/ci.sh test' }
      // Published by the stage that produces it: this needs a workspace, so
      // keeping it here means an early failure (bad checkout, bad Jenkinsfile)
      // cannot trigger a confusing "FilePath is missing" error in post.
      post { always { junit testResults: 'test-results.xml', allowEmptyResults: true } }
    }

    stage('Build') {
      when { not { expression { params.ROLLBACK } } }
      steps { sh './ci/ci.sh build' }
      post {
        success {
          archiveArtifacts artifacts: 'dist/*.whl', allowEmptyArchive: true, fingerprint: true
        }
      }
    }

    // Deploy is what makes this CD rather than just CI: it installs the
    // wheel into a fresh release, flips the symlink, restarts gunicorn,
    // and auto-rolls-back if /health does not answer.
    stage('Deploy') {
      when { not { expression { params.ROLLBACK } } }
      steps { sh './ci/ci.sh deploy' }
    }

    stage('Status') {
      steps { sh './ci/ci.sh status || true' }
    }
  }

  // Only steps that need no workspace belong here.
  post {
    success { echo "✅ build ${env.BUILD_NUMBER} deployed - http://localhost:8000" }
    failure { echo "❌ build ${env.BUILD_NUMBER} failed - site left on the last good release" }
  }
}
