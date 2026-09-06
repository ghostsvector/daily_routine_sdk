# Changelog

Generated from git commit history between tags (`.github/workflows/release.yml`
runs `git log <previous-tag>..<tag>` on every tagged release and prepends the
result here) — not GitHub's PR-based release notes, since this repo pushes
directly to `main` rather than through pull requests, which left the
auto-generated notes essentially empty. Not hand-edited; if a description here
is wrong, the fix is a better commit message on the next push, not editing
this file directly.

## v0.1.7 — 2026-09-06

- Add task-completion counts to ActivitySummary

## v0.1.6 — 2026-09-06

- Add Crashlytics-backed CrashReportingService

## v0.1.5 — 2026-09-06

- Switch poll/error logging from dart:developer to debugPrint

## v0.1.4 — 2026-09-04

- Add daily activity rollup + pruning to permanently cap read cost

## v0.1.3 — 2026-09-04

- Stop REST polling from running forever in the background, add logging

## v0.1.2 — 2026-09-04

- Fix Linux activity polling exhausting Firestore's read quota

## v0.1.1 — 2026-09-04

- Document activity/usage modules and add a security policy
- Update Chrome extension link to its new standalone repo
- Fetch full history in release workflow to fix gh release create bug
- Make routine task completion reset daily
- Bump version to 0.1.1 for release

## v0.1.0 — 2026-09-02

- first commit
- Add isAlarm field to RoutineTask for full-screen alarm-style reminders
- Update compileSdk version to 37 for compatibility with flutter_secure_storage
- Implement app usage tracking feature with foreground service and Firestore integration
- Add desktop app usage tracking implementation and update related models
- Implement FirestoreActivityRepositoryService with REST fallback for Linux and enhance ActivityEvent handling
- Add CI and tag-triggered release workflows
