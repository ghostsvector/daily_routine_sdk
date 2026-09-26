## v0.2.0 — 2026-09-26

- Update CHANGELOG.md for v0.1.11 [skip ci]
- Update release workflow's commit-signing email after account rename
- Reduce Linux desktop poll frequency to ease Firestore quota pressure
- Remove background polling from Linux desktop REST backends entirely
- Classify Firestore errors by HTTP status / error code instead of a blanket DatabaseError
- Remove stale pollInterval param from REST routine repo cache test
- Merge pull request #1 from ghostsvector/claude/fix-poll-interval-test
- Add AssistantService/VoiceService (Murthy LLM + voice, Linux desktop)
- Merge pull request #2 from ghostsvector/claude/assistant-service-linux
- Add Android implementations of AssistantService/VoiceService
- Fix AndroidLlamaAssistantService against llama_cpp_dart's real API
- Merge pull request #3 from ghostsvector/claude/assistant-service-android
- Add WakeWordService ("Hey Murthy") for Linux and Android
- Fix deprecated_member_use lints in AndroidSpeechWakeWordService
- Merge pull request #4 from ghostsvector/claude/wake-word
- Bump version to 0.2.0
- Merge pull request #5 from ghostsvector/claude/bump-version

## v0.1.11 — 2026-09-08

- Update CHANGELOG.md for v0.1.10 [skip ci]
- Add caching to the REST/Linux data path: instant last-known data + refresh-on-write

## v0.1.10 — 2026-09-07

- Update CHANGELOG.md for v0.1.9 [skip ci]
- Wire App Check debug tokens into every REST Firestore/Auth call

## v0.1.9 — 2026-09-07

- Update CHANGELOG.md for v0.1.8 [skip ci]
- Sign CI's automated CHANGELOG commits with a dedicated commit-signing key
- Add RFC 6238 TOTP service for app-level 2FA

## v0.1.8 — 2026-09-06

- Auto-generate CHANGELOG.md on every release
- Bump version to 0.1.8 for release
- Backfill CHANGELOG.md from commit history, fix release notes automation

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
