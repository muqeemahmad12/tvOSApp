# Spark for DOOH — HTTP API reference

This document describes every outbound HTTP API the tvOS app uses: URLs, methods, headers, bodies, and response shapes as implemented in code. **Backend contracts may evolve**—verify against the live service when integrating.

---

## How base URLs are chosen

| Concern | Source |
|--------|--------|
| **Activation** host + path prefix | Remote `tv-config.json` → `activation_base_url`, then app appends path segments (see below). Fallback: `AppConfig` / Info.plist `ACTIVATION_BASE_URL`. |
| **DRS quest** host + path | Remote `drs_base_url`. If it already contains `/drs/v2`, app appends `/quest`. If it is host-only (e.g. `https://qa-drs-service.doceree.com`), app uses `{host}/drs/v2/quest`. Fallback: `AppConfig` `DRS_BASE_URL` + `drs/v2/quest`. |
| **Remote config** | Fixed GET URL (see §7). |
| **Heartbeat environment** (payload + Sentry tag) | Hostname of `activation_base_url` (e.g. `qa-keen.doceree.com`). |

Implementations: `TVRemoteConfigStore`, `TVRemoteConfigService`, `AppConfig`.

---

## 1. Remote TV config (bootstrap)

Loads before any other app API (retries until success).

| | |
|---|---|
| **Client** | `TVRemoteConfigService` |
| **Method** | `GET` |
| **URL** | `https://servedbydoceree.doceree.com/resources/p/spark-dooh/tv-config.json` |
| **Headers** | `Accept: application/json` |
| **Body** | — |

### Response (JSON)

Root object:

| Field | Type | Description |
|-------|------|-------------|
| `tvos` | object | Map of **CFBundleShortVersionString** (e.g. `"1.0.2"`) **or** `"default"` → entry |

