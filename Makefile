# Phoenix local AWS (Floci) — the standard. Per-agent isolation via PROJECT.
# Each agent: `make up PROJECT=phoenix-<me>` → own container, own state.

PROJECT ?= phoenix
PORT    ?= 4566
COMPOSE := docker compose -p $(PROJECT)

.PHONY: up down reset seed wait logs sh

up: ## start this agent's Floci instance and wait for it
	$(COMPOSE) up -d
	$(MAKE) wait

down: ## stop and remove it (keeps the data volume)
	$(COMPOSE) down

reset: ## wipe everything (container + data volume)
	$(COMPOSE) down -v

wait: ## block until the endpoint answers
	@until curl -s "http://localhost:$(PORT)/" -o /dev/null; do sleep 0.2; done
	@echo "floci ready on :$(PORT)"

seed: ## apply the Layer 0 baseline (org + landing zone + OUs + registry) into Floci
	./seed/seed.sh

smoke: ## apply the self-contained smoke (org + Control Tower + DynamoDB) against Floci
	terraform -chdir=smoke init -input=false
	terraform -chdir=smoke apply -auto-approve -input=false
	terraform -chdir=smoke output

logs: ## follow Floci logs
	$(COMPOSE) logs -f floci

sh: ## shell into the Floci container
	$(COMPOSE) exec floci sh
