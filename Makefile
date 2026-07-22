.PHONY: help up down logs backend-install backend-run backend-test backend-lint backend-typecheck \
	backend-shell db-migrate db-reset seed api-validate api-generate-ios api-check-generated test clean-local \
	repo-checks docker-build ios-generate ios-build ios-test \
	ios-build-local ios-build-development ios-build-staging ios-build-production \
	ios-test-local ios-test-development ios-test-staging ios-test-production \
	account-deletion-finalize \
	staging-up staging-smoke backup-postgres restore-postgres perf-profile \
	job-upload-cleanup job-sketch-session-cleanup job-story-session-cleanup job-idempotency-cleanup \
	job-deleted-media-cleanup job-missing-prompt-check jobs-dry-run

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BACKEND := $(ROOT)/backend
# Local stack includes override (hot reload). Staging omits it on purpose.
COMPOSE := docker compose -f $(ROOT)/docker-compose.yml -f $(ROOT)/docker-compose.override.yml
STAGING_COMPOSE := docker compose -f $(ROOT)/docker-compose.yml -f $(ROOT)/docker-compose.staging.yml
PROD_COMPOSE := docker compose -f $(ROOT)/docker-compose.yml

# Prefer host .venv when present (CI / optional native tooling); otherwise use the Compose backend.
# Usage: $(call run_backend,pytest -q)  — command may include && ; run via bash -c.
define run_backend
	@if [ -x "$(BACKEND)/.venv/bin/python" ]; then \
		cd $(BACKEND) && . .venv/bin/activate && bash -c '$(1)'; \
	else \
		$(COMPOSE) exec -T backend bash -c '$(1)'; \
	fi
endef

help:
	@echo "Daily Sketch Make targets:"
	@echo "  up / down / logs / clean-local / staging-up / staging-smoke"
	@echo "  backend-shell / backend-test / backend-lint / backend-typecheck"
	@echo "  backend-install / backend-run  (optional host venv; CI uses install)"
	@echo "  db-migrate / db-reset / seed / account-deletion-finalize"
	@echo "  job-* cleanup targets / jobs-dry-run / perf-profile"
	@echo "  backup-postgres / restore-postgres BACKUP=path"
	@echo "  api-validate / api-generate-ios / api-check-generated"
	@echo "  repo-checks / docker-build / ios-generate / ios-build / ios-test / test"
	@echo "  ios-build|test with IOS_ENV=local|development|staging|production (IOS_APP=DailySketch|DailyStory)"

up:
	$(COMPOSE) up --build postgres minio minio-init backend

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

staging-up:
	$(STAGING_COMPOSE) up -d --build postgres minio minio-init backend

staging-smoke:
	@curl -fsS http://localhost:8080/health/live >/dev/null
	@curl -fsS http://localhost:8080/health/ready >/dev/null
	@curl -fsS http://localhost:8080/health/version >/dev/null
	@echo "Staging smoke checks passed."

backend-install:
	cd $(BACKEND) && uv venv .venv --python 3.14 && uv pip install -e ".[dev]"

backend-run:
	cd $(BACKEND) && . .venv/bin/activate && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

backend-shell:
	$(COMPOSE) exec backend bash

backend-test:
	$(call run_backend,pytest -q)

backend-lint:
	$(call run_backend,ruff check app tests && ruff format --check app tests)

backend-typecheck:
	$(call run_backend,mypy app)

db-migrate:
	$(call run_backend,alembic upgrade head)

db-reset:
	@echo "WARNING: This destroys the local Postgres volume and re-applies migrations."
	@printf "Type 'yes' to continue: " && read answer && [ "$$answer" = "yes" ]
	$(COMPOSE) down -v
	$(COMPOSE) up -d --build postgres minio minio-init backend
	@echo "Waiting for backend (migrations run on start)..."
	@until curl -fsS http://localhost:8000/health/ready >/dev/null 2>&1; do sleep 1; done
	@echo "Database reset complete."

seed:
	$(call run_backend,python -m app.seeds.prompts --days 30)
	$(call run_backend,python -m app.seeds.safety)

account-deletion-finalize:
	$(call run_backend,python -m app.jobs.account_deletion)

job-upload-cleanup:
	$(call run_backend,python -m app.jobs.upload_cleanup)

job-sketch-session-cleanup:
	$(call run_backend,python -m app.jobs.sketch_session_cleanup)

job-story-session-cleanup:
	$(call run_backend,python -m app.jobs.story_session_cleanup)

