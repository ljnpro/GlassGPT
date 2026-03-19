# ``ChatRuntimeWorkflows``

Actor-based runtime state management for chat reply sessions.

## Overview

ChatRuntimeWorkflows provides thread-safe state management for assistant reply sessions
using Swift actors. The module owns the mutable state of each reply—including text buffers,
tool call tracking, citation collection, and lifecycle management—and ensures all mutations
are serialized through actor isolation.

The central type is ReplySessionActor, which applies ReplyRuntimeTransition values to
produce updated ReplyRuntimeState snapshots. A RuntimeRegistryActor manages the collection
of active sessions across the application.

## Topics

### Session Management
- ``ReplySessionActor``
- ``RuntimeRegistryActor``

### Transitions
- ``RuntimeTransitionError``

### State
- ``ReplySession``
