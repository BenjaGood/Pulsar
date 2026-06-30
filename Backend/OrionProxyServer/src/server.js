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
const MEAL_SCAN_BODY_LIMIT = 8_000_000;

const MEAL_SCAN_RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    result: {
      type: "object",
      additionalProperties: false,
      properties: {
        mode: {
          type: "string",
          enum: ["depthAssisted", "photoOnly", "singlePlate", "multiItem", "packagedMeal", "leftovers"]
        },
        title: { type: "string" },
        summary: { type: "string" },
        ingredients: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              name: { type: "string" },
              grams: { type: "number" },
              nutrition: {
                type: "object",
                additionalProperties: false,
                properties: {
                  calories: { type: "number" },
                  proteinGrams: { type: "number" },
                  carbohydrateGrams: { type: "number" },
                  fatGrams: { type: "number" },
                  fiberGrams: { type: "number" },
                  sugarGrams: { type: "number" },
                  sodiumMilligrams: { type: "number" }
                },
                required: [
                  "calories",
                  "proteinGrams",
                  "carbohydrateGrams",
                  "fatGrams",
                  "fiberGrams",
                  "sugarGrams",
                  "sodiumMilligrams"
                ]
              },
              micronutrients: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  properties: {
                    name: { type: "string" },
                    amount: { type: "number" },
                    unit: { type: "string" },
                    percentDailyValue: { type: ["number", "null"] }
                  },
                  required: ["name", "amount", "unit", "percentDailyValue"]
                }
              },
              confidence: { type: "number" },
              regionID: { type: ["string", "null"] },
              reasoning: { type: ["string", "null"] },
              notes: { type: ["string", "null"] }
            },
            required: [
              "name",
              "grams",
              "nutrition",
              "micronutrients",
              "confidence",
              "regionID",
              "reasoning",
              "notes"
            ]
          }
        },
        totals: {
          type: "object",
          additionalProperties: false,
          properties: {
            calories: { type: "number" },
            proteinGrams: { type: "number" },
            carbohydrateGrams: { type: "number" },
            fatGrams: { type: "number" },
            fiberGrams: { type: "number" },
            sugarGrams: { type: "number" },
            sodiumMilligrams: { type: "number" }
          },
          required: [
            "calories",
            "proteinGrams",
            "carbohydrateGrams",
            "fatGrams",
            "fiberGrams",
            "sugarGrams",
            "sodiumMilligrams"
          ]
        },
        micronutrients: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              name: { type: "string" },
              amount: { type: "number" },
              unit: { type: "string" },
              percentDailyValue: { type: ["number", "null"] }
            },
            required: ["name", "amount", "unit", "percentDailyValue"]
          }
        },
        notes: {
          type: "array",
          items: { type: "string" }
        },
        accuracyDisclaimer: { type: "string" },
        quality: {
          type: "object",
          additionalProperties: false,
          properties: {
            level: {
              type: "string",
              enum: ["excellent", "good", "usable", "limited", "insufficient"]
            },
            confidence: { type: "number" },
            hasDepth: { type: "boolean" },
            hasLiDAR: { type: "boolean" },
            depthSource: {
              type: "string",
              enum: ["none", "sceneDepth", "smoothedSceneDepth"]
            },
            imageSharpnessEstimate: { type: ["number", "null"] },
            lightingEstimate: { type: ["number", "null"] },
            occlusionRisk: { type: "number" },
            warnings: {
              type: "array",
              items: { type: "string" }
            }
          },
          required: [
            "level",
            "confidence",
            "hasDepth",
            "hasLiDAR",
            "depthSource",
            "imageSharpnessEstimate",
            "lightingEstimate",
            "occlusionRisk",
            "warnings"
          ]
        },
        plateEstimate: {
          type: ["object", "null"],
          additionalProperties: false,
          properties: {
            diameterCentimeters: { type: ["number", "null"] },
            areaSquareCentimeters: { type: ["number", "null"] },
            volumeMilliliters: { type: ["number", "null"] },
            confidence: { type: "number" },
            source: { type: "string" }
          },
          required: [
            "diameterCentimeters",
            "areaSquareCentimeters",
            "volumeMilliliters",
            "confidence",
            "source"
          ]
        },
        foodRegions: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              id: { type: "string" },
              label: { type: ["string", "null"] },
              normalizedBoundingBox: {
                type: "object",
                additionalProperties: false,
                properties: {
                  x: { type: "number" },
                  y: { type: "number" },
                  width: { type: "number" },
                  height: { type: "number" }
                },
                required: ["x", "y", "width", "height"]
              },
              estimatedGrams: { type: ["number", "null"] },
              estimatedVolumeMilliliters: { type: ["number", "null"] },
              confidence: { type: "number" }
            },
            required: [
              "id",
              "label",
              "normalizedBoundingBox",
              "estimatedGrams",
              "estimatedVolumeMilliliters",
              "confidence"
            ]
          }
        },
        metadata: {
          type: "object",
          additionalProperties: false,
          properties: {
            modelName: { type: ["string", "null"] },
            backendVersion: { type: ["string", "null"] },
            disclaimer: { type: "string" },
            estimatedOnly: { type: "boolean" },
            needsUserReview: { type: "boolean" }
          },
          required: ["modelName", "backendVersion", "disclaimer", "estimatedOnly", "needsUserReview"]
        }
      },
      required: [
        "mode",
        "title",
        "summary",
        "ingredients",
        "totals",
        "micronutrients",
        "notes",
        "accuracyDisclaimer",
        "quality",
        "plateEstimate",
        "foodRegions",
        "metadata"
      ]
    }
  },
  required: ["result"]
};

