import http from "node:http";
import { randomUUID } from "node:crypto";
import { URL, URLSearchParams } from "node:url";

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || "0.0.0.0";
const OURA_CLIENT_ID = process.env.OURA_CLIENT_ID;
const OURA_CLIENT_SECRET = process.env.OURA_CLIENT_SECRET;
const OURA_REDIRECT_URI = process.env.OURA_REDIRECT_URI;
const OURA_WEB_REDIRECT_URI = process.env.OURA_WEB_REDIRECT_URI;
const CORS_ORIGIN = process.env.CORS_ORIGIN;

const OURA_AUTHORIZE_URL = "https://cloud.ouraring.com/oauth/authorize";
const OURA_TOKEN_URL = "https://api.ouraring.com/oauth/token";
const OURA_REVOKE_URL = "https://api.ouraring.com/oauth/revoke";
const DEFAULT_SCOPES = ["email", "personal", "daily", "heartrate", "workout", "tag", "session", "spo2"];

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

function sendHTML(response, statusCode, html) {
  response.writeHead(statusCode, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(html);
}

function requireServerConfiguration() {
  const missing = [];
  if (!OURA_CLIENT_ID) missing.push("OURA_CLIENT_ID");
  if (!OURA_CLIENT_SECRET) missing.push("OURA_CLIENT_SECRET");
  if (!OURA_REDIRECT_URI) missing.push("OURA_REDIRECT_URI");
  return missing;
}

function healthBody() {
  const missing = requireServerConfiguration();
  const body = {
    ok: true,
    service: "pulsar-oura-backend",
    configured: missing.length === 0
  };
  if (missing.length) {
    body.missing = missing;
  }
  return body;
}

async function readJSON(request) {
  let raw = "";
  for await (const chunk of request) {
    raw += chunk;
    if (raw.length > 16_384) {
      throw new Error("Request body too large.");
    }
  }
  if (!raw.trim()) return {};
  return JSON.parse(raw);
}

function authorizationURL({ state, scopes, redirectURI }) {
  const url = new URL(OURA_AUTHORIZE_URL);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", OURA_CLIENT_ID);
  url.searchParams.set("redirect_uri", redirectURI || OURA_REDIRECT_URI);
  url.searchParams.set("scope", (scopes?.length ? scopes : DEFAULT_SCOPES).join(" "));
  if (state) url.searchParams.set("state", state);
  return url;
}

async function requestOuraToken(parameters) {
  const body = new URLSearchParams({
    client_id: OURA_CLIENT_ID,
    client_secret: OURA_CLIENT_SECRET,
    ...parameters
  });
  const response = await fetch(OURA_TOKEN_URL, {
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body
  });
  const text = await response.text();
  let parsed = {};
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = { error: "invalid_oura_response" };
    }
  }
  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      body: {
        error: parsed.error || parsed.title || "oura_token_error",
        error_description: parsed.error_description || parsed.detail || "Oura token request failed."
      }
    };
  }
  return { ok: true, status: response.status, body: parsed };
}

async function revokeOuraToken(accessToken) {
  const url = new URL(OURA_REVOKE_URL);
  url.searchParams.set("access_token", accessToken);
  let response = await fetch(url, { method: "POST", headers: { "Accept": "application/json" } });
  if (response.status === 405) {
    response = await fetch(url, { method: "GET", headers: { "Accept": "application/json" } });
  }
  return response;
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

  const missing = requireServerConfiguration();
  if (missing.length) {
    sendJSON(response, 500, {
      error: "oura_backend_not_configured",
      error_description: `Missing ${missing.join(", ")}.`
    });
    return;
  }

  if (request.method === "GET" && path === "/oura/auth/start") {
    const state = url.searchParams.get("state") || randomUUID();
    const scopes = (url.searchParams.get("scope") || "").split(/[ ,]+/).filter(Boolean);
    const redirectURI = url.searchParams.get("redirect_uri") || OURA_WEB_REDIRECT_URI || OURA_REDIRECT_URI;
    const authURL = authorizationURL({ state, scopes, redirectURI });
    if (url.searchParams.get("mode") === "redirect") {
      response.writeHead(302, { Location: authURL.toString() });
      response.end();
      return;
    }
    sendJSON(response, 200, { authorization_url: authURL.toString(), state, redirect_uri: redirectURI });
    return;
  }

  if (request.method === "GET" && path === "/oura/auth/callback") {
    const error = url.searchParams.get("error");
    const code = url.searchParams.get("code");
    if (error) {
      sendHTML(response, 400, "<h1>Oura authorization failed</h1><p>You can close this window.</p>");
      return;
    }
    if (!code) {
      sendHTML(response, 400, "<h1>Missing Oura authorization code</h1><p>You can close this window.</p>");
      return;
    }
    sendHTML(response, 200, "<h1>Oura authorization received</h1><p>Return to Pulsar to finish connecting.</p>");
    return;
  }

  if (request.method === "POST" && (path === "/oura/token/exchange" || path === "/oura/oauth/exchange")) {
    const body = await readJSON(request);
    if (!body.code || !body.redirect_uri) {
      sendJSON(response, 400, {
        error: "invalid_request",
        error_description: "code and redirect_uri are required."
      });
      return;
    }
    const tokenParameters = {
      grant_type: "authorization_code",
      code: body.code,
      redirect_uri: body.redirect_uri
    };
    if (body.code_verifier) {
      tokenParameters.code_verifier = body.code_verifier;
    }
    const tokenResult = await requestOuraToken(tokenParameters);
    sendJSON(response, tokenResult.ok ? 200 : tokenResult.status, tokenResult.body);
    return;
  }

  if (request.method === "POST" && (path === "/oura/token/refresh" || path === "/oura/oauth/refresh")) {
    const body = await readJSON(request);
    if (!body.refresh_token) {
      sendJSON(response, 400, {
        error: "invalid_request",
        error_description: "refresh_token is required."
      });
      return;
    }
    const tokenResult = await requestOuraToken({
      grant_type: "refresh_token",
      refresh_token: body.refresh_token
    });
    sendJSON(response, tokenResult.ok ? 200 : tokenResult.status, tokenResult.body);
    return;
  }

  if (request.method === "POST" && (path === "/oura/disconnect" || path === "/oura/oauth/revoke")) {
    const body = await readJSON(request);
    if (!body.access_token) {
      sendJSON(response, 400, {
        error: "invalid_request",
        error_description: "access_token is required."
      });
      return;
    }
    const revokeResponse = await revokeOuraToken(body.access_token);
    if (!revokeResponse.ok && revokeResponse.status !== 400 && revokeResponse.status !== 401) {
      sendJSON(response, revokeResponse.status, {
        error: "oura_revoke_failed",
        error_description: "Oura revoke request failed."
      });
      return;
    }
    sendJSON(response, 200, { revoked: true });
    return;
  }

  sendJSON(response, 404, { error: "not_found" });
}

const server = http.createServer((request, response) => {
  handleRequest(request, response).catch((error) => {
    console.error("[PulsarOuraBackend]", error.message);
    sendJSON(response, 500, {
      error: "internal_server_error",
      error_description: "Oura backend request failed."
    });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`[PulsarOuraBackend] Listening on http://${HOST}:${PORT}`);
});