job-idempotency-cleanup:
	$(call run_backend,python -m app.jobs.idempotency_cleanup)

job-deleted-media-cleanup:
	$(call run_backend,python -m app.jobs.deleted_media_cleanup)

job-missing-prompt-check:
	$(call run_backend,python -m app.jobs.missing_prompt_check)

jobs-dry-run:
	$(call run_backend,python -m app.jobs.upload_cleanup --dry-run)
	$(call run_backend,python -m app.jobs.sketch_session_cleanup --dry-run)
	$(call run_backend,python -m app.jobs.story_session_cleanup --dry-run)
	$(call run_backend,python -m app.jobs.idempotency_cleanup --dry-run)
	$(call run_backend,python -m app.jobs.deleted_media_cleanup --dry-run)
	$(call run_backend,python -m app.jobs.missing_prompt_check --dry-run)
	$(call run_backend,python -m app.jobs.account_deletion --dry-run)

backup-postgres:
	bash $(ROOT)/scripts/ops/backup-postgres.sh

restore-postgres:
	@if [ -z "$(BACKUP)" ]; then echo "Usage: make restore-postgres BACKUP=path/to/backup.sql" >&2; exit 1; fi
	bash $(ROOT)/scripts/ops/restore-postgres.sh "$(BACKUP)"

perf-profile:
	@if [ -x "$(BACKEND)/.venv/bin/python" ]; then \
		cd $(BACKEND) && . .venv/bin/activate && python $(ROOT)/scripts/perf/load_profile.py; \
	else \
		$(COMPOSE) exec -T backend python /scripts/perf/load_profile.py; \
	fi

api-validate:
	bash $(ROOT)/scripts/api-validate.sh

api-generate-ios:
	bash $(ROOT)/scripts/api-generate-ios.sh

api-check-generated:
	bash $(ROOT)/scripts/api-check-generated.sh

repo-checks:
	bash $(ROOT)/scripts/repo-checks.sh

docker-build:
	$(PROD_COMPOSE) build backend

ios-generate:
	cd $(ROOT)/ios && xcodegen generate

# iOS environment: local | development | staging | production
IOS_ENV ?= local
# iOS app target: DailySketch | DailyStory
IOS_APP ?= DailySketch
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 16,OS=18.1

ios_config_local := Debug-Local
ios_config_development := Debug-Development
ios_config_staging := Release-Staging
ios_config_production := Release-Production
IOS_CONFIGURATION = $(ios_config_$(IOS_ENV))

ifeq ($(IOS_ENV),local)
  IOS_SCHEME_SUFFIX :=
else ifeq ($(IOS_ENV),development)
  IOS_SCHEME_SUFFIX := Development
else ifeq ($(IOS_ENV),staging)
  IOS_SCHEME_SUFFIX := Staging
else ifeq ($(IOS_ENV),production)
  IOS_SCHEME_SUFFIX := Production
else
  $(error Unknown IOS_ENV '$(IOS_ENV)'. Use: local, development, staging, or production.)
endif

ifeq ($(IOS_SCHEME_SUFFIX),)
  IOS_SCHEME := $(IOS_APP)
else
  IOS_SCHEME := $(IOS_APP) $(IOS_SCHEME_SUFFIX)
endif

ios-build:
	cd $(ROOT)/ios && xcodebuild \
		-project DailySketch.xcodeproj \
		-scheme '$(IOS_SCHEME)' \
		-destination '$(IOS_DESTINATION)' \
		-configuration $(IOS_CONFIGURATION) \
		build

ios-test:
	cd $(ROOT)/ios && xcodebuild \
		-project DailySketch.xcodeproj \
		-scheme '$(IOS_SCHEME)' \
		-destination '$(IOS_DESTINATION)' \
		-configuration $(IOS_CONFIGURATION) \
		test

ios-build-local ios-build-development ios-build-staging ios-build-production:
	$(MAKE) ios-build IOS_ENV=$(subst ios-build-,,$@)

ios-test-local ios-test-development ios-test-staging ios-test-production:
	$(MAKE) ios-test IOS_ENV=$(subst ios-test-,,$@)

test: backend-test api-validate repo-checks

clean-local:
	$(COMPOSE) down -v --remove-orphans
	rm -rf $(BACKEND)/.venv $(BACKEND)/.pytest_cache $(BACKEND)/.mypy_cache $(BACKEND)/.ruff_cache
	rm -rf $(ROOT)/api/generated/.tmp-ios $(ROOT)/api/generated/.check-ios
	@echo "Local Docker volumes and Python caches cleaned."
