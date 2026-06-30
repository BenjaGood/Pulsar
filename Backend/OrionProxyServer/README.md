# Pulsar Orion OpenAI Proxy

This backend connects Orion to OpenAI without shipping an OpenAI API key in the iOS app. The iOS app sends a user message and summarized Pulsar context to this service, and this service calls OpenAI's Responses API with the server-side `OPENAI_API_KEY`.

## Environment

Copy `.env.example` to `.env`:

```sh
cp Backend/OrionProxyServer/.env.example Backend/OrionProxyServer/.env
```

Then edit `.env`:

```sh
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-5.5
OPENAI_REASONING_EFFORT=low
PORT=8788
```

`Backend/OrionProxyServer/.env` is ignored by Git. Do not commit API keys.

## Run Locally

From the repo root:

```sh
./scripts/start-orion-backend.sh
```

Health check:

```sh
curl http://127.0.0.1:8788/health
```

For the iOS Simulator, set `ORION_BACKEND_BASE_URL` in `Config/Orion.local.xcconfig`:

```xcconfig
ORION_BACKEND_BASE_URL = http:/$()/127.0.0.1:8788
ORION_CHAT_PATH = /orion/chat
```

For a physical iPhone, use your Mac's LAN IP:

```sh
ipconfig getifaddr en0
```

```xcconfig
ORION_BACKEND_BASE_URL[sdk=iphoneos*] = http:/$()/<MAC_LOCAL_IP>:8788
```

## Routes

- `GET /health`
- `GET /healthz`
- `POST /orion/chat`
- `POST /api/orion/chat`
- `POST /orion/meal-scan`
- `POST /api/orion/meal-scan`

## Request Contract

```json
{
  "message": "How should I train today?",
  "messages": [],
  "context": {
    "todayWorkoutSummary": {},
    "recentWorkouts": [],
    "nutritionSummary": {},
    "recoverySummary": {},
    "sleepSummary": {},
    "userGoals": {}
  }
}
```

## Response Contract

```json
{
  "reply": "Based on your summarized Pulsar context..."
}
```

The backend does not log request bodies, OpenAI responses, API keys, HealthKit data, or user messages.

## Meal Scanner Route

The iOS 3D Meal Scanner sends a compact JPEG and scan metadata to `POST /api/orion/meal-scan`. The OpenAI API key stays only in this backend environment.

```json
{
  "prompt": "Analyze this meal scan for Pulsar...",
  "instructions": "Return strict JSON only...",
  "imageBase64": "/9j/4AAQSkZJRgABAQ...",
  "payload": {
    "metadata": {},
    "quality": {},
    "depthStats": {},
    "clientHints": {}
  }
}
```

The response is wrapped for the iOS decoder:

```json
{
  "id": "resp_...",
  "created_at": "2026-06-25T23:30:00.000Z",
  "result": {
    "title": "Scanned meal",
    "ingredients": []
  },
  "model": "gpt-5.5"
}
```
