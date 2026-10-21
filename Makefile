.PHONY: up
up:
	docker compose -f compose.yaml up -d

.PHONY: down
down:
	docker compose -f compose.yaml down -v

.PHONY: ps
ps:
	docker compose -f compose.yaml ps
