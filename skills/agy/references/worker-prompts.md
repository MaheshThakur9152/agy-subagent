# Worker prompts

agy workers start with no memory of your conversation. Every task must stand alone.

## Prompt contract

```text
ROLE: <role from the table below>
OBJECTIVE: <one or two sentences: what done looks like>
CONTEXT: <repo purpose, stack, how to run it, what the user already tried, relevant findings so far>
INSPECT: <exact files, dirs, modules, commands, URLs>
MAY CHANGE: <exact files/dirs this worker owns, or "nothing (read-only)">
CONSTRAINTS: <style, no new deps, keep API stable, time budget, no commits unless told>
DELIVERABLES: <findings with file:line evidence | patch | tests | plan>
TESTS: <commands the worker must run, and what must pass>
DONE WHEN: <checkable condition>
```

The runner appends the report format. Every worker ends with: Investigated, Changed, Files, Commands and tests, Errors or blockers, Remaining risks.

## Roles

Roles are focus instructions, not extra model abilities. Put the focus line into ROLE/OBJECTIVE.

| Role | Focus line | Typical mode |
|---|---|---|
| Backend Engineer | Server code, APIs, business logic. Implement or fix within MAY CHANGE; keep public interfaces stable. | unattended |
| Frontend Engineer | UI components, state, rendering, bundle. Measure before optimizing. | unattended |
| Database Engineer | Schema, queries, indexes, migrations. Show query plans; migrations must be reversible. | sandbox / unattended |
| Security Auditor | Find exploitable issues: authn, authz, injection, secrets, uploads, SSRF. Each finding: file:line, attack, impact, fix. Read-only. | sandbox |
| Performance Engineer | Measure first (timings, profiles). Rank bottlenecks by measured cost. No speculative fixes. | sandbox / unattended |
| Test Engineer | Write or fix tests for the named behavior; run them; report coverage gaps. | unattended |
| Code Reviewer | Review the named diff or files for bugs and risky changes. One line per finding with file:line. Read-only. | sandbox |
| Debugging Specialist | Reproduce, isolate root cause with evidence, propose the narrowest fix. Do not refactor. | unattended |
| Architecture Analyst | Map modules, data flow and dependencies for the named area. Output a short map and risks. Read-only. | sandbox |

## Examples

Single worker, debugging:

```text
ROLE: Performance Engineer
OBJECTIVE: Find why `python gen.py --prompt cat` takes ~115 s; identify the top time sinks with measurements.
CONTEXT: Image-generation pipeline in pipeline/ (diffusers, CUDA). Expected < 20 s on this GPU.
INSPECT: pipeline/gen.py, pipeline/model_loader.py, pipeline/postprocess.py
MAY CHANGE: nothing (read-only); temporary profiling scripts only under /tmp
CONSTRAINTS: Do not download new models.
DELIVERABLES: Ranked list of time sinks with seconds each and file:line; a recommended fix per item.
TESTS: Run `python -m cProfile -o /tmp/gen.prof gen.py --prompt cat` and summarize the top 15 entries.
DONE WHEN: Over 80% of wall time is attributed to specific code.
```

Parallel security audit (three workers, `--perm sandbox`, shared tree):
- Worker A: Security Auditor, authentication (`src/auth/**`, login, sessions, tokens).
- Worker B: Security Auditor, authorization (`src/api/**` route guards, role checks, IDOR).
- Worker C: Security Auditor, file uploads (`src/upload/**`, storage, content-type checks, path traversal).
Then merge findings, drop duplicates, verify each high-severity claim yourself.

Parallel implementation (worktrees, `--perm unattended`):
- Worker A: Backend Engineer, MAY CHANGE `src/cache/**` + its tests, commit on `agy/cache`.
- Worker B: Test Engineer, MAY CHANGE `tests/api/**`, commit on `agy/api-tests`.
Merge one branch at a time, run the full test suite after each.
