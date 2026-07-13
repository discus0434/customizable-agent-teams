.PHONY: post-change smoke

post-change:
	@git diff --check -- .

smoke: harness-test

include .agents/agent-team.mk
include .agents/harness.mk
