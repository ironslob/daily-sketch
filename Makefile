.PHONY: help up down logs backend-install backend-run backend-test backend-lint backend-typecheck \
	db-migrate db-reset seed api-validate api-generate-ios api-check-generated test clean-local \
	repo-checks docker-build ios-generate ios-build ios-test

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BACKEND := $(ROOT)/backend
COMPOSE := docker compose -f $(ROOT)/docker-compose.yml

help:
	@echo "Daily Sketch Make targets:"
	@echo "  up / down / logs / clean-local"
	@echo "  backend-install / backend-run / backend-test / backend-lint / backend-typecheck"
	@echo "  db-migrate / db-reset / seed"
	@echo "  api-validate / api-generate-ios / api-check-generated"
	@echo "  repo-checks / docker-build / ios-generate / ios-build / ios-test / test"

up:
	$(COMPOSE) up -d postgres minio minio-init backend

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

backend-install:
	cd $(BACKEND) && uv venv .venv --python 3.14 && uv pip install -e ".[dev]"

backend-run:
	cd $(BACKEND) && . .venv/bin/activate && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

backend-test:
	cd $(BACKEND) && . .venv/bin/activate && pytest -q

backend-lint:
	cd $(BACKEND) && . .venv/bin/activate && ruff check app tests && ruff format --check app tests

backend-typecheck:
	cd $(BACKEND) && . .venv/bin/activate && mypy app

db-migrate:
	cd $(BACKEND) && . .venv/bin/activate && alembic upgrade head

db-reset:
	@echo "WARNING: This destroys the local Postgres volume and re-applies migrations."
	@printf "Type 'yes' to continue: " && read answer && [ "$$answer" = "yes" ]
	$(COMPOSE) down -v
	$(COMPOSE) up -d postgres
	@echo "Waiting for Postgres..."
	@until $(COMPOSE) exec -T postgres pg_isready -U dailysketch -d dailysketch; do sleep 1; done
	$(MAKE) db-migrate

seed:
	cd $(BACKEND) && . .venv/bin/activate && python -m app.seeds.prompts --days 30

api-validate:
	bash $(ROOT)/scripts/api-validate.sh

api-generate-ios:
	bash $(ROOT)/scripts/api-generate-ios.sh

api-check-generated:
	bash $(ROOT)/scripts/api-check-generated.sh

repo-checks:
	bash $(ROOT)/scripts/repo-checks.sh

docker-build:
	$(COMPOSE) build backend

ios-generate:
	cd $(ROOT)/ios && xcodegen generate

ios-build:
	cd $(ROOT)/ios && xcodebuild \
		-project DailySketch.xcodeproj \
		-scheme DailySketch \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' \
		-configuration Debug \
		build

ios-test:
	cd $(ROOT)/ios && xcodebuild \
		-project DailySketch.xcodeproj \
		-scheme DailySketch \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' \
		-configuration Debug \
		test

test: backend-test api-validate repo-checks

clean-local:
	$(COMPOSE) down -v --remove-orphans
	rm -rf $(BACKEND)/.venv $(BACKEND)/.pytest_cache $(BACKEND)/.mypy_cache $(BACKEND)/.ruff_cache
	rm -rf $(ROOT)/api/generated/.tmp-ios $(ROOT)/api/generated/.check-ios
	@echo "Local Docker volumes and Python caches cleaned."
