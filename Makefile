.PHONY: post-change smoke harness-test bootstrap bootstrap-finish team-identity team-bootstrap team-start team-stop team-status team-send team-submit inbox dispatch report review-report state state-update memory-list memory-append

post-change:
	@git diff --check -- .

smoke:
	@echo "Define project smoke during team-bootstrap." >&2
	@exit 1

harness-test:
	@bash -n .agents/scripts/*.sh
	@bash -n .agents/tests/harness/*.sh
	./.agents/tests/harness/team_lifecycle_test.sh

bootstrap:
	direnv allow
	$(MAKE) post-change
	$(MAKE) team-bootstrap
	@session="$$(./.agents/scripts/team_config.sh session)"; tmux attach -t "$$session"

bootstrap-finish:
	$(MAKE) post-change
	$(MAKE) smoke
	rm -rf .agents/skills/team-bootstrap
	git add -A
	@if git diff --cached --quiet; then \
		echo "no bootstrap changes to commit" >&2; \
		exit 1; \
	fi
	git commit -m "Bootstrap project"
	$(MAKE) team-start
	@session="$$(./.agents/scripts/team_config.sh session)"; tmux attach -t "$$session"

team-identity:
	./.agents/scripts/team_identity.sh

team-bootstrap:
	./.agents/scripts/team_bootstrap.sh

team-start:
	./.agents/scripts/team_start.sh --restart

team-stop:
	./.agents/scripts/team_stop.sh

team-status:
	@./.agents/scripts/team_status.sh

team-send:
	@test -n "$(TO)" || { echo "TO is required" >&2; exit 2; }
	@test -n "$(TYPE)" || { echo "TYPE is required" >&2; exit 2; }
	./.agents/scripts/team_send.sh "$(TO)" "$(TYPE)" "$(TASK)" "$(BODY)"

team-submit:
	@test -n "$(AGENT)" || { echo "AGENT is required" >&2; exit 2; }
	./.agents/scripts/team_submit.sh "$(AGENT)"

inbox:
	@test -n "$(AGENT)" || { echo "AGENT is required" >&2; exit 2; }
	@if [ -n "$(MARK)" ]; then \
		./.agents/scripts/team_inbox.sh "$(AGENT)" --mark "$(MARK)"; \
	else \
		./.agents/scripts/team_inbox.sh "$(AGENT)"; \
	fi

report:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(AGENT)" || { echo "AGENT is required" >&2; exit 2; }
	@test -n "$(STATUS)" || { echo "STATUS is required" >&2; exit 2; }
	./.agents/scripts/team_report.sh "$(TASK)" "$(AGENT)" "$(STATUS)"

dispatch:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(WORKER)" || { echo "WORKER is required" >&2; exit 2; }
	@test -n "$(REVIEWER)" || { echo "REVIEWER is required" >&2; exit 2; }
	@./.agents/scripts/team_dispatch.sh "$(TASK)" "$(WORKER)" "$(REVIEWER)"

review-report:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(REVIEWER)" || { echo "REVIEWER is required" >&2; exit 2; }
	@test -n "$(DECISION)" || { echo "DECISION is required" >&2; exit 2; }
	@./.agents/scripts/team_review_report.sh "$(TASK)" "$(REVIEWER)" "$(DECISION)"

state:
	@./.agents/scripts/team_state_update.sh show

state-update:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(STATUS)" || { echo "STATUS is required" >&2; exit 2; }
	@./.agents/scripts/team_state_update.sh update "$(TASK)" "$(STATUS)"

memory-list:
	./.agents/scripts/team_memory_update.sh list

memory-append:
	@test -n "$(PROPOSAL)" || { echo "PROPOSAL is required" >&2; exit 2; }
	./.agents/scripts/team_memory_update.sh append "$(PROPOSAL)"
