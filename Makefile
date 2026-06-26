.PHONY: post-change smoke template-test bootstrap bootstrap-team team-identity team-start team-stop team-status team-send team-submit inbox dispatch report review-report release-request release-report state state-update memory-list memory-append

post-change:
	@git diff --check -- .

smoke:
	@echo "Define project smoke during bootstrap." >&2
	@exit 1

template-test:
	@bash -n .agents/scripts/*.sh
	@bash -n .agents/tests/team/*.sh
	./.agents/tests/team/team_lifecycle_test.sh

bootstrap:
	direnv allow
	$(MAKE) post-change
	./.agents/scripts/team_bootstrap.sh
	@session="$$(./.agents/scripts/team_config.sh session)"; tmux attach -t "$$session"

bootstrap-team:
	./.agents/scripts/team_bootstrap_team.sh
	@session="$$(./.agents/scripts/team_config.sh session)"; tmux attach -t "$$session"

team-identity:
	./.agents/scripts/team_identity.sh

team-start:
	./.agents/scripts/team_start.sh --restart

team-stop:
	./.agents/scripts/team_stop.sh

team-status:
	@./.agents/scripts/team_status.sh

team-send:
	@test -n "$(TO)" || { echo "TO is required" >&2; exit 2; }
	@if [ -n "$(BODY_FILE)" ] && [ -n "$(BODY)" ]; then \
		echo "BODY and BODY_FILE cannot both be set" >&2; \
		exit 2; \
	fi
	@if [ -n "$(BODY_FILE)" ]; then \
		if [ -n "$(FROM)" ]; then \
			./.agents/scripts/team_send.sh --from "$(FROM)" --type "$(TYPE)" --task "$(TASK)" --bundle "$(BUNDLE)" --body-file "$(BODY_FILE)" "$(TO)"; \
		else \
			./.agents/scripts/team_send.sh --type "$(TYPE)" --task "$(TASK)" --bundle "$(BUNDLE)" --body-file "$(BODY_FILE)" "$(TO)"; \
		fi; \
	else \
		if [ -n "$(FROM)" ]; then \
			./.agents/scripts/team_send.sh --from "$(FROM)" --type "$(TYPE)" --task "$(TASK)" --bundle "$(BUNDLE)" "$(TO)" "$(BODY)"; \
		else \
			./.agents/scripts/team_send.sh --type "$(TYPE)" --task "$(TASK)" --bundle "$(BUNDLE)" "$(TO)" "$(BODY)"; \
		fi; \
	fi

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
	@if [ -n "$(MANAGER)" ]; then \
		./.agents/scripts/team_dispatch.sh --manager "$(MANAGER)" "$(TASK)" "$(WORKER)" "$(REVIEWER)"; \
	else \
		./.agents/scripts/team_dispatch.sh "$(TASK)" "$(WORKER)" "$(REVIEWER)"; \
	fi

review-report:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(REVIEWER)" || { echo "REVIEWER is required" >&2; exit 2; }
	@test -n "$(DECISION)" || { echo "DECISION is required" >&2; exit 2; }
	@./.agents/scripts/team_review_report.sh "$(TASK)" "$(REVIEWER)" "$(DECISION)"

release-request:
	@test -n "$(BUNDLE)" || { echo "BUNDLE is required" >&2; exit 2; }
	@test -n "$(TASKS)" || { echo "TASKS is required" >&2; exit 2; }
	@if [ -n "$(MANAGER)" ] && [ -n "$(RELEASE_CAPTAIN)" ]; then \
		./.agents/scripts/team_release_request.sh --manager "$(MANAGER)" --release-captain "$(RELEASE_CAPTAIN)" "$(BUNDLE)" $(TASKS); \
	elif [ -n "$(MANAGER)" ]; then \
		./.agents/scripts/team_release_request.sh --manager "$(MANAGER)" "$(BUNDLE)" $(TASKS); \
	elif [ -n "$(RELEASE_CAPTAIN)" ]; then \
		./.agents/scripts/team_release_request.sh --release-captain "$(RELEASE_CAPTAIN)" "$(BUNDLE)" $(TASKS); \
	else \
		./.agents/scripts/team_release_request.sh "$(BUNDLE)" $(TASKS); \
	fi

release-report:
	@test -n "$(BUNDLE)" || { echo "BUNDLE is required" >&2; exit 2; }
	@test -n "$(RELEASE_CAPTAIN)" || { echo "RELEASE_CAPTAIN is required" >&2; exit 2; }
	@test -n "$(DECISION)" || { echo "DECISION is required" >&2; exit 2; }
	@./.agents/scripts/team_release_report.sh "$(BUNDLE)" "$(RELEASE_CAPTAIN)" "$(DECISION)"

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
