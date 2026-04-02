---
name: gitversion-handling
description: 'Diagnose and fix GitVersion SemVer and InformationalVersion mismatches in this repo. Use when RUNME.ps1 tests fail, release/* versions are unexpected, or GitVersion mode/branch settings need correction. Includes mode selection rules and verification steps grounded in official docs.'
argument-hint: 'Describe the mismatch and expected version behavior'
user-invocable: true
---

# GitVersion Handling

## When to Use
- RUNME scenarios fail because `SemVer`, `FullSemVer`, or `InformationalVersion` are not what you expected.
- Release branch versions do not move the way the team expects.
- You need to change only GitVersion config (not test cases) to satisfy versioning requirements.

## Key Truths From GitVersion Docs
- `SemVer` is `Major.Minor.Patch` plus pre-release tag (if present).
- `FullSemVer` is fully SemVer 2.0 compliant and includes build metadata.
- `InformationalVersion` defaults to `FullSemVer` suffixed by branch/SHA metadata.
- `ContinuousDeployment`: same semantic version for commits until a new tag is created.
- `ContinuousDelivery`: commits advance pre-release/build metadata between tags.
- `Mainline`: enabled with global `mode: Mainline`; expensive over long history, so tag periodically.
- `version-in-branch-pattern` only applies when `is-release-branch: true`.

References: see [GitVersion Notes](./references/gitversion-doc-notes.md).

## Procedure
1. Baseline the current behavior.
- Run `./RUNME.ps1` from repo root.
- Capture failing scenarios and actual values from the overview table.

2. Inspect effective GitVersion config.
- Run `gitversion /showConfig` in the sandbox/repo context used by tests.
- Confirm which defaults and overrides are active.

3. Decide expected behavior before editing.
- If you want stable same-version-until-tag behavior, use `ContinuousDeployment`.
- If you want incrementing versions between tags, prefer `ContinuousDelivery` or `Mainline` (global mode).
- If you want release branch version extraction from branch name, ensure `is-release-branch: true` and regex supports your naming.

4. Edit only `Config/ReleaseBranches.yml`.
- Avoid changing `RUNME.ps1` when the requirement says expected cases are authoritative.
- Keep changes minimal and localized.

5. Validate after every edit.
- Re-run `./RUNME.ps1`.
- Check both pass/fail counts and the release rows in the overview (`SemVer` and `InformationalVersion`).

6. If outcomes still mismatch, branch by symptom.
- Symptom: `x.y.0` repeated after tag despite many commits.
  Action: You are likely in `ContinuousDeployment`; switch mode only if expected behavior requires increments between tags.
- Symptom: `x.y.z-n` pre-release output when stable `x.y.z` expected.
  Action: `ContinuousDelivery` behavior is active; re-evaluate branch mode and labels.
- Symptom: branch not recognized as release.
  Action: fix `branches.release.regex` and ensure `is-release-branch: true`.
- Symptom: config errors or all tests fail unexpectedly.
  Action: check for invalid mode placement (for example, unsupported branch-level mode), then verify with `gitversion /showConfig`.

7. Completion checks.
- `Tests Passed: 9, Failed: 0`.
- Release scenarios match expected values.
- No non-config files changed unless explicitly requested.

## Guardrails
- Do not add custom interpretation logic in scripts if the requirement is "GitVersion output only."
- Prefer official mode semantics over ad-hoc patch math.
- Keep `RUNME.ps1` untouched unless the user explicitly asks for test expectation changes.
