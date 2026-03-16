# Coding Standards — All Agents

These standards apply to **every agent** that writes code. No exceptions.

## Git Workflow

### Branch Policy
- **Never commit directly to `main`**
- All work must be done on a **feature branch**
- Branch naming: `<agent-id>/<short-description>` (e.g. `siteconfig/add-lambda-handler`)
- Keep branches focused — one feature/fix per branch

### Pull Requests
- All changes go through a **Pull Request** before merge
- PR title must be descriptive (not "fix stuff")
- PR description must explain **what** and **why**
- Link related issues if they exist

### Code Review
- Every PR must be **reviewed by Gemini** (automated review)
- All review comments must be **addressed** before merge
  - Fix the issue, or explain why you disagree
  - Don't ignore comments
- No merging with unresolved conversations

### CI/CD
- **CI must be green** before merge — no exceptions
- If CI fails, fix it. Don't skip or retry and hope.
- If CI is flaky, fix the flakiness — don't normalise red builds

## Test Coverage

### Coverage Rules
- Test coverage must **never decrease** on a PR
- New code should include tests
- If you're fixing a bug, add a test that reproduces it first
- Coverage gates are enforced in CI — don't try to bypass them

### Testing Principles
- Test behaviour, not implementation
- Tests must be deterministic — no flaky tests
- Mock external dependencies, not internal logic
- Name tests clearly: `test_<what>_<condition>_<expected>`

## Code Quality

### General
- Write clean, readable code — future you will thank present you
- Handle errors explicitly — no silent failures
- Log structured output (JSON preferred) — not printf debugging
- Keep functions small and focused
- Comment **why**, not **what** (the code says what)

### Security
- No credentials in code — use environment variables or secrets
- Least-privilege for IAM/permissions
- Validate inputs, especially from external sources
- Flag security concerns in PR reviews proactively

## Commit Messages

Follow conventional commits:
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `ci`, `chore`

Examples:
```
feat(miner-client): add hashrate anomaly detection
fix(edgex): handle modbus timeout on device disconnect
test(vpp-api): add integration tests for bidder endpoint
docs(infra): update k8s deployment architecture
```

## Agent-Specific Notes

Each agent should add their own domain-specific standards to their workspace `AGENTS.md`. These are the **baseline** — agents can be stricter, never looser.
