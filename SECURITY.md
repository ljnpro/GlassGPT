# Security Policy

## Supported Versions

Only the latest minor release is actively supported with security updates.

| Version | Supported          |
|---------|--------------------|
| 4.8.x   | Yes                |
| 4.7.x   | Security fixes only|
| < 4.7   | No                 |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Email** [ljnpro6@gmail.com](mailto:ljnpro6@gmail.com) with a detailed
   description of the issue, steps to reproduce, and any relevant logs or
   screenshots.
2. **Do not** open a public GitHub issue for security vulnerabilities.
3. You will receive an acknowledgment within **72 hours**.
4. We will work with you to understand the scope, develop a fix, and coordinate
   disclosure.

## Scope

The following areas are in scope for security reports:

- **API key storage** -- GlassGPT stores the user's OpenAI API key in the
  iOS Keychain. Reports related to key leakage, insecure storage, or
  unauthorized access are in scope.
- **HTTPS-only transport** -- All network communication with the OpenAI API
  uses HTTPS with certificate validation. Reports related to cleartext
  transmission or certificate bypasses are in scope.
- **No telemetry or analytics** -- GlassGPT does not collect or transmit any
  usage data, analytics, or telemetry. If you discover data being sent to any
  endpoint other than the configured OpenAI API, please report it.

## Out of Scope

- Vulnerabilities in the OpenAI API itself.
- Issues requiring physical access to an unlocked device.
- Social engineering attacks.
