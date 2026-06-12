import http from "node:http";
import { randomUUID } from "node:crypto";

const PORT = Number(process.env.PORT || 8788);
const HOST = process.env.HOST || "0.0.0.0";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-5.5";
const OPENAI_TIMEOUT_MS = Number(process.env.OPENAI_TIMEOUT_MS || 30_000);
const OPENAI_TEXT_VERBOSITY = process.env.OPENAI_TEXT_VERBOSITY || "low";
const OPENAI_REASONING_EFFORT = process.env.OPENAI_REASONING_EFFORT;
const CORS_ORIGIN = process.env.CORS_ORIGIN;
const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
const REQUEST_BODY_LIMIT = 96_000;

const ORION_INSTRUCTIONS = `
You are Orion, Pulsar's intelligence assistant.
Use the summarized Pulsar context supplied by the app to answer questions about workouts,
recovery, nutrition, sleep, and goals. Be concise, practical, and clear when data is missing.
Do not claim access to raw databases, raw HealthKit samples, browser data, or web search unless
the backend explicitly adds those tools later. Do not provide medical diagnosis.
`.trim();

function sendJSON(response, statusCode, body) {
  const headers = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  };
  if (CORS_ORIGIN) {
    headers["Access-Control-Allow-Origin"] = CORS_ORIGIN;
    headers["Access-Control-Allow-Headers"] = "Content-Type";
    headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS";
  }
  response.writeHead(statusCode, headers);
  response.end(JSON.stringify(body));
}

async function readJSON(request) {
  let raw = "";
  for await (const chunk of request) {
    raw += chunk;
    if (raw.length > REQUEST_BODY_LIMIT) {
      const error = new Error("Request body too large.");
      error.statusCode = 413;
      throw error;
    }
  }
  if (!raw.trim()) return {};
  return JSON.parse(raw);
}

function missingConfiguration() {
  const missing = [];
  if (!OPENAI_API_KEY || OPENAI_API_KEY === "replace_with_your_openai_api_key") {
    missing.push("OPENAI_API_KEY");
  }
  return missing;
}

function healthBody() {
  const missing = missingConfiguration();
  const body = {
    ok: true,
    service: "pulsar-orion-backend",
    configured: missing.length === 0,
    model: OPENAI_MODEL
  };
  if (missing.length) {
    body.missing = missing;
  }
  return body;
}

function sanitizeMessage(value) {
  if (!value || typeof value !== "object") return null;
  const role = value.role === "assistant" ? "assistant" : value.role === "user" ? "user" : null;
  const content = typeof value.content === "string" ? value.content.trim() : "";
  if (!role || !content) return null;
  return { role, content: content.slice(0, 4_000) };
}

function summarizeConversation(messages) {
  if (!Array.isArray(messages)) return "No previous Orion turns.";
  const recentMessages = messages.slice(-10).map(sanitizeMessage).filter(Boolean);
  if (!recentMessages.length) return "No previous Orion turns.";
  return recentMessages
    .map((message) => `${message.role.toUpperCase()}: ${message.content}`)
    .join("\n");
}

function compactJSONString(value) {
  if (!value || typeof value !== "object") return "{}";
  return JSON.stringify(value, null, 2).slice(0, 24_000);
}

function buildOpenAIInput(body) {
  const contextJSON = compactJSONString(body.context);
  const conversation = summarizeConversation(body.messages);
  const userQuestion = String(body.message || "").trim().slice(0, 4_000);

  return [
    {
      role: "developer",
      content: ORION_INSTRUCTIONS
    },
    {
      role: "user",
      content: [
        "Answer the latest Orion user question using only the summarized Pulsar context below.",
        "",
        "Latest user question:",
        userQuestion,
        "",
        "Recent conversation:",
        conversation,
        "",
        "Summarized Pulsar context JSON:",
        contextJSON
      ].join("\n")
    }
  ];
}

