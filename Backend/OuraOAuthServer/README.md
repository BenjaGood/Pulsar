# Pulsar Oura OAuth Backend

Oura's official OAuth documentation for the authorization-code flow requires `client_secret` during code exchange and refresh unless HTTP Basic auth is used, which still requires the same secret. Do not ship `OURA_CLIENT_SECRET` inside the iOS app. This tiny backend keeps the secret server-side while allowing Pulsar for iOS to open the real Oura login page with `ASWebAuthenticationSession`.

## Environment

Copy `.env.example` to `.env` or export these variables before starting:

```sh
export OURA_CLIENT_ID="..."
export OURA_CLIENT_SECRET="..."
export OURA_REDIRECT_URI="aetherial-pulsar://oura/oauth/callback"
export PORT=8787
```

Optional browser smoke-test redirect:

```sh
export OURA_WEB_REDIRECT_URI="http://localhost:8787/oura/auth/callback"
```

## Run Locally

```sh
cp Backend/OuraOAuthServer/.env.example Backend/OuraOAuthServer/.env
# Fill in the Oura values, then from the repo root:
./scripts/start-oura-backend.sh
```

The backend listens on all local interfaces by default so a physical iPhone can reach it over Wi-Fi:

```sh
curl http://127.0.0.1:8787/health
```

For an iOS Simulator build, copy `Config/Oura.local.xcconfig.example` to `Config/Oura.local.xcconfig` and set:

```xcconfig
OURA_CLIENT_ID = <same client id>
OURA_OAUTH_REDIRECT_URI = aetherial-pulsar:/$()/oura/oauth/callback
OURA_OAUTH_SCOPES = email personal daily heartrate workout tag session spo2
OURA_BACKEND_BASE_URL = http:/$()/127.0.0.1:8787
```

For a physical iPhone, `127.0.0.1` points at the phone itself. Use your Mac's LAN URL or a development HTTPS tunnel instead:

```sh
ipconfig getifaddr en0
```

```xcconfig
OURA_BACKEND_BASE_URL[sdk=iphoneos*] = http:/$()/<MAC_LOCAL_IP>:8787
```

Keep the Mac and iPhone on the same Wi-Fi and allow the backend port through macOS firewall if prompted.

## Oura Developer Portal

In Oura's API application settings, configure these redirect URIs:

- iOS app callback: `aetherial-pulsar://oura/oauth/callback`
- Optional browser smoke test: `http://localhost:8787/oura/auth/callback`

The iOS app uses the custom-scheme redirect. The backend `/oura/auth/start` and `/oura/auth/callback` routes are provided for local browser verification and future web flows; the mobile production path uses `/oura/token/exchange`, `/oura/token/refresh`, and `/oura/disconnect`.

## Routes

- `GET /health`
- `GET /healthz`
- `GET /oura/auth/start`
- `GET /oura/auth/callback`
- `POST /oura/token/exchange`
- `POST /oura/token/refresh`
- `POST /oura/disconnect`

Compatibility aliases are also supported for the app's previous path names:

- `POST /oura/oauth/exchange`
- `POST /oura/oauth/refresh`
- `POST /oura/oauth/revoke`

The backend does not log authorization codes, access tokens, refresh tokens, or health data.
