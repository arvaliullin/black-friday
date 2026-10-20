.PHONY: up
up:
	podman compose -f compose.yaml up -d

.PHONY: down
down:
	podman compose -f compose.yaml down -v

.PHONY: ps
ps:
	podman compose -f compose.yaml ps
