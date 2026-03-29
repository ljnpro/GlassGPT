import type {
  ArtifactDTO,
  ConversationDetailDTO,
  ConversationDTO,
  ConversationPageDTO,
  MessageDTO,
  RunEventDTO,
  RunSummaryDTO,
  SyncEnvelopeDTO,
} from '@glassgpt/backend-contracts';
import {
  filePathAnnotationSchema,
  toolCallInfoSchema,
  urlCitationSchema,
} from '@glassgpt/backend-contracts';
import { z } from 'zod';
import type { ArtifactRecord } from '../domain/artifact-model.js';
import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunEventRecord } from '../domain/run-event-model.js';
import type { RunRecord } from '../domain/run-model.js';
import { parseOptionalJSONPayload } from './json-payload-codec.js';

const messageAnnotationsSchema = z.array(urlCitationSchema);
const messageFilePathAnnotationsSchema = z.array(filePathAnnotationSchema);
const messageToolCallsSchema = z.array(toolCallInfoSchema);

export const buildConversationDTO = (conversation: ConversationRecord): ConversationDTO => {
  return {
    agentWorkerReasoningEffort: conversation.agentWorkerReasoningEffort ?? undefined,
    createdAt: conversation.createdAt,
    id: conversation.id,
    lastRunId: conversation.lastRunId ?? undefined,
    lastSyncCursor: conversation.lastSyncCursor ?? undefined,
    model: conversation.model ?? undefined,
    mode: conversation.mode,
    reasoningEffort: conversation.reasoningEffort ?? undefined,
    serviceTier: conversation.serviceTier ?? undefined,
    title: conversation.title,
    updatedAt: conversation.updatedAt,
  };
};

export const buildConversationPageDTO = (
  conversations: ConversationRecord[],
  nextCursor: string | null,
  hasMore: boolean,
): ConversationPageDTO => {
  return {
    hasMore,
    items: conversations.map(buildConversationDTO),
    nextCursor: nextCursor ?? undefined,
  };
};

export const buildMessageDTO = (message: MessageRecord): MessageDTO => {
  return {
    agentTraceJSON: message.agentTraceJSON ?? undefined,
    annotations: parseOptionalJSONPayload(message.annotationsJSON, messageAnnotationsSchema),
    completedAt: message.completedAt ?? undefined,
    content: message.content,
    conversationId: message.conversationId,
    createdAt: message.createdAt,
    filePathAnnotations: parseOptionalJSONPayload(
      message.filePathAnnotationsJSON,
      messageFilePathAnnotationsSchema,
    ),
    id: message.id,
    role: message.role,
    runId: message.runId ?? undefined,
    serverCursor: message.serverCursor ?? undefined,
    thinking: message.thinking ?? undefined,
    toolCalls: parseOptionalJSONPayload(message.toolCallsJSON, messageToolCallsSchema),
  };
};

export const buildRunSummaryDTO = (run: RunRecord): RunSummaryDTO => {
  return {
    conversationId: run.conversationId,
    createdAt: run.createdAt,
    id: run.id,
    kind: run.kind,
    lastEventCursor: run.lastEventCursor ?? undefined,
    processSnapshotJSON: run.processSnapshotJSON ?? undefined,
    stage: run.stage ?? undefined,
    status: run.status,
    updatedAt: run.updatedAt,
    visibleSummary: run.visibleSummary ?? undefined,
  };
};

export const buildArtifactDTO = (artifact: ArtifactRecord): ArtifactDTO => {
  return {
    byteCount: artifact.byteCount,
    contentType: artifact.contentType,
    conversationId: artifact.conversationId,
    createdAt: artifact.createdAt,
    filename: artifact.filename,
    id: artifact.id,
    kind: artifact.kind,
    runId: artifact.runId,
  };
};

export const buildRunEventDTO = (event: RunEventRecord): RunEventDTO => {
  return {
    artifact: event.artifact ? buildArtifactDTO(event.artifact) : undefined,
    artifactId: event.artifactId ?? undefined,
    conversation: event.conversation ? buildConversationDTO(event.conversation) : undefined,
    conversationId: event.conversationId,
    createdAt: event.createdAt,
    cursor: event.cursor,
    id: event.id,
    kind: event.kind,
    message: event.message ? buildMessageDTO(event.message) : undefined,
    progressLabel: event.progressLabel ?? undefined,
    run: event.run ? buildRunSummaryDTO(event.run) : undefined,
    runId: event.runId,
    stage: event.stage ?? undefined,
    textDelta: event.textDelta ?? undefined,
  };
};

export const buildConversationDetailDTO = (
  conversation: ConversationRecord,
  messages: MessageRecord[],
  runs: RunRecord[],
): ConversationDetailDTO => {
  return {
    conversation: buildConversationDTO(conversation),
    messages: messages.map(buildMessageDTO),
    runs: runs.map(buildRunSummaryDTO),
  };
};

export const buildSyncEnvelopeDTO = (
  events: RunEventRecord[],
  nextCursor: string | null,
): SyncEnvelopeDTO => {
  return {
    events: events.map(buildRunEventDTO),
    nextCursor: nextCursor ?? undefined,
  };
};
