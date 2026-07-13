.PHONY: bootstrap bootstrap-team team-attach team-identity team-start team-stop team-status team-send team-reply team-submit inbox agent-surfaces task-lint dispatch express-fix task-commit report direction-report supervision-report state state-update state-commit memory-list memory-append

bootstrap:
	direnv allow
	$(MAKE) post-change
	./.agents/scripts/team_bootstrap.sh

bootstrap-team:
	./.agents/scripts/team_bootstrap_team.sh

team-attach:
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
			./.agents/scripts/team_send.sh --from "$(FROM)" --type "$(TYPE)" --task "$(TASK)" --body-file "$(BODY_FILE)" "$(TO)"; \
		else \
			./.agents/scripts/team_send.sh --type "$(TYPE)" --task "$(TASK)" --body-file "$(BODY_FILE)" "$(TO)"; \
		fi; \
	else \
		if [ -n "$(FROM)" ]; then \
			./.agents/scripts/team_send.sh --from "$(FROM)" --type "$(TYPE)" --task "$(TASK)" "$(TO)" "$(BODY)"; \
		else \
			./.agents/scripts/team_send.sh --type "$(TYPE)" --task "$(TASK)" "$(TO)" "$(BODY)"; \
		fi; \
	fi

team-reply:
	@test -n "$(IN_REPLY_TO)" || { echo "IN_REPLY_TO is required" >&2; exit 2; }
	@if [ -n "$(BODY_FILE)" ] && [ -n "$(BODY)" ]; then \
		echo "BODY and BODY_FILE cannot both be set" >&2; \
		exit 2; \
	fi
	@args="--in-reply-to $(IN_REPLY_TO)"; \
	if [ -n "$(FROM)" ]; then args="$$args --from $(FROM)"; fi; \
	if [ -n "$(TO)" ]; then args="$$args --to $(TO)"; fi; \
	if [ -n "$(TYPE)" ]; then args="$$args --type $(TYPE)"; fi; \
	if [ -n "$(BODY_FILE)" ]; then \
		./.agents/scripts/team_reply.sh $$args --body-file "$(BODY_FILE)"; \
	else \
		./.agents/scripts/team_reply.sh $$args "$(BODY)"; \
	fi

team-submit:
	@test -n "$(AGENT)" || { echo "AGENT is required" >&2; exit 2; }
	./.agents/scripts/team_submit.sh "$(AGENT)"

inbox:
	@test -n "$(AGENT)" || { echo "AGENT is required" >&2; exit 2; }
	@if [ -n "$(MARK)" ]; then \
		./.agents/scripts/team_inbox.sh "$(AGENT)" --mark "$(MARK)"; \
	elif [ -n "$(RAW)" ]; then \
		./.agents/scripts/team_inbox.sh "$(AGENT)" --raw; \
	else \
		./.agents/scripts/team_inbox.sh "$(AGENT)"; \
	fi

agent-surfaces:
	@./.agents/scripts/team_agent_surfaces.sh

task-lint:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@./.agents/scripts/team_task_lint.sh "$(TASK)"

dispatch:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@if [ -n "$(OWNER)" ]; then \
		./.agents/scripts/team_dispatch.sh --owner "$(OWNER)" "$(TASK)"; \
	else \
		./.agents/scripts/team_dispatch.sh "$(TASK)"; \
	fi

express-fix:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(BODY)" || { echo "BODY is required" >&2; exit 2; }
	@./.agents/scripts/team_express_fix.sh "$(TASK)" "$(BODY)"

task-commit:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(MESSAGE)" || { echo "MESSAGE is required" >&2; exit 2; }
	@./.agents/scripts/team_task_commit.sh "$(TASK)" "$(MESSAGE)"

report:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(STATUS)" || { echo "STATUS is required" >&2; exit 2; }
	./.agents/scripts/team_report.sh "$(TASK)" "$(STATUS)"

direction-report:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(DECISION)" || { echo "DECISION is required" >&2; exit 2; }
	@if [ -n "$(BODY_FILE)" ]; then \
		./.agents/scripts/team_direction_report.sh "$(TASK)" "$(DECISION)" "$(BODY_FILE)"; \
	else \
		./.agents/scripts/team_direction_report.sh "$(TASK)" "$(DECISION)"; \
	fi

supervision-report:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(DECISION)" || { echo "DECISION is required" >&2; exit 2; }
	@./.agents/scripts/team_supervision_report.sh "$(TASK)" "$(DECISION)"

state:
	@./.agents/scripts/team_state_update.sh show

state-update:
	@test -n "$(TASK)" || { echo "TASK is required" >&2; exit 2; }
	@test -n "$(STATUS)" || { echo "STATUS is required" >&2; exit 2; }
	@./.agents/scripts/team_state_update.sh update "$(TASK)" "$(STATUS)"

state-commit:
	@./.agents/scripts/team_state_commit.sh

memory-list:
	./.agents/scripts/team_memory_update.sh list

memory-append:
	@test -n "$(PROPOSAL)" || { echo "PROPOSAL is required" >&2; exit 2; }
	./.agents/scripts/team_memory_update.sh append "$(PROPOSAL)"
