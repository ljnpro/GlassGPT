import type { Hono } from 'hono';

export type BackendApp = Hono<{ Bindings: Env }>;
