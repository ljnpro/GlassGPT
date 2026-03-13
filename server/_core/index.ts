import "dotenv/config";
import express from "express";
import { createServer } from "http";
import net from "net";
import { Server } from "socket.io";
import { createExpressMiddleware } from "@trpc/server/adapters/express";
import { registerOAuthRoutes } from "./oauth";
import { appRouter } from "../routers";
import { createContext } from "./context";
import { OpenAIRelayService } from "../openai-relay";
import { registerRelayRoutes } from "../relay-routes";
import { registerRelaySocketHandlers } from "../relay-socket";
import { RelayStore } from "../relay-store";
import { RELAY_SOCKET_PATH } from "../relay-types";

function isPortAvailable(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.listen(port, () => {
      server.close(() => resolve(true));
    });
    server.on("error", () => resolve(false));
  });
}

async function findAvailablePort(startPort: number = 3000): Promise<number> {
  for (let port = startPort; port < startPort + 20; port++) {
    if (await isPortAvailable(port)) {
      return port;
    }
  }
  throw new Error(`No available port found starting from ${startPort}`);
}

async function startServer() {
  const app = express();
  const server = createServer(app);

  app.disable("x-powered-by");
  app.set("trust proxy", true);

  // Enable CORS for all routes - reflect the request origin to support credentials
  app.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin) {
      res.header("Access-Control-Allow-Origin", origin);
    }
    res.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    res.header(
      "Access-Control-Allow-Headers",
      "Origin, X-Requested-With, Content-Type, Accept, Authorization",
    );
    res.header("Access-Control-Allow-Credentials", "true");

    if (req.method === "OPTIONS") {
      res.sendStatus(200);
      return;
    }
    next();
  });

  app.use(express.json({ limit: "50mb" }));
  app.use(express.urlencoded({ limit: "50mb", extended: true }));

  const io = new Server(server, {
    path: RELAY_SOCKET_PATH,
    transports: ["websocket"],
    serveClient: false,
    cors: {
      origin: true,
      credentials: true,
    },
    connectionStateRecovery: {
      maxDisconnectionDuration: 2 * 60_000,
      skipMiddlewares: true,
    },
  });

  const relayStore = new RelayStore();
  const relayService = new OpenAIRelayService(relayStore, io);

  registerOAuthRoutes(app);
  registerRelayRoutes(app, { store: relayStore, relay: relayService });
  registerRelaySocketHandlers(io, { store: relayStore, relay: relayService });

  app.get("/api/health", (_req, res) => {
    res.json({ ok: true, timestamp: Date.now() });
  });

  app.use(
    "/api/trpc",
    createExpressMiddleware({
      router: appRouter,
      createContext,
    }),
  );

  const preferredPort = parseInt(process.env.PORT || "3000");
  const port = await findAvailablePort(preferredPort);

  if (port !== preferredPort) {
    console.log(`Port ${preferredPort} is busy, using port ${port} instead`);
  }

  const shutdown = (signal: string) => {
    console.log(`[api] received ${signal}, shutting down`);
    relayStore.dispose();
    io.close();
    server.close((error?: Error) => {
      if (error) {
        console.error("[api] shutdown error", error);
        process.exit(1);
        return;
      }
      process.exit(0);
    });
  };

  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));

  server.listen(port, () => {
    console.log(`[api] server listening on port ${port}`);
    console.log(`[api] socket.io listening on path ${RELAY_SOCKET_PATH}`);
  });
}

startServer().catch(console.error);
