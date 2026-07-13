.PHONY: post-change smoke

post-change:
	@git diff --check -- .

smoke:
	@echo "Define project smoke during bootstrap." >&2
	@exit 1

include .agents/agent-team.mk
