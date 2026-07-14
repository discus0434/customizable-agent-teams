# customizable-agent-teams

**English** | [日本語](.agents/docs/README.ja.md)

A project template that splits Claude Code and Codex into 11 roles and runs them as one team on tmux.

Humans talk to a single agent, the Lead. Task breakdown, assignment, review, and progress tracking all happen inside the team.

![customizable-agent-teams workflow](.agents/assets/agent-team-flow.png)

Pile requirements clarification, implementation, review, and completion judgment onto one agent, and it gradually loses the ability to pull what matters right now out of a bloated context.

This template instead gives each responsibility its own agent with its own dedicated context.

Separating responsibilities also lets you pick the right CLI and model per role: a conversation-strong model at the human-facing desk, cheap and fast models for high-volume implementation.

The team is built on four mechanisms.

- **Fixed reviewers**: every implementation worker has a fixed reviewer, and no task becomes done without passing review. The situation where an agent approves its own changes is removed structurally.
- **Completion gate**: when the Manager tries to report completion, the full verification suite runs automatically against the integrated HEAD at send time; if it fails, the send itself fails.
- **Express lane**: small requests skip the Manager. The Lead dispatches them straight to an Express Worker and reviews the result itself.
- **Model allocation in one config file**: edit `model` and `effort` in `.agents/config/agent-team.yaml` and the models swap out while the role structure stays intact. Hence the name.

## Requirements

Starting the team requires `git`, `make`, `bash`, `tmux`, `direnv`, and the CLIs of the coding agents you use.

GitHub operations use `gh`.

`ripgrep` is available for repository investigation.

The toolchain of the stack you choose is also used during bootstrap.

<details>
<summary>Install everything on macOS</summary>

```bash
brew install gh ripgrep direnv tmux pnpm node python uv
brew install --cask codex
npm install -g @anthropic-ai/claude-code
```

</details>

<details>
<summary>Install everything on apt-based Linux</summary>

```bash
npm install -g @openai/codex @anthropic-ai/claude-code
wget -qO- https://get.pnpm.io/install.sh | sh -
wget -qO- https://astral.sh/uv/install.sh | sh

type -p wget >/dev/null || (sudo apt update && sudo apt install -y wget)
sudo mkdir -p -m 755 /etc/apt/keyrings
out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
sudo mkdir -p -m 755 /etc/apt/sources.list.d
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt-get install -y gh ripgrep direnv tmux python3 nodejs npm
```

</details>

## Quick Start

1. Create a new repository from this template and clone it.

2. Enable `direnv` in your current shell.

   <details>
   <summary>Add the direnv hook to your shell</summary>

   ```bash
   if [ -n "${ZSH_VERSION:-}" ]; then
     rc="$HOME/.zshrc"; hook='eval "$(direnv hook zsh)"'
   elif [ -n "${BASH_VERSION:-}" ]; then
     rc="$HOME/.bashrc"; hook='eval "$(direnv hook bash)"'
   else
     echo "Add the direnv hook for your shell, then rerun Quick Start." >&2; exit 1
   fi
   eval "$hook"
   grep -Fqx "$hook" "$rc" 2>/dev/null || printf '\n%s\n' "$hook" >> "$rc"
   ```

   </details>

3. Start the bootstrap.

   ```bash
   make bootstrap
   make team-attach
   ```

   The Lead opens with a single question: what to build.

   With each answer it settles the deliverable, its users, the stack, the entrypoint, `make post-change`, and `make smoke`, in that order.

4. Once the Lead sends the initialization requirements to the Manager, press `Ctrl-b` then `d` to detach from tmux.

   From the repository root, start the remaining roles and attach again.

   ```bash
   make bootstrap-team
   make team-attach
   ```

   From here on, watch the Lead's pane for progress and answer when the Lead asks you something.

## Day-to-day operation

Humans only need three commands.

| Operation | Command |
| --- | --- |
| Start or restart the team | `make team-start`, then `make team-attach` |
| Check the current state | `make team-status` |
| Stop the team | `make team-stop` |

To detach from tmux, press `Ctrl-b` then `d`.

## Roles and configuration

| Role | Responsibility |
| --- | --- |
| **Lead** | The human's only point of contact; settles goals, success criteria, constraints, and approvals. |
| **Manager** | Manages tasks, dependencies, assignment, completion judgment, and `STATE.md`. |
| **Strategist** | Investigates causes, compares options, and shapes execution plans. |
| **Architect** | Decides technical direction, design boundaries, shared structure, and test policy. |
| **General Worker** | Handles ordinary implementation, verification, task commits, and reports. |
| **Hard Task Worker** | Handles implementation or debugging that needs sustained investigation and reasoning. |
| **General Reviewer** | Fields its fixed worker's questions, gives mid-task feedback, and does the final review. |
| **Research Worker** | Investigates the codebase, feasibility, and external sources. |
| **Express Worker** | Implements small tasks dispatched directly by the Lead. |
| **Frontend Worker** | Implements frontend work while checking the rendered result. |
| **Frontend Critic** | Reviews visual direction, rendering quality, interaction, accessibility, and the frontend implementation. |

Under `agents` in `.agents/config/agent-team.yaml`, you can change each agent's role, CLI, model, effort, window, count, and fixed supervisor.

```yaml
  - id: general-worker-1
    role: general-worker
    cli: codex
    model: gpt-5.6-luna
    effort: high
    window: general-worker-1
    supervisor: general-reviewer-1
```

Launch commands are generated from each agent's `cli`, `model`, and `effort`.

Claude Code runs with `--dangerously-skip-permissions`.

Codex runs with `--dangerously-bypass-approvals-and-sandbox`.

Research Workers and Express Workers hold no resident window; they are launched as non-interactive `codex exec` runs when a request is assigned. These two roles take no `window` field.

## Repository layout

| Path | Contents |
| --- | --- |
| `AGENTS.md` | Shared rules for every agent; `CLAUDE.md` is a symlink to this file. |
| `.agents/config/agent-team.yaml` | Agents, roles, models, efforts, and fixed supervisors. |
| `.agents/agent-team.mk` | Make targets that operate the agent team. |
| `.agents/docs/TEAM_PROTOCOL.md` | Connections between roles and state transitions. |
| `.agents/state/STATE.md` | The state needed for current decisions and next actions. |
| `.agents/state/MEMORY.md` | Rules, tips, pitfalls, and user preferences reused over the long term. |
| `.agents/skills/` | Skills shared by Claude Code and Codex. |
| `.agents/queue/` | Shared artifacts: tasks, reports, reviews, research, and more. |
| `Makefile` | Defines the project's `post-change` and `smoke`, and includes `.agents/agent-team.mk`. |

## Related documents

- [`AGENTS.md`](AGENTS.md): shared rules for every agent.
- [`TEAM_PROTOCOL.md`](.agents/docs/TEAM_PROTOCOL.md): connections between roles and state transitions.
- [`MEMORY.md`](.agents/state/MEMORY.md): update rules for the shared memory.
