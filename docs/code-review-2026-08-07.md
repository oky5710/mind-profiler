# Code Review — 2026-08-07

## Review metadata

- Reviewed revision: `1a92a22` (`main`)
- Reviewer completed: Codex
- Second reviewer: Claude — pending; append confirmations or disagreements under the Claude section below
- Validation: iOS Simulator Debug build succeeded on 2026-08-07
- Build output: no compiler errors; only the informational App Intents metadata warning
- Scope: recent local rMSSD cache, sleep aggregation, HRV Trend, bundled cat-photo splash, and adjacent data flows

## Codex findings

### [High] A local cache creation failure terminates the whole app

- Location: `Services/RMSSDLocalStore.swift:15-40`
- Evidence: every setup error, including a corrupt SwiftData store, unavailable Application Support directory, or file-protection error, reaches `fatalError`.
- Impact: a disposable calculation cache can prevent the user from opening the app. Reinstalling may be the only recovery visible to the user.
- Recommendation: distinguish directory/protection warnings from store-open failure. For a store-open failure, move the corrupt cache aside and recreate it; if recreation also fails, disable the cache for that session and surface a recoverable error instead of terminating.

### [Medium] A merged sleep gap is not necessarily counted as awake time

- Locations: `Services/SleepAnalysisService.swift:16-18`, `ViewModels/HomeViewModel.swift:371-397`, `Views/HRVAnalysis/HRVAnalysisView.swift:1110-1148`
- Evidence: `buildSleepRanges` merges two asleep ranges separated by up to two hours. Total awake duration and longest continuous sleep are calculated only from explicit `.awake` HealthKit samples. If the gap has no category sample at all, it expands the sleep window but contributes zero minutes to `awakeDuration`.
- Impact: the UI can show one merged night while understating total awake time and overstating longest continuous sleep. The current documentation says the empty gap is treated as awake, which is stronger than the implementation.
- Recommendation: derive uncovered intervals inside the merged sleep window and union them with explicit `.awake` intervals before calculating continuity metrics. Add cases for an explicit awake sample, an empty gap, and overlapping stage samples.

### [Medium] Overlapping sleep-stage samples can be counted more than once

- Location: `Services/SleepAnalysisService.swift:73-82`
- Evidence: stage duration is the direct sum of every sample duration in a group. HealthKit can contain overlapping sleep samples from multiple sources or overlapping stage corrections.
- Impact: total sleep duration and the derived sleep score can exceed the actual covered sleeping time; reports, briefing clues, and long-term cases share this result.
- Recommendation: normalize overlapping intervals before summing. Prefer the most specific stage over `.unspecified`, and define a deterministic source/overlap policy.

### [Medium] Splash image discovery depends on a duplicated hard-coded folder list

- Location: `Services/CatPhotoService.swift:5-15`
- Evidence: the service lists all 16 category directory names separately from the actual `Resources/CatPhotos` hierarchy.
- Impact: adding or renaming a resource folder succeeds at build time but its photos are silently excluded from random selection until this array is updated.
- Recommendation: enumerate the `CatPhotos` bundle directory recursively, filter regular `.jpg` files, and select from that result. A generated manifest is another deterministic option.

### [Low] Splash JPEG decoding runs in the view task's actor context

- Locations: `App/MindProfilerApp.swift:94-97`, `Services/CatPhotoService.swift:16-18`
- Evidence: random resource enumeration and `CGImageSourceCreateImageAtIndex` are synchronous operations invoked directly from the SwiftUI `.task` closure.
- Impact: the images are now compressed and bounded to 1600px, so the pause should usually be small, but decoding can still consume part of the 1.5-second splash animation budget on slower devices.
- Recommendation: perform URL discovery and decoding in a non-main isolated service operation, then publish the decoded image on the main actor. Measure launch performance before treating this as release-blocking.

### [Low] The custom RMSSD operation queue is not cancellation-aware

- Location: `Services/RMSSDLocalStore.swift:77-94`
- Evidence: a cancelled caller waiting in `withCheckedContinuation` remains in `operationWaiters` and is resumed later as normal.
- Impact: rapid navigation can execute an obsolete HealthKit/cache request after its view task was cancelled, increasing latency for the next relevant request.
- Recommendation: replace the continuation gate with an actor-owned coalescing task keyed by date range, or track waiter IDs and remove cancelled waiters with a cancellation handler.

## Release and test gaps

- Confirm redistribution rights and retain a source/license manifest for all 385 bundled photos. Renaming files removed the original author-oriented filenames from the project copy.
- Add unit tests for sleep merging at `1:59:59`, exactly `2:00:00`, and `2:00:01`, including both explicit-awake and no-sample gaps.
- Add tests for overlapping sleep stages and for `RMSSDLocalStore` aggregation-version migration.
- Add a bundle-resource test that asserts at least one readable photo exists and that every included category is discoverable.
- The current compressed photo payload is about 59MB; monitor archived IPA and App Store cellular-download size rather than relying only on the 95MB simulator app size.

