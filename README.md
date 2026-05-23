# Pulsar

## Oura OAuth Setup

Pulsar uses Oura's OAuth authorization-code flow for production. Oura's token endpoint requires the developer app `client_secret` for code exchange and token refresh, so the iOS app must never contain the client secret. Keep `OURA_CLIENT_SECRET` only on the backend.

Official Oura endpoints:

- Authorization URL: `https://cloud.ouraring.com/oauth/authorize`
- Token URL: `https://api.ouraring.com/oauth/token`

### 1. Create an Oura developer app

1. Open the Oura developer portal and create an application.
2. Copy the app's Client ID.
3. Configure this redirect URI exactly:

```text
aetherial-pulsar://oura/oauth/callback
```

### 2. Configure Pulsar's local xcconfig

The iOS app reads these Info.plist keys, all populated by build settings from `Config/Oura.shared.xcconfig` plus your local override:

- `OuraOAuthClientID`
- `OuraOAuthRedirectURI`
- `OuraOAuthScopes`
- `OuraBackendBaseURL`

Copy the example file:

```sh
cp Config/Oura.local.xcconfig.example Config/Oura.local.xcconfig
```

Edit `Config/Oura.local.xcconfig`:

```xcconfig
OURA_CLIENT_ID = your_oura_client_id
OURA_OAUTH_REDIRECT_URI = aetherial-pulsar:/$()/oura/oauth/callback
OURA_OAUTH_SCOPES = email personal daily heartrate workout tag session spo2
OURA_BACKEND_BASE_URL = https:/$()/www.aetherial.tech/api
OURA_MOCK_MODE = NO
```

`Config/Oura.local.xcconfig` is git-ignored. Do not add `OURA_CLIENT_SECRET` to any iOS xcconfig or Info.plist.

### 3. Configure the hosted backend token exchanger

Pulsar's hosted Oura token backend currently lives at:

```text
https://www.aetherial.tech/api
```

Set these environment variables on the website host, not in the iOS app:

```text
OURA_CLIENT_ID
OURA_CLIENT_SECRET
OURA_REDIRECT_URI=aetherial-pulsar://oura/oauth/callback
```

Check the backend before testing the app:

```sh
curl https://www.aetherial.tech/api/health
```

The response should include `"ok":true`, `"service":"pulsar-oura-backend"`, and `"configured":true`.

When these values are configured, tapping **Connect Oura** opens the real Oura login/authorization page. If a required value is missing, DEBUG builds log the missing key with `[PulsarOura]`; Release builds show a user-friendly unavailable message.

For local backend development before the hosted API is ready, copy `Backend/OuraOAuthServer/.env.example` to `.env`, fill in the same Oura values, run `./scripts/start-oura-backend.sh`, and temporarily point `OURA_BACKEND_BASE_URL` to `http:/$()/127.0.0.1:8787` for simulator or your Mac LAN IP for physical iPhone.
