# GlassGPT 5.4.0 Audit

## Scope

- Restore image upload through the backend-proxied Responses flow.
- Restore file upload through the backend file proxy and `input_file` message parts.
- Restore visible tool-call indicators under 250 ms polling.
- Restore generated file download, caching, and preview for sandbox/code-interpreter outputs.

## Architecture Assertions

- The 5.3+ backend architecture remains in place: iOS talks to Cloudflare Workers, not directly to OpenAI.
- Polling remains the delivery mechanism for live updates; no SSE reintroduction was attempted.
- OpenAI credentials remain backend-only for chat, upload, and download flows.

## Pre-Release Evidence

- Focused feature verification was completed for all four restored capabilities.
- Full backend CI passed cleanly for the 5.4.0 branch.
- Full iOS CI is being rerun after sharding the UI gate to avoid the monolithic runner hang observed in the `ui-tests` lane.

## Release Status

- Backend production deploy: pending
- TestFlight upload for `5.4.0 (20223)`: pending
- Final branch push and `v5.4.0` tag: pending
