# ``AITransportContracts``

Provider-agnostic protocols and types for AI completion services.

## Overview

AITransportContracts defines the interface boundary between the application's runtime
and composition layers and any AI provider backend. By depending on these contracts
rather than on a specific provider module (such as OpenAITransport), the runtime
evaluators and composition coordinators remain decoupled from provider implementation
details.

This module enables multi-provider support: OpenAI, Claude, Gemini, or local models
like Ollama can all conform to ``AICompletionService`` without requiring changes to
the runtime or composition layers.

## Topics

### Service Protocol
- ``AICompletionService``

### Stream Events
- ``AIStreamEvent``

### Response Types
- ``AIResponseFetchResult``

### Error Handling
- ``AIServiceError``
