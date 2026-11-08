# Resumable execution checkpoints: handover

Recorded 2026-11-08. This folder is working knowledge for the next session,
not documentation intended to merge into main. The user explicitly requested
that this knowledge be committed and will keep it out of main.

## Start here

- Repository: https://github.com/roschaefer/git-splice
- Task: https://github.com/roschaefer/git-splice/issues/445
- Worktree: `/home/robert/Development/tools-sub-repos/git-splice/exec-checkpoints`
- Branch: `feat/exec-checkpoints`
- Base: `pile/recursion`, commit `8d56103` (the `recursion-pile` worktree).
- Implementation has NOT started. Only the worktree/branch and this handover
  have been created. No tests, dependency changes, commits of code, or PRs.
- Continue implementation here rather than modifying one of the many existing
  worktrees. The parent directory is a bare Git repository, not a worktree.

Read [the agreed direction](design.md), [the code map](implementation-map.md),
and [the research](research.md) before implementing. The design is conversational
agreement, not a finalized wire format or a finished implementation plan.

## What the user wants

The initial request was to study Git's behaviour before tackling #445 and
understand whether hooks could support Git LFS. Discussion converged on a
general operation-checkpoint mechanism with `--exec`, rich structured payloads,
and externally stored continuation. The user then asked whether we had enough
to start; the assistant said yes and created this branch. Their latest request
is to commit this knowledge for handover before context runs out.

The key user statements were:

> git splice would send a payload with everything important to the script with
> --exec. This script could parse that payload and decide what to do.

> For the docs I want to interrupt, run check-drawing and compare the state
> with a diagram, and continue the operation until the next checkpoint.

> The interruption script could just echo the payload and die. The docs could
> then feed that payload (e.g. saved temporarily to a file) back to git splice.
> passed --exec again with the same script, it will interrupt, save the new
> payload, and so on.

The user also identified `--rebuilt-commit <commit>` as a narrow instance of
this external handoff pattern. The assistant agreed after inspecting the flag.

## Working instructions to preserve

- User-facing terminal commands use fish syntax. Scripts saved to files may
  use bash with a shebang. Tool execution shell in this session is bash.
- Conventional Commits: `<type>(<scope>): <imperative description>`. Explain
  motivation in the body, rather than narrating the diff.
- Never add AI coauthor trailers or conversation/session links to commits/PRs.
- Do not post comments, reviews, or other text under the user's GitHub account.
  PR titles/descriptions are allowed; issues only if explicitly requested.
- Any PR must initially be draft. No PR creation was requested or performed.
- When fixing automated review findings, resolve threads without replying.
- Prefer descriptive tests and clear code over explanatory code comments.
- Do not spawn subagents: current developer instructions prohibit this unless
  the user or applicable instructions explicitly request delegation.
- No applicable on-disk AGENTS.md was found in the inspected worktrees; the
  user's globally supplied AGENTS.md instructions above remain applicable.

## Environment notes

Git is 2.56.0. `git lfs version` fails in the plain shell because LFS is not on
PATH. LFS behaviour was researched through official docs and existing scenario
pages; no fresh LFS experiment was run. Use the development shell if needed.

The workspace allows ordinary file edits in this worktree, but shared `.git`
metadata is read-only in the sandbox. `git worktree add` initially failed for
that reason. Retrying through `exec_command` with
`sandbox_permissions: "require_escalated"` succeeded. Git add/commit will likely
need the same escalation. This is an environment boundary, not missing user
authorization. The user explicitly requested the handover commit.

No skill was applied: this task is repository development, not OpenAI product
advice, website building, Neon, or Playwright.
