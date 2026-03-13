import express, { type Express, type NextFunction, type Request, type RequestHandler, type Response } from "express";
import multer from "multer";
import type { OpenAIRelayService } from "./openai-relay";
import type { RelayStore } from "./relay-store";
import {
  RELAY_HTTP_BASE_PATH,
  type RelayCancelRequestBody,
  type RelayRunStartRequest,
  type RelayRunStartResponse,
} from "./relay-types";
import {
  RelayHttpError,
  createIpRateLimitMiddleware,
  createRelayRunId,
  createResumeToken,
  getMaxUploadBytes,
  isRecord,
  requireBearerApiKey,
  requireNonEmptyString,
  sendRelayErrorResponse,
  validateCreateRunRequest,
  validateUploadedFile,
} from "./relay-security";

type RelayRouteDeps = {
  store: RelayStore;
  relay: OpenAIRelayService;
};

type AsyncRouteHandler = (req: Request, res: Response, next: NextFunction) => Promise<void>;

function asyncHandler(handler: AsyncRouteHandler): RequestHandler {
  return (req, res, next) => {
    void handler(req, res, next).catch(next);
  };
}

function validateCancelRequestBody(body: unknown): RelayCancelRequestBody {
  if (!isRecord(body)) {
    throw new RelayHttpError(400, "invalid_request", "Invalid cancel request body", false);
  }

  return {
    resumeToken: requireNonEmptyString(body, "resumeToken"),
  };
}

function createUploadMiddleware() {
  return multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: getMaxUploadBytes(),
      files: 1,
    },
  });
}

export function registerRelayRoutes(app: Express, deps: RelayRouteDeps): void {
  const router = express.Router();
  const upload = createUploadMiddleware();

  const generalLimiter = createIpRateLimitMiddleware({
    windowMs: 60_000,
    maxRequests: 120,
  });

  const uploadLimiter = createIpRateLimitMiddleware({
    windowMs: 60_000,
    maxRequests: 20,
  });

  router.post(
    "/files",
    uploadLimiter,
    upload.single("file"),
    asyncHandler(async (req, res) => {
      const apiKey = requireBearerApiKey(req);
      const file = validateUploadedFile(req.file);

      const response = await deps.relay.uploadFile({
        apiKey,
        filename: file.originalname || "upload",
        contentType: file.mimetype || "application/octet-stream",
        buffer: file.buffer,
      });

      res.json(response);
    }),
  );

  router.post(
    "/runs",
    generalLimiter,
    asyncHandler(async (req, res) => {
      const apiKey = requireBearerApiKey(req);
      const body: RelayRunStartRequest = validateCreateRunRequest(req.body);

      const existing = deps.store.getRunByClientRequestId(body.clientRequestId);
      if (existing) {
        const deduped: RelayRunStartResponse = {
          relayRunId: existing.relayRunId,
          resumeToken: existing.resumeToken,
          status: existing.status,
          responseId: existing.responseId,
        };
        res.status(200).json(deduped);
        return;
      }

      const run = deps.store.createRun({
        relayRunId: createRelayRunId(),
        resumeToken: createResumeToken(),
        conversationId: body.conversationId,
        clientRequestId: body.clientRequestId,
        model: body.model,
        reasoningEffort: body.reasoningEffort ?? "none",
        vectorStoreIds: body.vectorStoreIds ?? [],
        metadata: body.metadata,
        status: "starting",
      });

      const payload: RelayRunStartResponse = {
        relayRunId: run.relayRunId,
        resumeToken: run.resumeToken,
        status: run.status,
      };

      res.status(202).json(payload);

      void Promise.resolve()
        .then(() =>
          deps.relay.startBackgroundStream({
            relayRunId: run.relayRunId,
            apiKey,
            request: body,
          }),
        )
        .catch((error) => {
          console.error("[relay-routes] failed to start background stream", {
            relayRunId: run.relayRunId,
            clientRequestId: body.clientRequestId,
            error: error instanceof Error ? error.message : String(error),
          });
        });
    }),
  );

  router.post(
    "/runs/:id/cancel",
    generalLimiter,
    asyncHandler(async (req, res) => {
      const apiKey = requireBearerApiKey(req);
      const relayRunId = req.params.id as string;
      const body = validateCancelRequestBody(req.body);
      const run = deps.store.getRun(relayRunId);

      if (!run) {
        throw new RelayHttpError(404, "not_found", "Relay run not found", false);
      }

      if (run.resumeToken !== body.resumeToken) {
        throw new RelayHttpError(403, "forbidden", "Invalid relay resume token", false);
      }

      const cancelled = await deps.relay.cancelRun({
        relayRunId,
        apiKey,
      });

      res.json({
        ok: true,
        relayRunId: cancelled.relayRunId,
        status: cancelled.status,
        responseId: cancelled.responseId,
      });
    }),
  );

  router.get(
    "/runs/:id/status",
    generalLimiter,
    asyncHandler(async (req, res) => {
      const relayRunId = req.params.id as string;
      const resumeToken =
        typeof req.query.resumeToken === "string" ? req.query.resumeToken : undefined;

      if (!resumeToken) {
        throw new RelayHttpError(400, "invalid_request", "resumeToken query parameter is required", false);
      }

      const run = deps.store.getRun(relayRunId);
      if (!run) {
        throw new RelayHttpError(404, "not_found", "Relay run not found", false);
      }

      if (run.resumeToken !== resumeToken) {
        throw new RelayHttpError(403, "forbidden", "Invalid relay resume token", false);
      }

      res.json(deps.store.toStatusResponse(relayRunId));
    }),
  );

  router.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (error instanceof multer.MulterError) {
      const statusCode = error.code === "LIMIT_FILE_SIZE" ? 413 : 400;
      sendRelayErrorResponse(
        res,
        new RelayHttpError(statusCode, "invalid_request", error.message, false),
      );
      return;
    }

    sendRelayErrorResponse(res, error);
  });

  app.use(RELAY_HTTP_BASE_PATH, router);
}
