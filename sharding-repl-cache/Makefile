COMPOSE = docker compose -f compose.yaml

.PHONY: up
up:
	$(COMPOSE) up -d

.PHONY: down
down:
	$(COMPOSE) down -v

.PHONY: ps
ps:
	$(COMPOSE) ps

.PHONY: init
init: up
	./scripts/wait-nodes.sh
	./scripts/init-replica-sets.sh
	./scripts/wait-primary.sh
	./scripts/enable-sharding.sh

.PHONY: count
count:
	./scripts/count.sh

.PHONY: cache
cache:
	./scripts/cache.sh
