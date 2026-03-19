# ``ChatDomain``

Core domain types for the GlassGPT chat application.

## Overview

ChatDomain defines the fundamental value types, enumerations, and protocols that model
the chat domain. These types are used throughout the application stack from persistence
to presentation. The module has zero dependencies beyond Foundation, ensuring it can be
imported by any layer in the architecture.

Key responsibilities include modeling conversation configuration, message content types,
streaming events, and model selection parameters.

## Topics

### Models
- ``ModelType``
- ``ReasoningEffort``
- ``ServiceTier``
- ``AppTheme``

### Conversation
- ``ConversationConfiguration``
- ``APIMessage``

### Streaming
- ``StreamEvent``
- ``StreamCursor``

### File Support
- ``FileAttachment``
- ``URLCitation``
- ``FilePathAnnotation``
