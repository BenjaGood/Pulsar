# Oura API Integration

Reviewed: 2026-05-20

## Summary

Pulsar treats Oura Ring as a cloud-synced health source, not as a live Bluetooth sensor. The public Oura API integration point is Oura API V2 over HTTPS with OAuth2 bearer tokens. There is no public Oura API V2 route for direct ring Bluetooth streaming, so Pulsar must show last successful cloud sync time and avoid real-time wording.

Production authentication uses the OAuth2 authorization-code flow. Oura's official authentication docs list `client_secret` as required for token exchange and refresh unless HTTP Basic auth is used, and Basic auth still uses the same client secret. The official docs do not document PKCE parameters such as `code_challenge`, `code_challenge_method`, or `code_verifier` for Oura OAuth. Therefore Pulsar must not perform a direct public-client code exchange from iOS.

Pulsar opens Oura authorization on-device with `ASWebAuthenticationSession`, receives the custom-scheme redirect URI, validates `state`, and sends the authorization code to a minimal backend token service. The backend exchanges and refreshes tokens with Oura while keeping `OURA_CLIENT_SECRET` server-side. The iOS app stores returned access and refresh tokens in Keychain.

Sources:

- Oura V2 docs: https://cloud.ouraring.com/v2/docs
- Oura OAuth/authentication docs: https://cloud.ouraring.com/docs/authentication
- Oura API errors and rate limits: https://cloud.ouraring.com/docs/error-handling
- Oura membership/API access note: https://support.ouraring.com/hc/en-us/articles/4415266939155-The-Oura-API

## Production OAuth Flow

1. Register a Pulsar OAuth application in the Oura developer portal.
2. Configure redirect URI: `aetherial-pulsar://oura/oauth/callback`.
3. Start or deploy `Backend/OuraOAuthServer` with:
   - `OURA_CLIENT_ID`
   - `OURA_CLIENT_SECRET`
   - `OURA_REDIRECT_URI=aetherial-pulsar://oura/oauth/callback`
4. Add these iOS build settings or xcconfig values:
   - `OURA_CLIENT_ID`
   - `OURA_OAUTH_REDIRECT_URI=aetherial-pulsar://oura/oauth/callback`
   - `OURA_OAUTH_SCOPES=email personal daily heartrate workout tag session spo2`
   - `OURA_BACKEND_BASE_URL=https://www.aetherial.tech/api`
   - Optional dev mode: `OURA_MOCK_MODE=true`
   These populate the app Info.plist keys `OuraOAuthClientID`, `OuraOAuthRedirectURI`, `OuraOAuthScopes`, and `OuraBackendBaseURL`.
5. iOS starts `ASWebAuthenticationSession` at `https://cloud.ouraring.com/oauth/authorize` with `response_type=code`, `client_id`, `redirect_uri`, scopes, and a random `state`.
6. Before opening Oura, iOS calls `GET /health` on `OURA_BACKEND_BASE_URL`; if the backend is not reachable, the app stops and shows an actionable setup error instead of launching a login that cannot finish.
7. iOS parses `code`, `scope`, and `state`, verifies state, then calls Pulsar's backend token exchange endpoint.
8. Backend calls `https://api.ouraring.com/oauth/token` with `grant_type=authorization_code`, `code`, `redirect_uri`, `client_id`, and `client_secret`.
9. iOS receives access/refresh tokens from the backend and stores them in Keychain.
10. Before sync, iOS refreshes expiring tokens through the backend. Oura refresh tokens are single-use, so the returned refresh token replaces the old one.
11. Disconnect calls the optional backend revoke endpoint and always deletes local Keychain credentials.

Do not use Personal Access Tokens for production. They are useful for manual developer inspection only.

## Scopes

Pulsar requests the minimal set needed for the current feature:

| Scope | Used for |
| --- | --- |
| `personal` | Oura user profile and account identity. |
| `email` | Optional account email display/debug attribution if the user grants it. |
| `daily` | Daily sleep, readiness/recovery, activity, stress, resilience, and related daily summaries. |
| `heartrate` | Time-series heart rate samples, HRV context, and resting/active HR support. |
| `workout` | Auto-detected and user-entered workouts. |
| `tag` | User-entered tags when useful for future context or annotations. |
| `session` | Guided/unguided sessions where available. |
| `spo2` | Daily sleep SpO2 average when available. |

The configured default scope string is `email personal daily heartrate workout tag session spo2`.

## Endpoints

The Oura API client fetches these V2 cloud endpoints through `https://api.ouraring.com/v2/usercollection`:

- `personal_info`
- `daily_sleep`
- `sleep`
- `daily_readiness`
- `daily_activity`
- `heartrate`
- `workout`
- `session`
- `daily_spo2`
- `daily_stress`
- `daily_resilience`

`ring_configuration` is supported by Oura but requires the separate `ring_configuration` scope. Pulsar does not request that scope by default, so the client only calls this endpoint when a token explicitly includes it.

Optional or account-dependent endpoints are best-effort. `403` and `404` on optional routes are logged with `[PulsarOura]` and skipped so one missing entitlement does not break the whole sync.

## Mapping

Oura data is normalized in `OuraDataMapper`; SwiftUI views do not call Oura endpoints directly.

