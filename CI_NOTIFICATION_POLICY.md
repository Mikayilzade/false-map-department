# CI / EMAIL NOISE POLICY

This repository must not recreate the notification storm seen in earlier autonomous implementation work.

## Hard rule
Do **not** enable push-triggered GitHub Actions for an unstable or expected-to-fail test suite.

During Phase 12A and early 12B:
- run Godot/headless/unit tests locally inside the implementation session whenever possible;
- keep commits coherent rather than committing every micro-fix;
- if remote CI is needed before the baseline is stable, prefer manual `workflow_dispatch` runs;
- only enable automatic `push`/PR CI after the baseline suite is consistently green;
- if a new CI change starts producing repeated failing runs, disable or return it to manual-only until fixed;
- never intentionally generate repeated failing workflow runs merely to probe the environment.

GitHub email delivery itself is controlled by the account/repository notification settings, not by game code. Therefore this policy reduces the source of email spam: repeated failing Actions runs.

This policy is part of the autonomous implementation handoff and must be read before creating CI workflows.
