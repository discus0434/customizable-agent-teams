.PHONY: harness-test

harness-test:
	@bash -n .agents/scripts/*.sh
	@bash -n .agents/tests/team/*.sh
	./.agents/tests/team/team_lifecycle_test.sh