| Oura data | Pulsar model |
| --- | --- |
| `daily_sleep.score`, `sleep.total_sleep_duration`, stages | `PulsarSleepSyncMetric` |
| `daily_readiness.score`, contributors, HRV/RHR/temp from sleep | `PulsarRecoverySyncMetric` |
| `sleep.average_hrv` | HRV health metric and canonical HRV sample |
| `sleep.lowest_heart_rate` / `average_heart_rate` | Resting HR health metric |
| `sleep.respiratory_rate` | Respiratory health metric |
| `sleep.temperature_deviation` / readiness temperature | Wrist temperature deviation |
| `daily_activity.score`, steps, active calories, activity time | `PulsarStrainSyncMetric` |
| `workout` | Canonical workout samples and strain workout load |
| `daily_spo2.spo2_percentage.average` | Oxygen saturation health metric |
| `daily_stress` | `PulsarStressSyncMetric` |
| `daily_resilience.level` | Stress/recovery context and stress score adjustment |

Assumptions:

- Oura sleep phase strings are adapted as `1=deep`, `2=core/light`, `3=REM`, `4=awake`; unknown values become unspecified sleep.
- Oura resilience is categorical, not a 0-100 Pulsar score. Pulsar uses it as context and a small adjustment to the daily stress metric, not as a standalone recovery score.
- Oura does not expose a public women’s health/cycle endpoint in the scopes/endpoints confirmed for this integration. Pulsar uses Oura temperature deviation/trends for temperature and cycle-related insight support, but cycle events remain sourced from Pulsar/iPhone/manual data unless a future Oura endpoint is added.

## Source Priority And Deduplication

Pulsar stores user source preferences per category:

- Sleep & Recovery Source
- Workout Source
- Heart Metrics Source
- Temperature & Cycle Source

Default behavior favors Oura for sleep/recovery, heart metrics, and temperature/cycle trends, while Apple Watch remains preferred for workouts/activity. If the preferred source is missing or stale and fallback is enabled, `HealthSourcePriorityResolver` selects the next usable source and UI can show “Using fallback source.” `HealthSampleDeduplicator` removes overlapping canonical samples by metric/time and keeps the sample from the currently preferred source order.

## Limitations

- Oura API V2 is cloud-synced. Pulsar cannot force direct ring Bluetooth sync or stream live ring sensor data.
- API data freshness depends on Oura app/ring sync and Oura’s processing pipeline. Sleep/readiness data may not be available until the user opens/syncs the Oura app; activity, stress, and heart rate may update periodically in the background. Pulsar shows last successful sync and supports manual “Sync now.”
- Oura documents V1/V2 rate limiting at 5000 requests per 5 minutes. Pulsar handles `429` and `Retry-After` and should prefer background-safe, user-initiated, and batched sync over polling.
- Gen3 and Oura Ring 4 users need active Oura Membership for API access. The user for this integration has an active membership, but Pulsar still surfaces auth/sync errors clearly.
- Some endpoints are generation, membership, scope, or feature dependent. SpO2, stress, resilience, and sessions may be absent.

## Backend Contract

Minimal backend endpoints expected by the iOS app are scaffolded in `Backend/OuraOAuthServer`:

`POST /oura/token/exchange`

```json
{
  "code": "authorization-code",
  "redirect_uri": "aetherial-pulsar://oura/oauth/callback",
  "requested_scopes": ["daily", "heartrate"]
}
```

Response:

```json
{
  "token_type": "bearer",
  "access_token": "...",
  "refresh_token": "...",
  "expires_in": 86400,
  "scope": "daily heartrate"
}
```

`POST /oura/token/refresh`

```json
{
  "refresh_token": "single-use-refresh-token"
}
```

Optional `POST /oura/disconnect`:

```json
{
  "access_token": "...",
  "refresh_token": "..."
}
```

The backend must never return the Oura client secret to the app and should avoid logging tokens or health payloads.

## Development Mode

For the hosted production-style OAuth flow:

1. Configure the Oura developer portal redirect URI: `aetherial-pulsar://oura/oauth/callback`.
2. Set these environment variables on the hosted website backend:

```text
OURA_CLIENT_ID
OURA_CLIENT_SECRET
OURA_REDIRECT_URI=aetherial-pulsar://oura/oauth/callback
```

3. Confirm `/health` works before launching Pulsar:

```sh
curl https://www.aetherial.tech/api/health
```

Expected response:

```json
{ "ok": true, "service": "pulsar-oura-backend", "configured": true }
```

4. Copy the local xcconfig template and fill in the Client ID and hosted backend base URL:

```sh
cp Config/Oura.local.xcconfig.example Config/Oura.local.xcconfig
```

```xcconfig
OURA_CLIENT_ID = <your Oura client id>
OURA_OAUTH_REDIRECT_URI = aetherial-pulsar:/$()/oura/oauth/callback
OURA_OAUTH_SCOPES = email personal daily heartrate workout tag session spo2
OURA_BACKEND_BASE_URL = https:/$()/www.aetherial.tech/api
```

For a real local backend flow before the hosted API is ready:

```sh
cp Backend/OuraOAuthServer/.env.example Backend/OuraOAuthServer/.env
# Fill in OURA_CLIENT_ID, OURA_CLIENT_SECRET, and OURA_REDIRECT_URI.
./scripts/start-oura-backend.sh
```

Then temporarily set:

```xcconfig
OURA_BACKEND_BASE_URL = http:/$()/127.0.0.1:8787
```

For physical devices, use a LAN host or development HTTPS tunnel instead of `127.0.0.1`. Find the Mac LAN IP with `ipconfig getifaddr en0`, keep both devices on the same Wi-Fi, and allow the backend port through macOS firewall if prompted.

Set `OURA_MOCK_MODE=true` or `UserDefaults` key `pulsar.oura.mockMode.v1` only when you want to test the Devices UI and sync pipeline without a real Oura account. Mock mode creates a local test token and uses `MockOuraAPIClient` with deterministic sleep, readiness, activity, HR, SpO2, stress, resilience, and workout data.