Each **entry** (per key in `tvos`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `activation_base_url` | string | ✓ | Base URL for activation/heartbeat (no trailing slash normalized in app). |
| `drs_base_url` | string | ✓ | DRS service base (see path rules above). |
| `force_update` | bool | ✓ | Stored; drives `TVRemoteConfigStore.forceUpdate`. |
| `spark_portal_url` | string | optional | Activation QR web base; if omitted, `AppConfig.sparkPortalURL` is used. |

**Success:** HTTP 2xx, JSON decodable as above, non-empty activation + DRS URLs.  
**Persistence:** Successful entry is saved to UserDefaults (`com.doceree.sparkfordooh.tvRemoteConfig.cache`).

---

## 2. Activation — request device pairing

| | |
|---|---|
| **Client** | `ActivationAPI.requestActivation` |
| **Method** | `POST` |
| **URL** | `{activation_base_url}/dooh/device/activation/request` |
| **Headers** | `Content-Type: application/json` |
| **Body** | JSON — see table below |

### Request body — `ActivationRequest` (JSON keys = Swift property names, camelCase)

| Field | Type | Description |
|-------|------|-------------|
| `deviceId` | string | Device identifier used for activation. |
| `resolutionWidth` | int | Display width (px). |
| `resolutionHeight` | int | Display height (px). |
| `screenSizeInches` | int | Screen diagonal. |
| `orientation` | string | e.g. landscape/portrait. |
| `os` | string | OS name/version string. |
| `device` | string | Device model/name. |
| `brand` | string | Brand. |
| `manufacturer` | string | Manufacturer. |
| `latitude` | number | Location latitude (may be placeholder if unavailable). |
| `longitude` | number | Location longitude. |
| `ramGb` | number | RAM in GB. |
| `romGb` | number | Storage in GB. |

### Response — `ActivationResponse` + `ActivationData`

App treats HTTP 2xx and **`code == 200`** with non-nil `data` as success.

**Envelope (`ActivationResponse`):**

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | Server timestamp. |
| `code` | int | Business code; **200** = success for app logic. |
| `status` | string | Status string. |
| `message` | string | Human-readable message. |
| `data` | object? | Present on success. |

**`data` (`ActivationData`):**

| Field | Type | Description |
|-------|------|-------------|
| `deviceCode` | string | Device code for polling / headers. |
| `userCode` | string | User-facing pairing code (e.g. for QR flow). |
| `status` | string | Activation state from server. |
| `expiresAt` | string | Expiry for the pairing session. |

**Model file:** `Models/ActivationModel.swift`

---

## 3. Activation — poll until active

| | |
|---|---|
| **Client** | `ActivationPollAPI.pollOnce` / `pollUntilActivated` |
| **Method** | `POST` |
| **URL** | `{activation_base_url}/dooh/device/activation/poll` |
| **Headers** | `Content-Type: application/json` |
| **Body** | `{ "deviceCode": "<string>" }` |

### Response — `ActivationPollResponse` + `ActivationPollData`

App expects HTTP 2xx and **`code == 200`** with non-nil `data`.

**Envelope (`ActivationPollResponse`):** same shape as activation request envelope (`timestamp`, `code`, `status`, `message`, `data`).

**`data` (`ActivationPollData`):**

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | e.g. `ACTIVE`, `ACTIVATED`, `INACTIVE` (app compares case-insensitively for ACTIVE/ACTIVATED/INACTIVE). |
| `secureKey` | string? | Stored and used as **DRS / quest `x-api-key`** and for identification server-side. |
| `logoUrl` | string? | Optional branding asset URL. |
| `tickerMessage` | string? | Optional ticker text. |

**Polling behavior:** `pollUntilActivated` retries up to `maxAttempts` (default 20) with `delaySeconds` (default 15s). `INACTIVE` → `AppError.activationInactive`.

**Model file:** `Models/ActivationPollModel.swift`

---

## 4. Heartbeat (Keen / activation stack)

| | |
|---|---|
| **Client** | `HeartbeatAPI` (`sendHeartbeat`) |
| **Method** | `POST` |
| **URL** | `{activation_base_url}/dooh/device/heartbeat` |
| **Headers** | `Content-Type: application/json`, **`x-api-key`**: `AppConfig.apiKey` (Info.plist `API_KEY` or default) |
| **Body** | JSON object (see table) |
| **Timeout** | 30s |

### Request body (keys as sent by app)

| Field | Type | Description |
|-------|------|-------------|
| `screen_id` | string | From `AppConfig.screenId` (Info.plist `SCREEN_ID` or default). |
| `device_id` | string | `identifierForVendor` UUID (fallback random UUID). |
| `last_sync` | string | ISO8601; last playlist sync time, or `""`. |
| `last_played` | string | ISO8601; last ad playback update, or `""`. |
| `network_status` | string | Currently always `"connected"` (placeholder). |
| `deviceCode` | string | Saved device code from activation. |
| `secureKey` | string | Saved secure key from activation poll. |
| `timestamp` | string | ISO8601 “now”. |
| `status` | string | `"playing"` or `"idle"`. |
| `currentSequence` | int | Current sequence index in playlist. |
| `currentAdId` | string | Current ad id. |
| `appVersion` | string | `CFBundleShortVersionString`. |
| `osVersion` | string | `UIDevice.current.systemVersion`. |
| `environment` | string | **Hostname** of activation base URL from tv-config (not a hardcoded Dev/Prod flag). |

### Response

Decoded when possible as **`HeartbeatResponse`**:

| Field | Type | Description |
|-------|------|-------------|
| `code` | int? | Optional business code. |
| `message` | string? | Optional message. |
| `data` | object? | Nested payload. |
| `data.screenStatus` | string? | If **`INACTIVE`** (case-insensitive), app posts `heartbeatScreenStatusInactive` notification. |

Non-2xx HTTP → heartbeat treated as failure. Initial failure routes UI to registration; periodic interval default **20 minutes**.

---

## 5. DRS — playlist / item sequence (“quest”)

| | |
|---|---|
| **Client** | `APIService.fetchItemSeqInfo` |
| **Method** | `POST` |
| **URL** | `{resolved drs base}/drs/v2/quest` (see § “How base URLs”) |
| **Headers** | `Content-Type: application/json`; **`x-hs-key`**: `AppConfig.drsQuestApiKey` (Info.plist `DRS_QUEST_API_KEY` or default); **`x-dev-id`**: device code; **`x-api-key`**: activation **secureKey** (not the HS key). |
| **Body** | JSON — see below |

**Note:** The `screenId` argument to `fetchItemSeqInfo` is used by callers for logging/context; the **HTTP body only sends `reqNum`**—server derives screen from **`x-api-key` (secure key)** per app comments.

### Request body

| Field | Type | Description |
|-------|------|-------------|
| `reqNum` | int | Request sequence number (app increments per sync). |

### Response — `ItemSeqInfoResponse`

App decodes with **tolerant** `item1`: missing key → empty array.

| Field | Type | Description |
|-------|------|-------------|
| `screenid` | string? | Optional screen id. |
| `status` | string? | Optional status string. |
| `item1` | array | List of **`AdSequenceGroup`** (may be omitted → `[]`). |

**`AdSequenceGroup`:**

| Field | Type | Description |
|-------|------|-------------|
| `facilityid` | string | Facility identifier. |
| `sequence` | int | Playback order. |
| `ii` | array | List of **`AdItemModel`**. |
| `is_active` | bool | Inactive groups filtered out for playback. |

**`AdItemModel`** (JSON uses `is_flex` for `isFlex`):

| Field | Type | Description |
|-------|------|-------------|
| `itemid` | string | Unique ad id. |
| `assettype` | string | e.g. image / video. |
| `assetcat` | string? | Category. |
| `itemurl` | string | Media URL. |
| `itemsize` | string? | e.g. `"1920x1080"`. |
| `is_flex` | bool? | Flexible layout flag. |
| `trackerlist` | [string]? | Tracker URLs (see §6). |
| `itemspeciality` | string? | Optional. |
| `subcampaignid` | string? | Optional. |
| `schedulestarttime` | string? | Optional. |
| `scheduleendtime` | string? | Optional. |

**Convenience:** `groupedAds` = active groups sorted by `sequence`.

**Model file:** `Models/AdItemModel.swift`

---

## 6. Impression / tracker pixels

| | |
|---|---|
| **Client** | `TrackerService.fire` |
| **Method** | `GET` (one request per URL) |
| **URL** | Each string in `trackerlist` after placeholder replacement |
| **Headers** | Default URLSession |
| **Body** | — |

**Placeholder:** `{{EVENT_CLIENT_TIME}}` → client timestamp in **milliseconds** since Unix epoch.

**Behavior:** Best-effort, background, no retries; runs only after tv-config gate completes.

---

## 7. Weather (optional third-party)

| | |
|---|---|
| **Client** | `WeatherService` |
| **Provider** | OpenWeatherMap (if `WEATHER_API_KEY` in Info.plist) |
| **Otherwise** | Mock data — no network |

Not a Doceree API; see `WeatherService.swift` for query parameters if documenting externally.

---

## 8. Quick file map

| API | Swift module / file |
|-----|---------------------|
| TV config | `Services/TVRemoteConfigService.swift` |
| Activation request | `Services/ActivationAPI.swift`, `Models/ActivationModel.swift` |
| Activation poll | `Services/ActivationPollAPI.swift`, `Models/ActivationPollModel.swift` |
| Heartbeat | `Services/HeartbeatAPI.swift` |
| DRS quest | `Services/APIService.swift`, `Models/AdItemModel.swift` |
| Trackers | `Services/TrackerService.swift` |
| Keys / screen / fallbacks | `AppConfig.swift` |

---

## Changelog hint for maintainers

When changing headers or JSON fields, update this doc and the **Config** notes (`SparkForDOOH/Config/README.md` for tv-config shape). Quest auth uses **`x-hs-key`** (HS/static key) and **`x-api-key`** (per-device secure key from activation).
