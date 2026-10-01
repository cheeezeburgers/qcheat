.DEFAULT_GOAL := help
.PHONY: help install uninstall dry-run test lint check tag push-tag release demo

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "} /^[[:alnum:]_-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' "$(strip $(MAKEFILE_LIST))"

install: ## Install qcheat
	./install.sh

uninstall: ## Remove qcheat-owned installed resources
	bash dev/uninstall.sh

dry-run: ## Preview installation without changes
	./install.sh --dry-run

test: ## Run offline test suite
	bash dev/tests/run.sh

lint: ## Run ShellCheck
	shellcheck install.sh bin/qcheat lib/*.sh dev/*.sh dev/tests/*.sh

check: lint test ## Run all validation

# Commit the current version first, then tag, push-tag and release in order.
tag: ## Create the current version tag
	bash dev/release.sh tag

push-tag: ## Push only the current version tag to origin
	bash dev/release.sh push-tag

release: ## Create a GitHub release for the pushed tag
	bash dev/release.sh release

demo: ## Regenerate assets/qcheat.gif with VHS
	vhs dev/demo.tape
