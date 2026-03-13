import { randomBytes, randomUUID } from "node:crypto";
import type { NextFunction, Request, RequestHandler, Response } from "express";
import type { RelayErrorCode, RelayRunStartRequest } from "./relay-types";

const DEFAULT_MAX_UPLOAD_BYTES = 25 * 1024 * 1024;

const BLOCKED_FILE_EXTENSIONS = new Set([
  ".exe",
  ".dmg",
  ".pkg",
  ".app",
  ".bat",
  ".cmd",
  ".com",
  ".msi",
  ".sh",
  ".ps1",
  ".scr",
]);

const ALLOWED_MIME_PREFIXES = [
  "text/",
  "image/",
  "application/pdf",
  "application/json",
  "application/xml",
  "application/rtf",
  "application/msword",
  "application/vnd.ms-",
  "application/vnd.openxmlformats-officedocument.",
  "application/vnd.oasis.opendocument",
  "application/zip",
  "application/x-zip-compressed",
  "application/octet-stream",
] as const;

export class RelayHttpError extends Error {
  public readonly statusCode: number;
  public readonly code: RelayErrorCode;
  public readonly retryable: boolean;
  public readonly details?: unknown;

  constructor(
    statusCode: number,
    code: RelayErrorCode,
    message: string,
    retryable: boolean,
    details?: unknown,
  ) {
    super(message);
    this.name = "RelayHttpError";
    this.statusCode = statusCode;
    this.code = code;
    this.retryable = retryable;
    this.details = details;
  }
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

export function readOptionalString(
  record: Record<string, unknown>,
  field: string,
  maxLength: number = 4096,
): string | undefined {
  const value = record[field];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new RelayHttpError(400, "invalid_request", `${field} must be a string`, false);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return undefined;
  }
  if (trimmed.length > maxLength) {
    throw new RelayHttpError(
      400,
      "invalid_request",
      `${field} exceeds maximum length of ${maxLength}`,
      false,
    );
  }
  return trimmed;
}

export function requireNonEmptyString(
  record: Record<string, unknown>,
  field: string,
  maxLength: number = 4096,
): string {
  const value = readOptionalString(record, field, maxLength);
  if (!value) {
    throw new RelayHttpError(400, "invalid_request", `${field} is required`, false);
  }
  return value;
}

export function readOptionalFiniteNumber(
  record: Record<string, unknown>,
  field: string,
): number | undefined {
  const value = record[field];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new RelayHttpError(400, "invalid_request", `${field} must be a finite number`, false);
  }
  return value;
}

export function requireBearerApiKey(req: Request): string {
  const raw = req.headers.authorization;
  if (!raw || typeof raw !== "string") {
    throw new RelayHttpError(401, "missing_api_key", "Missing Authorization bearer token", false);
  }

  const match = raw.match(/^Bearer\s+(.+)$/i);
  if (!match || !match[1]) {
    throw new RelayHttpError(401, "missing_api_key", "Invalid Authorization header format", false);
  }

  const apiKey = match[1].trim();
  if (!apiKey) {
    throw new RelayHttpError(401, "missing_api_key", "Missing Authorization bearer token", false);
  }

  return apiKey;
}

export function redactApiKey(apiKey: string | undefined | null): string {
  if (!apiKey) {
    return "<empty>";
  }
  if (apiKey.length <= 10) {
    return `${apiKey.slice(0, 2)}***`;
  }
  return `${apiKey.slice(0, 7)}...${apiKey.slice(-4)}`;
}

export function createRelayRunId(): string {
  return `relay_${Date.now().toString(36)}_${randomUUID().replace(/-/g, "")}`;
}

export function createResumeToken(): string {
  return `secret_${randomBytes(16).toString("base64url")}`;
}

export function getMaxUploadBytes(): number {
  const configured = Number(process.env.RELAY_FILE_MAX_BYTES ?? DEFAULT_MAX_UPLOAD_BYTES);
  if (!Number.isFinite(configured) || configured <= 0) {
    return DEFAULT_MAX_UPLOAD_BYTES;
  }
  return configured;
}

function getClientIp(req: Request): string {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    return forwarded.split(",")[0]?.trim() ?? req.ip;
  }
  if (Array.isArray(forwarded) && forwarded.length > 0) {
    return forwarded[0] ?? req.ip;
  }
  return req.ip || req.socket.remoteAddress || "unknown";
}

