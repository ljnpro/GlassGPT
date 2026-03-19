# ``OpenAITransport``

Network transport layer for communicating with the OpenAI Responses API.

## Overview

OpenAITransport encapsulates all HTTP communication with the OpenAI API, including
request construction, response parsing, streaming via Server-Sent Events (SSE), and
file upload operations. The module is designed around protocol abstractions to support
testing and alternative transport implementations.

The transport layer handles both synchronous request/response patterns for operations
like file upload and title generation, as well as long-lived streaming connections for
real-time chat completions.

## Topics

### Service
- ``OpenAIService``
- ``OpenAIServiceError``

### Transport
- ``OpenAIDataTransport``
- ``OpenAIURLSessionTransport``

### Request Building
- ``OpenAIRequestBuilder``
- ``OpenAIRequestFactory``

### Streaming
- ``SSEEventStream``
- ``SSEEventDecoder``
- ``OpenAIStreamEventTranslator``
