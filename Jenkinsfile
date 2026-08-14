pipeline {
  agent { label 'trainmate-builder' }

  options {
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
  }

  environment {
    PYTHONUNBUFFERED = '1'
    PIP_DISABLE_PIP_VERSION_CHECK = '1'
  }

  stages {
    stage('检出与基线检查') {
      steps {
        checkout scm
        sh '''
          set -eu
          test -f pubspec.lock
          test -f backend/pyproject.toml
          test -f ops-web/package-lock.json
          if git ls-files | grep -E '(^|/)\._|(^|/)\.env$|deploy/(production\.env|\.env\.deploy)$'; then
            echo '发现禁止提交的 AppleDouble、密钥或生产环境文件' >&2
            exit 1
          fi
          flutter --version
          python3 --version
          docker --version
        '''
      }
    }

    stage('后端静态检查') {
      steps {
        dir('backend') {
          sh '''
            set -eu
            python3 -m venv .ci-venv
            .ci-venv/bin/python -m pip install -e '.[dev]'
            .ci-venv/bin/ruff check .
          '''
        }
      }
    }

    stage('后端测试') {
      steps {
        dir('backend') {
          sh '''
            mkdir -p test-results
            .ci-venv/bin/pytest --junitxml=test-results/pytest.xml
          '''
        }
      }
      post {
        always {
          junit testResults: 'backend/test-results/**/*.xml'
        }
      }
    }

    stage('Flutter 分析与测试') {
      steps {
        sh '''
          set -eu
          flutter pub get
          flutter analyze --no-pub
          flutter test --no-pub
        '''
      }
    }

    stage('Flutter Web 构建') {
      steps {
        sh '''
          set -eu
          test -n "${TRAINMATE_CI_API_BASE_URL:-}"
          flutter build web --release --no-wasm-dry-run --no-pub \
            --dart-define=TRAINFLOW_API_BASE_URL="${TRAINMATE_CI_API_BASE_URL}"
        '''
      }
    }

    stage('Ops Web 类型检查与构建') {
      steps {
        dir('ops-web') {
          sh '''
            set -eu
            node --version
            npm ci
            npm run build
          '''
        }
      }
    }

    stage('构建并推送不可变镜像') {
      when {
        expression {
          def ref = env.GIT_BUILD_REF ?: ''
          return ref == 'refs/heads/main' || ref.startsWith('refs/tags/v')
        }
      }
      steps {
        sh '''
          set -eu
          test -n "${TCR_REGISTRY:-}"
          test -n "${TCR_NAMESPACE:-}"
          test -n "${TCR_USERNAME:-}"
          test -n "${TCR_PASSWORD:-}"
          image_tag="${GIT_COMMIT}"
          api_image="${TCR_REGISTRY}/${TCR_NAMESPACE}/trainmate-api:${image_tag}"
          ops_image="${TCR_REGISTRY}/${TCR_NAMESPACE}/trainmate-ops-web:${image_tag}"
          printf '%s' "${TCR_PASSWORD}" | docker login "${TCR_REGISTRY}" \
            --username "${TCR_USERNAME}" --password-stdin
          docker build --build-arg APP_VERSION="${image_tag}" \
            --tag "${api_image}" backend
          docker build --tag "${ops_image}" ops-web
          docker push "${api_image}"
          docker push "${ops_image}"
          docker logout "${TCR_REGISTRY}"
          printf 'TRAINMATE_API_IMAGE=%s\n' "${api_image}" > image-manifest.env
          printf 'TRAINMATE_OPS_WEB_IMAGE=%s\n' "${ops_image}" >> image-manifest.env
          printf 'GIT_COMMIT=%s\n' "${GIT_COMMIT}" >> image-manifest.env
        '''
        archiveArtifacts artifacts: 'image-manifest.env', fingerprint: true
      }
    }
  }

  post {
    always {
      sh 'rm -rf backend/.ci-venv || true'
    }
  }
}
