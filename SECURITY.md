# Security Policy

## Supported Versions

GlassGPT supports the latest released line and, when needed, the previous
release line for critical security fixes only.

As of 2026-03-29:

| Version | Supported |
|---------|-----------|
| 5.2.x   | Yes |
| < 5.2   | No |

Notes:
- The repository currently contains in-progress `5.3.0` hardening work, but
  that line is not treated as a supported release until it is tagged and
  published.
- Security fixes are shipped through the scripted backend/TestFlight release
  process documented in the `5.3.0` tracker and release scripts.

## Reporting A Vulnerability

Please report security issues privately:

1. Email [ljnpro6@gmail.com](mailto:ljnpro6@gmail.com) with a clear summary,
   reproduction steps, affected build or commit, and any supporting logs.
2. Do not open a public GitHub issue for an unpatched vulnerability.
3. An acknowledgement target is 72 hours.
4. Fixes and disclosure timing are coordinated once scope and impact are clear.

## In Scope

- Backend authentication, session management, and credential storage.
- Backend-origin validation, rate limiting, request validation, and release
  environment configuration.
- Device identity handling and persistence on iOS.
- OpenAI credential storage, encryption, or unauthorized disclosure risks.
- Cross-device conversation sync, event replay, and access-control mistakes.
- Build, release, and deployment issues that could expose production secrets or
  publish the wrong backend/app artifacts.

## Out Of Scope

- Vulnerabilities in OpenAI, Cloudflare, Apple, or other third-party platforms
  themselves.
- Issues that require physical access to an already-unlocked device.
- Social engineering or phishing attacks.
- Denial-of-service claims without a reproducible product-specific issue.

## Current Security Posture

- iOS stores backend/device identity and user secrets in platform-secured
  storage rather than raw `UserDefaults` where sensitive material is involved.
- Backend requests are validated at the HTTP boundary and conversation
  configuration is now authoritative on the server.
- Backend origin policy and rate limiting are enforced in the Cloudflare Worker
  path rather than existing only as dead code.
- Release scripts are designed to fail closed when release gates, audit
  artifacts, or deployment prerequisites are missing.
