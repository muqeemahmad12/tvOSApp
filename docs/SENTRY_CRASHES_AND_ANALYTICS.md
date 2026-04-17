# Sentry: crashes & analytics

This app uses **[Sentry](https://sentry.io)** for **crash reporting** and **lightweight product analytics** (not Firebase Crashlytics / Google Analytics).

---

## 1. Analytics integration

### Role

Structured **funnel / product** signals (config loaded, heartbeat, activation, playlist) are sent as Sentry **message** events at **info** level. They count toward **org error / event quota** on the free plan—same pool as real errors—so treat `track` as **high-signal only**, not per-frame logging.

### API (`SentryService`)

| Method | Use |
|--------|-----|
| `track(_:)` | Event name only (`SentryAnalyticsEvent` string). |
| `track(_:attributes:)` | Event + string attributes (must use **`attributes:`** label). Tag keys ≤ 32 chars, values ≤ 200. |
| `track(_:attributes:sampleRate:)` | Same as above; **`sampleRate`** in `0...1` (default `1`). Use `< 1` for noisy paths to **sample** and save quota (e.g. `0.25` ≈ 25% of sends). |
| `breadcrumb(category:message:data:)` | **Cheap** trail attached to the **next** error/crash—not a separate billable “issue” like each `track`. Use for step-by-step context. |

Every `track` event also sets tag **`analytics_event`** = the full event name (same as message), so Discover can filter `analytics_event:app.playlist.loaded` even when the Issues feed is noisy.

### Naming convention

Event names live in **`SentryAnalyticsEvent`** and follow **`app.<area>.<action>`** (e.g. `app.heartbeat.initial_success`). Keeps Discover search and issue titles consistent.

### Where to look in Sentry

- **Environment** is built from tv-config **`activation_base_url`** and **`drs_base_url`** hosts: one host if both match, otherwise `activationHost|drsHost`. Use **All environments** or that exact string in Sentry filters.
- **Discover:** query e.g. `message:"app.lifecycle.launch"` or `analytics_event:app.playlist.loaded`, time range **Last 24h**, correct **project** (DSN).
- **Issues:** info-level message issues may not dominate the default **Feed**; use Discover or clear filters / include resolved.

### `track` vs `breadcrumb`

| | `track` | `breadcrumb` |
|---|---------|----------------|
| **Purpose** | Funnel milestones you want to **count and graph** | Debugging **trail** before a failure |
| **Quota** | Each send is a full event | Breadcrumb payload on next error |
| **Example** | `app.activation.saved` | `credentials_saved` under `activation` |

### Current call sites (Swift)

| Area | `track` | `breadcrumb` |
|------|---------|----------------|
| App bootstrap | `app.lifecycle.launch` (after config + Sentry + device scope; attrs: `config_key`, `device_activated`) | `app_launch`, `tv_config_ready` (`lifecycle`) |
| Heartbeat | `initialHeartbeatSuccess` / `initialHeartbeatFailed` | `initial_ok` / `initial_failed` (`heartbeat`) |
| Activation | `activationSaved` (attrs), `activationCleared` | `credentials_saved` / `credentials_cleared` (`activation`) |
| Screen / phase | `app.screen.playing_phase` (RootView: cold start + phase → playing), `app.screen.activation_flow` (ActivationView appear) | `playing_phase`, `activation_flow_visible` (`lifecycle`) |
| Playback | `app.playback.started` / `app.playback.stopped` (first real group / `stop()`) | `started` / `stopped` (`playback`) |
| Ads | `app.ad.impression` (`item_id`, `asset_type`, `sequence`; **sampleRate 0.2**) | — |
| Error UI | `app.error_screen.activation_failed`, `connection_lost`, `waiting_for_content` | `*_visible` (`error_ui`) |
| Network | `app.network.connectivity_lost` / `connectivity_restored` (reason tag) | `connectivity_lost` / `connectivity_restored` (`network`) |
| Playlist | `playlistLoaded`, `playlistEmpty`, `playlistFetchFailed`, `playlistUsedCache` | `empty_response`, fetch details, `cache_fallback_after_error` (`playlist`) |

**POC test crash (DEBUG):** `SentryService.shared.triggerTestCrashForPOC()` raises an `NSException` for Issues + symbolication checks. Trigger it either from LLDB (`expr -l Swift -- SentryService.shared.triggerTestCrashForPOC()`) or by launching with `--sentry-crash-test` (already present in the shared app scheme). The launch-arg trigger is one-time per app install so the next launch can upload the crash.

### Adding new analytics

1. Add a constant to **`SentryAnalyticsEvent`** in `SentryService.swift`.
2. Call **`SentryService.shared.track(...)`** at the right lifecycle point; pair with **`breadcrumb`** if you need a trail toward crashes.
3. Keep attribute keys/values short (enforced in code). Prefer **low-cardinality** tag values for filtering.
4. If an event could fire very often, add **`sampleRate:`** on `track` (or split “always track failure” vs “sample success”).

DSN: `AppConfig` / Info.plist `SENTRY_DSN`, or built-in fallback in `SentryService.start()`.

---

## 2. Crash reporting

### What is captured

- **Uncaught native crashes** (signals, watchdogs where applicable) and **Swift runtime failures** that terminate the process, once `SentryService.start()` has run.
- **App hangs (main thread):** `enableAppHangTracking` is enabled in `SentryService.start()` so long main-thread stalls can surface as issues (tvOS / SDK permitting).
- **Non-fatal errors:** `SentryService.capture(error:)` or **`capture(error:tags:)`** — use tags such as `layer` / `reason` so Issues are easy to filter (e.g. playback sync fallback).

### Release & symbolication

- **`releaseName`** is set to `{bundleId}@{CFBundleShortVersionString}+{CFBundleVersion}` and **`dist`** to the build number so events line up with **debug symbols** in Sentry.
- **Release** builds use **dSYM** (`DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` in the project). Upload symbols to Sentry via **Xcode Organizer**, **Sentry Xcode plugin**, or **`sentry-cli upload-dif`** so stack traces are human-readable.

### Context on crashes

- **User context:** `userId` = saved **device code** after activation (for grouping). Cleared when activation is wiped.
- **Tags:** `backend_host` (activation URL host), `app_version`, `screen_id` (after activation).
- **Device (tvOS):** After `start()`, `attachDeviceContext(environment:)` runs on the main thread and adds tags `platform`, `os_version`, `device_machine` (sysctl `hw.model`, e.g. `AppleTV14,1`), `device_marketing_model`, `screen_resolution_points`, `screen_resolution_native_px`, plus a **`device`** context object with the same fields (and `backend_host` / `app_version`) for every event.
- **Sessions:** `enableAutoSessionTracking` + release health in Sentry.
- **Last run crashed:** `onCrashedLastRun` logs to the Xcode console when the previous launch ended in a crash (useful for local QA; you can later hook UI from the same callback).

### Options (tuning)

- **`attachStacktrace`** is on for errors with stack samples where applicable.
- **Performance:** `tracesSampleRate` 0.2 (adjust in `SentryService.start()`).