function openAIRequestBody(body) {
  const payload = {
    model: OPENAI_MODEL,
    input: buildOpenAIInput(body),
    store: false
  };

  if (supportsGPT5TextControls(OPENAI_MODEL)) {
    payload.text = {
      verbosity: OPENAI_TEXT_VERBOSITY
    };
  }

  if (supportsReasoningEffort(OPENAI_MODEL)) {
    payload.reasoning = {
      effort: OPENAI_REASONING_EFFORT || "low"
    };
  }

  return payload;
}

function supportsGPT5TextControls(model) {
  return model.startsWith("gpt-5");
}

function supportsReasoningEffort(model) {
  return model.startsWith("gpt-5") || model.startsWith("o");
}

function extractOpenAIText(body) {
  if (typeof body.output_text === "string" && body.output_text.trim()) {
    return body.output_text.trim();
  }

  const fragments = [];
  for (const output of body.output || []) {
    for (const content of output.content || []) {
      if (typeof content.text === "string") {
        fragments.push(content.text);
      }
    }
  }
  return fragments.join("\n").trim();
}

async function requestOpenAI(body) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);

  try {
    const response = await fetch(OPENAI_RESPONSES_URL, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(openAIRequestBody(body)),
      signal: controller.signal
    });

    const text = await response.text();
    let parsed = {};
    if (text) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = { error: { message: "OpenAI returned a non-JSON response." } };
      }
    }

    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        message: parsed.error?.message || "OpenAI request failed."
      };
    }

    const reply = extractOpenAIText(parsed);
    if (!reply) {
      return {
        ok: false,
        status: 502,
        message: "OpenAI returned an empty response."
      };
    }

    return {
      ok: true,
      id: parsed.id || randomUUID(),
      reply,
      model: parsed.model || OPENAI_MODEL
    };
  } catch (error) {
    if (error?.name === "AbortError") {
      return { ok: false, status: 504, message: "OpenAI request timed out." };
    }
    return { ok: false, status: 502, message: "OpenAI request failed." };
  } finally {
    clearTimeout(timeout);
  }
}

async function handleChat(request, response) {
  const missing = missingConfiguration();
  if (missing.length) {
    sendJSON(response, 500, {
      error: "orion_backend_not_configured",
      error_description: `Missing ${missing.join(", ")}.`,
      message: "Orion backend is missing OPENAI_API_KEY in the server environment."
    });
    return;
  }

  const body = await readJSON(request);
  const message = typeof body.message === "string" ? body.message.trim() : "";
  if (!message) {
    sendJSON(response, 400, {
      error: "invalid_request",
      error_description: "message is required.",
      message: "Please enter a message for Orion."
    });
    return;
  }

  const result = await requestOpenAI({ ...body, message });
  if (!result.ok) {
    sendJSON(response, result.status, {
      error: "orion_openai_request_failed",
      error_description: result.message,
      message: result.message
    });
    return;
  }

  sendJSON(response, 200, {
    id: result.id,
    created_at: new Date().toISOString(),
    reply: result.reply,
    model: result.model
  });
}

async function handleRequest(request, response) {
  const url = new URL(request.url, `http://${request.headers.host || "localhost"}`);
  const path = url.pathname;

  if (request.method === "OPTIONS") {
    sendJSON(response, 204, {});
    return;
  }

  if (request.method === "GET" && (path === "/health" || path === "/healthz")) {
    sendJSON(response, 200, healthBody());
    return;
  }

  if (request.method === "POST" && (path === "/orion/chat" || path === "/api/orion/chat")) {
    await handleChat(request, response);
    return;
  }

  sendJSON(response, 404, { error: "not_found" });
}

const server = http.createServer((request, response) => {
  handleRequest(request, response).catch((error) => {
    console.error("[PulsarOrionBackend]", error.message);
    sendJSON(response, error.statusCode || 500, {
      error: "internal_server_error",
      error_description: "Orion backend request failed.",
      message: "Orion backend request failed."
    });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`[PulsarOrionBackend] Listening on http://${HOST}:${PORT}`);
});
