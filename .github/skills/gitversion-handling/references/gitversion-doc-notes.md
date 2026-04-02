# GitVersion Notes (From Official Docs)

Sources:
- https://gitversion.net/docs/reference/configuration
- https://gitversion.net/docs/reference/variables
- https://gitversion.net/docs/reference/modes/continuous-delivery
- https://gitversion.net/docs/reference/modes/continuous-deployment
- https://gitversion.net/docs/reference/modes/mainline

## Version Variables
- `SemVer`: semantic version including pre-release tag when present.
- `FullSemVer`: fully compliant SemVer 2.0 version.
- `InformationalVersion`: defaults to `FullSemVer` plus branch/SHA metadata.

## Mode Semantics
- `ContinuousDeployment`: same SemVer is produced for commits until the next tag.
- `ContinuousDelivery`: versions move between tags using pre-release/build metadata.
- `Mainline`: use global `mode: Mainline`; computes increments walking commits and merge history.

## Branch Config Facts
- `is-release-branch: true` marks release branch behavior.
- `version-in-branch-pattern` applies only on branches with `is-release-branch: true`.
- `source-branches` narrows merge-base candidates and improves accuracy/performance.

## Practical Verification
- `gitversion /showConfig` shows effective config with defaults + overrides.
- `gitversion /output json` reveals raw values consumed by tests.