## Claude review

Reviewed at `1a92a22` by reading each cited file directly (not just the Codex text). All six findings hold up; no disagreements. One addition below.

### [High] Local cache fatalError — Confirmed

- `Services/RMSSDLocalStore.swift:15-42`: `private init()` wraps schema/directory/`ModelContainer` setup in one `do` block; any failure (corrupt store, missing Application Support, protection-attribute failure) falls through to `fatalError` at line 40. `shared` is a lazy singleton, so this isn't a first-launch-only risk — a store corrupted mid-session (e.g., disk full, killed mid-write) crash-loops every subsequent launch until the user reinstalls or manually clears app data.

### [Medium] Merged sleep gap not counted as awake — Confirmed, and traced to a doc claim I introduced this session

- `Services/SleepAnalysisService.swift:16-18` merges asleep segments separated by ≤2h (`mergeGapThreshold`).
- `ViewModels/HomeViewModel.swift:369-399` (`briefingNight`) and `Views/HRVAnalysis/HRVAnalysisView.swift:1112-1154` (`makeContinuityMetrics`) both derive `awakeDuration`/`longestContinuousSleep` **only** from explicit `.awake` `SleepTimelineStage` samples (`timeline.filter { $0.stage == .awake ... }`) — a merged gap with zero category samples in it contributes nothing to `awakeDuration` and is silently walked through as sleep by the `cursor` loop that computes `longestContinuousSleep`.
- This directly contradicts `docs/features.md`'s sleep-merge line — "깨어 있던 공백은 총 수면시간에는 더하지 않고 해당 수면 사건의 각성 시간으로 계산한다" ("the awake gap isn't added to sleep time, it's counted as that sleep event's awake time") — which I wrote in commit `28d0cec` earlier in this session when the merge threshold moved from 1h to 2h. The doc describes the intended behavior; the two view-model implementations don't do it. This is a real doc/code mismatch I should fix, either by making the two continuity calculators fill uncovered intervals inside the merged window (matching the doc), or by weakening the doc claim to describe what actually happens today.
- Both locations share near-identical logic (merge `.awake` intervals, walk a cursor) — worth extracting into one shared helper regardless of which side of the fix is chosen, since a fix applied to only one of the two would leave the other silently wrong again.

### [Medium] Overlapping sleep-stage samples double-counted — Confirmed

- `Services/SleepAnalysisService.swift:73-84` (`flushGroup`): `durations[sample.stage, default: 0] += sample.end.timeIntervalSince(sample.start)` sums every sample's raw duration with no overlap normalization. Multiple sources (e.g., iPhone + Watch both logging sleep) or overlapping stage corrections inflate `stageDurations`, which feeds `sleepDuration`, the estimated sleep score, and every downstream sleep-duration-based signal (including the "수면 시간이 짧았어요" priority signal added this session — an inflated duration could mask a real shortage).

### [Medium] Hard-coded cat-photo category list — Confirmed

- `Services/CatPhotoService.swift:5-9` lists 16 category names by hand. `find Resources/CatPhotos -type d` currently shows exactly 16 subdirectories and 385 `.jpg` files, matching the Codex count — today's list is accurate, but nothing enforces that it stays that way. Adding/renaming a folder builds fine and just silently drops those photos from `randomPhoto()`'s pool.

### [Low] Splash decode on the calling actor — Confirmed

- `App/MindProfilerApp.swift:94-98` calls `CatPhotoService.randomPhoto()` (synchronous) directly inside `.task`, and SwiftUI's `.task` on a view runs on that view's actor (MainActor here, no `nonisolated`/`Task.detached` involved). `CatPhotoService.randomPhoto()` (`Services/CatPhotoService.swift:11-19`) does bundle URL enumeration across 16 subdirectories plus `CGImageSourceCreateImageAtIndex` synchronously — all on the main thread. Severity is correctly Low given the 1600px/compressed bound Codex noted, but it's real main-thread work inside the splash budget.

### [Low] Non-cancellation-aware operation queue — Confirmed

- `Services/RMSSDLocalStore.swift:79-95`: `acquireOperation()` suspends in `withCheckedContinuation` (not `withTaskCancellationHandler`), and `releaseOperation()` unconditionally does `operationWaiters.removeFirst().resume()`. A caller whose `Task` was cancelled while queued is resumed anyway and proceeds to run its now-obsolete HealthKit/cache request when its turn comes, rather than short-circuiting.

**Dual-reviewed**: yes, as of this entry. No findings were disputed; the sleep-gap finding additionally identifies a specific doc line (this session's) that needs to be reconciled with the code.