const ORION_INSTRUCTIONS = `
You are Orion, Pulsar's intelligence assistant.
Use the summarized Pulsar context supplied by the app to answer questions about workouts,
recovery, nutrition, sleep, and goals. Be concise, practical, and clear when data is missing.
Do not claim access to raw databases, raw HealthKit samples, browser data, or web search unless
the backend explicitly adds those tools later. Do not provide medical diagnosis.
`.trim();

const MEAL_SCAN_INSTRUCTIONS = `
You are Pulsar's backend nutrition analysis service for meal images.
Return only JSON matching the requested schema, with no Markdown or explanatory prose.
Use visible image evidence first, the compact scan payload second, and conservative nutrition estimates.
Perform the analysis in two internal passes: first identify only visible food regions, then estimate nutrition from those regions.
Never infer a common meal template from a plate shape, color palette, cuisine guess, or nutrition stereotype.
Never invent hidden ingredients or claim access to raw depth maps; only compact client metadata is available.
Use generic labels when evidence is ambiguous, such as "ground meat/protein, type uncertain", "mixed salad", "sauce/dressing, type uncertain", or "starch, type uncertain".
Do not label meat as chicken, beef, pork, fish, turkey, shrimp, tofu, egg, or cheese unless the image shows distinctive visual evidence for that exact food.
Set metadata.needsUserReview to true whenever the food identity, portion size, or nutrition estimate is uncertain.
`.trim();

const SPECIFIC_PROTEIN_RULES = [
  {
    pattern: /\b(chicken|turkey)\b/i,
    genericName: "poultry or protein, type uncertain",
    evidence: /\b(white meat|fibrous|breast|thigh|skin|drumstick|wing|shredded|grill mark|breaded|roasted poultry)\b/i
  },
  {
    pattern: /\b(beef|steak|carne asada|hamburger)\b/i,
    genericName: "ground meat/protein, type uncertain",
    evidence: /\b(red meat|steak grain|marbling|beef patty|visible beef label)\b/i
  },
  {
    pattern: /\b(pork|bacon|ham|sausage|chorizo)\b/i,
    genericName: "pork or processed meat, type uncertain",
    evidence: /\b(bacon strip|ham slice|sausage link|chorizo|pork chop|fat cap|cured meat)\b/i
  },
  {
    pattern: /\b(fish|salmon|tuna|shrimp|prawn|seafood)\b/i,
    genericName: "seafood/protein, type uncertain",
    evidence: /\b(flake|fish fillet|salmon color|tuna steak|shrimp shape|shell|tail|seafood)\b/i
  },
  {
    pattern: /\b(tofu|egg|cheese)\b/i,
    genericName: "protein/dairy item, type uncertain",
    evidence: /\b(tofu cube|curd|yolk|egg white|scrambled|melted cheese|cheese shred|cheese slice)\b/i
  }
];

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

