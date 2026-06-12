# Orion AI Assistant

Orion is Pulsar's global AI assistant. The iOS app must never ship an OpenAI API key in the app binary, Info.plist, asset catalog, source code, or committed configuration.

## Local Development Configuration

1. Copy `Config/Orion.local.xcconfig.example` to `Config/Orion.local.xcconfig`.
2. Set `ORION_BACKEND_BASE_URL` to a trusted backend/proxy that owns `OPENAI_API_KEY`.
3. Keep `Config/Orion.local.xcconfig` untracked. It is ignored by Git.

The backend should expose `POST /orion/chat` by default. That endpoint receives the user message, recent Orion conversation turns, and a summarized Pulsar context object. The backend is responsible for calling OpenAI with its server-side API key.

The production backend lives behind `https://www.aetherial.tech/api/orion/chat`. It must define `OPENAI_API_KEY` in the hosting provider environment.

The Aetherial website project also includes the hosted serverless route:

```text
/Users/benjamingutierrezmendoza/Documents/Aetherial/aetherialwebpage/api/orion/chat.js
```

The Pulsar app should point to:

```xcconfig
ORION_BACKEND_BASE_URL = https:/$()/www.aetherial.tech
ORION_CHAT_PATH = /api/orion/chat
```

This repo also includes a local simulator-only development proxy at `Backend/OrionProxyServer`. It calls OpenAI's Responses API from Node, using `OPENAI_API_KEY` from `Backend/OrionProxyServer/.env`.

```sh
cp Backend/OrionProxyServer/.env.example Backend/OrionProxyServer/.env
# Fill in OPENAI_API_KEY, then:
./scripts/start-orion-backend.sh
```

For simulator-only development, `Config/Orion.local.xcconfig` can point to:

```xcconfig
ORION_BACKEND_BASE_URL[sdk=iphonesimulator*] = http:/$()/127.0.0.1:8788
ORION_CHAT_PATH[sdk=iphonesimulator*] = /orion/chat
```

Do not use `127.0.0.1` for a physical iPhone build. The phone treats localhost as the phone itself, not your Mac.

## Security Notes

- Do not hardcode `OPENAI_API_KEY` in Swift, xcconfig files, plist files, or tests.
- Do not read secrets from Chrome, Keychain, browser storage, or personal machine state.
- Production should use a hosted backend/proxy with secret management.
- Local development can use a local backend `.env`, but that `.env` belongs to the backend and must also be ignored by Git.
- `OPENAI_MODEL` is a backend setting. Keep model/provider choices server-side so the iOS binary only knows the Orion backend URL.

## Context Summarization

`OrionContextProvider` prepares a small context snapshot before each request. It summarizes available dashboard, nutrition, recovery, sleep, and workout state instead of sending raw HealthKit samples or the full local database.

The first implementation includes:

- Today's workout/activity summary
- Recent workout placeholders
- Nutrition summary from the local nutrition dashboard
- Recovery/readiness summary from the home dashboard
- Sleep summary from the home dashboard
- User goals from profile and nutrition targets

## Future Data Sources

Connect Orion to richer Pulsar data by extending `OrionContextProviding` with narrowly scoped summaries from HealthKit, workout history stores, recovery details, sleep details, nutrition, and WatchConnectivity. For web search or tool calling, add those capabilities behind the backend/proxy so policy, logging, and secret handling stay server-side.
