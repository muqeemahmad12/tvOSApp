# Sentry: crashes & analytics

This app uses **[Sentry](https://sentry.io)** for **crash reporting** and **lightweight product analytics** (not Firebase Crashlytics / Google Analytics).

## Crash reporting

- Uncaught crashes and non-fatals are captured automatically after `SentryService.start()`.
- **`capture(error:)`** is used for explicit non-fatal errors (e.g. playback).
- **User context:** `userId` = saved **device code** after activation (for grouping). Cleared when activation is wiped.
- **Tags:** `backend_host` (activation URL host), `app_version`, `screen_id` (after activation).
- **Sessions:** `enableAutoSessionTracking` + release health in Sentry.
- **Performance:** `tracesSampleRate` 0.2 (adjust in `SentryService.start()`). Profiling can be enabled when your Sentry Cocoa SDK exposes it on `Options`.

DSN: `AppConfig` / Info.plist `SENTRY_DSN`, or built-in fallback in code.

## Analytics (Sentry “issues” at level `info`)

Structured events use **`SentryService.track(_ event)`** (no attributes) or **`track(_ event, attributes: [String: String])`** — the second parameter must use the **`attributes:`** label. In Sentry, filter **Discover** or Issues by **level = info** (or by message name).

| Event constant | When |
|----------------|------|
| `app.tv_config.loaded` | After remote tv-config succeeds |
| `app.heartbeat.initial_success` | First heartbeat OK |
| `app.heartbeat.initial_failed` | First heartbeat failed (registration path) |
| `app.activation.saved` | Credentials saved to UserDefaults |
| `app.activation.cleared` | Activation cleared (e.g. INACTIVE) |
| `app.playlist.loaded` | Quest returned groups + items |
| `app.playlist.empty_response` | Quest returned no groups |
| `app.playlist.fetch_failed` | Quest error after retries |
| `app.playlist.used_cache_fallback` | Using cache after API failure |

**Breadcrumbs** (`breadcrumb(category:message:data:)`) attach to the next error/crash for debugging trails (playlist, heartbeat, lifecycle).

## Adding new events

1. Add a name to `SentryAnalyticsEvent` in `SentryService.swift`.
2. Call `SentryService.shared.track(...)` and/or `breadcrumb(...)` at the right lifecycle point.
3. Keep attribute values short (tags are capped in code).