async function readJSON(request, limit = REQUEST_BODY_LIMIT) {
  let raw = "";
  for await (const chunk of request) {
    raw += chunk;
    if (raw.length > limit) {
      const error = new Error("Request body too large.");
      error.statusCode = 413;
      throw error;
    }
  }
  if (!raw.trim()) return {};
  try {
    return JSON.parse(raw);
  } catch {
    const error = new Error("Request body must be valid JSON.");
    error.statusCode = 400;
    throw error;
  }
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

function compactString(value, limit) {
  return typeof value === "string" ? value.trim().slice(0, limit) : "";
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

function imageValueFromBody(body) {
  if (typeof body.imageBase64 === "string") return body.imageBase64;
  if (typeof body.image_base64 === "string") return body.image_base64;
  if (typeof body.base64 === "string") return body.base64;
  if (typeof body.image === "string") return body.image;
  if (body.image && typeof body.image === "object") {
    if (typeof body.image.base64 === "string") return body.image.base64;
    if (typeof body.image.data === "string") return body.image.data;
    if (typeof body.image.dataUrl === "string") return body.image.dataUrl;
  }
  return "";
}

function normalizeImageDataURL(body) {
  const imageValue = imageValueFromBody(body).trim();
  if (!imageValue) return null;

  const dataURLMatch = imageValue.match(/^data:(image\/[a-z0-9.+-]+);base64,(.+)$/is);
  const mimeType = dataURLMatch ? dataURLMatch[1].toLowerCase() : "image/jpeg";
  const base64 = (dataURLMatch ? dataURLMatch[2] : imageValue)
    .replace(/\s/g, "")
    .replace(/-/g, "+")
    .replace(/_/g, "/");

  if (!base64 || base64.length % 4 === 1 || !/^[A-Za-z0-9+/]*={0,2}$/.test(base64)) {
    return null;
  }

  return `data:${mimeType};base64,${base64}`;
}

function buildMealScanOpenAIInput(body, imageDataURL) {
  const prompt = compactString(body.prompt, 4_000) || "Analyze this Pulsar meal scan.";
  const instructions = compactString(body.instructions, 8_000);
  const payloadJSON = compactJSONString(body.payload);

  return [
    {
      role: "developer",
      content: [MEAL_SCAN_INSTRUCTIONS, instructions].filter(Boolean).join("\n\n")
    },
    {
      role: "user",
      content: [
        {
          type: "input_text",
          text: [
            prompt,
            "",
            "Return a conservative nutrition estimate as strict JSON. Include visible-food reasoning for each ingredient.",
            "",
            "Compact meal scan payload JSON:",
            payloadJSON
          ].join("\n")
        },
        {
          type: "input_image",
          image_url: imageDataURL
        }
      ]
    }
  ];
}

function openAIMealScanRequestBody(body, imageDataURL) {
  const payload = {
    model: OPENAI_MODEL,
    input: buildMealScanOpenAIInput(body, imageDataURL),
    store: false,
    text: {
      format: {
        type: "json_schema",
        name: "meal_scan_analysis",
        strict: true,
        schema: MEAL_SCAN_RESPONSE_SCHEMA
      }
    }
  };

  if (supportsGPT5TextControls(OPENAI_MODEL)) {
    payload.text.verbosity = OPENAI_TEXT_VERBOSITY;
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

async function requestOpenAIResponse(payload) {
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
      body: JSON.stringify(payload),
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

    return {
      ok: true,
      body: parsed
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

async function requestOpenAI(body) {
  const result = await requestOpenAIResponse(openAIRequestBody(body));
  if (!result.ok) return result;

  const reply = extractOpenAIText(result.body);
  if (!reply) {
    return {
      ok: false,
      status: 502,
      message: "OpenAI returned an empty response."
    };
  }

  return {
    ok: true,
    id: result.body.id || randomUUID(),
    reply,
    model: result.body.model || OPENAI_MODEL
  };
}

function parseMealScanResult(text) {
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object" && parsed.result && typeof parsed.result === "object") {
      return { ok: true, result: sanitizeMealScanResult(parsed.result) };
    }
    return { ok: false, message: "OpenAI meal scan JSON did not include a result object." };
  } catch {
    return { ok: false, message: "OpenAI meal scan response was not valid JSON." };
  }
}

function sanitizeMealScanResult(result) {
  const warnings = [];
  const sanitized = {
    ...result,
    ingredients: Array.isArray(result.ingredients) ? result.ingredients.map((ingredient) => sanitizeIngredient(ingredient, warnings)) : [],
    foodRegions: Array.isArray(result.foodRegions) ? result.foodRegions : [],
    micronutrients: Array.isArray(result.micronutrients) ? result.micronutrients : [],
    notes: Array.isArray(result.notes) ? result.notes : []
  };

  if (warnings.length) {
    sanitized.notes = [
      ...sanitized.notes,
      "Some food identities were downgraded because the image evidence was not specific enough."
    ];
  }

  sanitized.totals = recomputeTotals(sanitized.ingredients, sanitized.totals);
  sanitized.quality = sanitizeQuality(sanitized.quality, warnings);
  sanitized.metadata = sanitizeMetadata(sanitized.metadata, warnings);
  sanitized.summary = sanitizeSummary(sanitized.summary, warnings);
  sanitized.accuracyDisclaimer = compactString(
    sanitized.accuracyDisclaimer,
    600
  ) || "Meal scanner nutrition is an estimate. Confirm foods and portions before logging.";
  return sanitized;
}

function sanitizeIngredient(ingredient, warnings) {
  const sanitized = {
    ...ingredient,
    name: compactString(ingredient?.name, 120) || "Detected food, type uncertain",
    reasoning: compactString(ingredient?.reasoning, 600) || null,
    notes: compactString(ingredient?.notes, 600) || null,
    confidence: clampNumber(ingredient?.confidence, 0, 1, 0.35)
  };
  const evidenceText = [sanitized.name, sanitized.reasoning, sanitized.notes].filter(Boolean).join(" ");
  const rule = SPECIFIC_PROTEIN_RULES.find((candidate) => candidate.pattern.test(sanitized.name));

  if (rule && !rule.evidence.test(evidenceText)) {
    warnings.push(`Downgraded "${sanitized.name}" because visible evidence did not support that exact food identity.`);
    sanitized.notes = joinNotes(
      sanitized.notes,
      `Original label "${sanitized.name}" was not visually specific enough; review before logging.`
    );
    sanitized.reasoning = joinNotes(
      sanitized.reasoning,
      "Specific protein type is uncertain from the visible image evidence."
    );
    sanitized.name = rule.genericName;
    sanitized.confidence = Math.min(sanitized.confidence, 0.46);
  }

  if (!sanitized.reasoning || weakEvidenceReasoning(sanitized.reasoning)) {
    sanitized.confidence = Math.min(sanitized.confidence, 0.52);
    sanitized.notes = joinNotes(
      sanitized.notes,
      "Review this item because the visual reasoning was limited."
    );
  }

  sanitized.grams = clampNumber(sanitized.grams, 0, 2_000, 0);
  sanitized.nutrition = sanitizeTotals(sanitized.nutrition);
  sanitized.micronutrients = Array.isArray(sanitized.micronutrients) ? sanitized.micronutrients : [];
  if (typeof sanitized.regionID !== "string") {
    sanitized.regionID = null;
  }
  return sanitized;
}

function sanitizeQuality(quality, warnings) {
  const sanitized = quality && typeof quality === "object" ? { ...quality } : {};
  sanitized.level = ["excellent", "good", "usable", "limited", "insufficient"].includes(sanitized.level)
    ? sanitized.level
    : "usable";
  sanitized.confidence = clampNumber(sanitized.confidence, 0, 1, 0.45);
  sanitized.hasDepth = Boolean(sanitized.hasDepth);
  sanitized.hasLiDAR = Boolean(sanitized.hasLiDAR);
  sanitized.depthSource = ["none", "sceneDepth", "smoothedSceneDepth"].includes(sanitized.depthSource)
    ? sanitized.depthSource
    : "none";
  sanitized.imageSharpnessEstimate = nullableNumber(sanitized.imageSharpnessEstimate);
  sanitized.lightingEstimate = nullableNumber(sanitized.lightingEstimate);
  sanitized.occlusionRisk = clampNumber(sanitized.occlusionRisk, 0, 1, 0.5);
  sanitized.warnings = Array.isArray(sanitized.warnings) ? sanitized.warnings : [];
  if (warnings.length) {
    sanitized.confidence = Math.min(sanitized.confidence, 0.56);
    sanitized.level = sanitized.level === "excellent" || sanitized.level === "good" ? "usable" : sanitized.level;
    sanitized.warnings = [...sanitized.warnings, ...warnings];
  }
  return sanitized;
}

function sanitizeMetadata(metadata, warnings) {
  const sanitized = metadata && typeof metadata === "object" ? { ...metadata } : {};
  sanitized.modelName = typeof sanitized.modelName === "string" ? sanitized.modelName : OPENAI_MODEL;
  sanitized.backendVersion = typeof sanitized.backendVersion === "string" ? sanitized.backendVersion : "orion-meal-scan-v2";
  sanitized.disclaimer = compactString(sanitized.disclaimer, 600)
    || "Meal scanner nutrition is an estimate. Confirm foods and portions before logging.";
  sanitized.estimatedOnly = typeof sanitized.estimatedOnly === "boolean" ? sanitized.estimatedOnly : true;
  sanitized.needsUserReview = warnings.length > 0 || sanitized.needsUserReview !== false;
  return sanitized;
}

function sanitizeSummary(summary, warnings) {
  const text = compactString(summary, 800);
  if (!warnings.length) return text;
  const uncertainty = "Some item identities are uncertain and should be reviewed.";
  return text.includes(uncertainty) ? text : [text, uncertainty].filter(Boolean).join(" ");
}

function weakEvidenceReasoning(reasoning) {
  return !/\b(visible|region|texture|shape|color|edge|separate|leaf|grain|crumb|ground|sliced|diced|sauce|label|plate|bowl)\b/i.test(reasoning);
}

function joinNotes(existing, addition) {
  if (!existing) return addition;
  return existing.includes(addition) ? existing : `${existing} ${addition}`;
}

function recomputeTotals(ingredients, fallbackTotals) {
  if (!ingredients.length) return sanitizeTotals(fallbackTotals);
  return ingredients.reduce((totals, ingredient) => ({
    calories: totals.calories + ingredient.nutrition.calories,
    proteinGrams: totals.proteinGrams + ingredient.nutrition.proteinGrams,
    carbohydrateGrams: totals.carbohydrateGrams + ingredient.nutrition.carbohydrateGrams,
    fatGrams: totals.fatGrams + ingredient.nutrition.fatGrams,
    fiberGrams: totals.fiberGrams + ingredient.nutrition.fiberGrams,
    sugarGrams: totals.sugarGrams + ingredient.nutrition.sugarGrams,
    sodiumMilligrams: totals.sodiumMilligrams + ingredient.nutrition.sodiumMilligrams
  }), sanitizeTotals({}));
}

function sanitizeTotals(value) {
  const totals = value && typeof value === "object" ? value : {};
  return {
    calories: clampNumber(totals.calories, 0, 5_000, 0),
    proteinGrams: clampNumber(totals.proteinGrams, 0, 500, 0),
    carbohydrateGrams: clampNumber(totals.carbohydrateGrams, 0, 800, 0),
    fatGrams: clampNumber(totals.fatGrams, 0, 500, 0),
    fiberGrams: clampNumber(totals.fiberGrams, 0, 200, 0),
    sugarGrams: clampNumber(totals.sugarGrams, 0, 500, 0),
    sodiumMilligrams: clampNumber(totals.sodiumMilligrams, 0, 20_000, 0)
  };
}

function nullableNumber(value) {
  if (value === null || value === undefined) return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function clampNumber(value, minimum, maximum, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(number, minimum), maximum);
}

async function requestOpenAIMealScan(body, imageDataURL) {
  const result = await requestOpenAIResponse(openAIMealScanRequestBody(body, imageDataURL));
  if (!result.ok) return result;

  const text = extractOpenAIText(result.body);
  if (!text) {
    return {
      ok: false,
      status: 502,
      message: "OpenAI returned an empty meal scan response."
    };
  }

  const parsed = parseMealScanResult(text);
  if (!parsed.ok) {
    return {
      ok: false,
      status: 502,
      message: parsed.message
    };
  }

  return {
    ok: true,
    id: result.body.id || randomUUID(),
    result: parsed.result,
    model: result.body.model || OPENAI_MODEL
  };
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

async function handleMealScan(request, response) {
  const missing = missingConfiguration();
  if (missing.length) {
    sendJSON(response, 500, {
      error: "orion_backend_not_configured",
      error_description: `Missing ${missing.join(", ")}.`,
      message: "Meal Scanner backend is missing OPENAI_API_KEY in the server environment."
    });
    return;
  }

  const body = await readJSON(request, MEAL_SCAN_BODY_LIMIT);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    sendJSON(response, 400, {
      error: "invalid_request",
      error_description: "Request body must be a JSON object.",
      message: "Meal Scanner requires a JSON request body."
    });
    return;
  }

  const imageDataURL = normalizeImageDataURL(body);
  if (!imageDataURL) {
    sendJSON(response, 400, {
      error: "invalid_request",
      error_description: "imageBase64 is required and must contain base64 image data.",
      message: "Meal Scanner requires a base64 image."
    });
    return;
  }

  if (!compactString(body.instructions, 8_000)) {
    sendJSON(response, 400, {
      error: "invalid_request",
      error_description: "instructions is required.",
      message: "Meal Scanner requires analysis instructions."
    });
    return;
  }

  if (!body.payload || typeof body.payload !== "object" || Array.isArray(body.payload)) {
    sendJSON(response, 400, {
      error: "invalid_request",
      error_description: "payload is required and must be an object.",
      message: "Meal Scanner requires compact scan metadata."
    });
    return;
  }

  const result = await requestOpenAIMealScan(body, imageDataURL);
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
    result: result.result,
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

  if (request.method === "POST" && (path === "/orion/meal-scan" || path === "/api/orion/meal-scan")) {
    await handleMealScan(request, response);
    return;
  }

  sendJSON(response, 404, { error: "not_found" });
}

const server = http.createServer((request, response) => {
  handleRequest(request, response).catch((error) => {
    const statusCode = error.statusCode || 500;
    const message = statusCode < 500 ? error.message : "Orion backend request failed.";
    if (statusCode >= 500) {
      console.error("[PulsarOrionBackend]", error.message);
    }
    sendJSON(response, statusCode, {
      error: statusCode < 500 ? "invalid_request" : "internal_server_error",
      error_description: message,
      message
    });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`[PulsarOrionBackend] Listening on http://${HOST}:${PORT}`);
});