export function createIpRateLimitMiddleware(options: {
  windowMs: number;
  maxRequests: number;
}): RequestHandler {
  const hits = new Map<string, { count: number; resetAt: number }>();

  return (req: Request, res: Response, next: NextFunction) => {
    const ip = getClientIp(req);
    const now = Date.now();
    const existing = hits.get(ip);

    if (!existing || existing.resetAt <= now) {
      hits.set(ip, {
        count: 1,
        resetAt: now + options.windowMs,
      });
      next();
      return;
    }

    existing.count += 1;

    if (existing.count > options.maxRequests) {
      res.status(429).json({
        error: {
          code: "rate_limited",
          message: "Too many requests",
          retryable: true,
        },
      });
      return;
    }

    next();
  };
}

export function validateCreateRunRequest(body: unknown): RelayRunStartRequest {
  if (!isRecord(body)) {
    throw new RelayHttpError(400, "invalid_request", "Request body must be a JSON object", false);
  }

  const clientRequestId = requireNonEmptyString(body, "clientRequestId", 200);
  const conversationId = requireNonEmptyString(body, "conversationId", 200);
  const model = requireNonEmptyString(body, "model", 200);
  const reasoningEffort = readOptionalString(body, "reasoningEffort", 32);

  const rawMessages = body.messages;
  if (!Array.isArray(rawMessages) || rawMessages.length === 0) {
    throw new RelayHttpError(400, "invalid_request", "messages must be a non-empty array", false);
  }

  const messages = rawMessages.map((message, index) => {
    if (typeof message === "string") {
      return message;
    }
    if (isRecord(message) || Array.isArray(message)) {
      return message;
    }
    throw new RelayHttpError(
      400,
      "invalid_request",
      `messages[${index}] must be an object, array, or string`,
      false,
    );
  });

  let vectorStoreIds: string[] = [];
  if (body.vectorStoreIds !== undefined) {
    if (!Array.isArray(body.vectorStoreIds)) {
      throw new RelayHttpError(400, "invalid_request", "vectorStoreIds must be an array", false);
    }
    vectorStoreIds = body.vectorStoreIds.map((value, index) => {
      if (typeof value !== "string" || !value.trim()) {
        throw new RelayHttpError(
          400,
          "invalid_request",
          `vectorStoreIds[${index}] must be a non-empty string`,
          false,
        );
      }
      return value.trim();
    });
  }

  let metadata: Record<string, unknown> | undefined;
  if (body.metadata !== undefined) {
    if (!isRecord(body.metadata)) {
      throw new RelayHttpError(400, "invalid_request", "metadata must be an object", false);
    }
    metadata = { ...body.metadata };
  }

  return {
    clientRequestId,
    conversationId,
    messages,
    model,
    reasoningEffort,
    vectorStoreIds,
    metadata,
  };
}

function getFileExtension(filename: string): string {
  const lower = filename.toLowerCase();
  const lastDot = lower.lastIndexOf(".");
  return lastDot >= 0 ? lower.slice(lastDot) : "";
}

function isAllowedMimeType(mimeType: string): boolean {
  return ALLOWED_MIME_PREFIXES.some((prefix) => mimeType.startsWith(prefix));
}

export function validateUploadedFile(file: { originalname: string; mimetype: string; size: number; buffer: Buffer } | undefined): { originalname: string; mimetype: string; size: number; buffer: Buffer } {
  if (!file) {
    throw new RelayHttpError(400, "invalid_request", "A multipart file field named 'file' is required", false);
  }

  if (!file.originalname || !file.originalname.trim()) {
    throw new RelayHttpError(400, "invalid_request", "Uploaded file must have a filename", false);
  }

  if (file.size <= 0) {
    throw new RelayHttpError(400, "invalid_request", "Uploaded file is empty", false);
  }

  if (file.size > getMaxUploadBytes()) {
    throw new RelayHttpError(413, "invalid_request", "Uploaded file is too large", false);
  }

  const extension = getFileExtension(file.originalname);
  if (BLOCKED_FILE_EXTENSIONS.has(extension)) {
    throw new RelayHttpError(400, "invalid_request", `File type ${extension} is not allowed`, false);
  }

  const mimeType = file.mimetype || "application/octet-stream";
  if (!isAllowedMimeType(mimeType)) {
    throw new RelayHttpError(400, "invalid_request", `MIME type ${mimeType} is not allowed`, false);
  }

  return file;
}

export function sendRelayErrorResponse(res: Response, error: unknown): void {
  if (res.headersSent) {
    return;
  }

  if (error instanceof RelayHttpError) {
    res.status(error.statusCode).json({
      error: {
        code: error.code,
        message: error.message,
        retryable: error.retryable,
        details: error.details,
      },
    });
    return;
  }

  if (error instanceof Error) {
    res.status(500).json({
      error: {
        code: "internal_error",
        message: error.message,
        retryable: false,
      },
    });
    return;
  }

  res.status(500).json({
    error: {
      code: "internal_error",
      message: "Unknown server error",
      retryable: false,
    },
  });
}
