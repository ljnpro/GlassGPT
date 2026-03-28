import { describe, expect, it } from 'vitest';
import {
  artifactDownloadFixture,
  artifactFixture,
  connectionCheckFixture,
  conversationDetailFixture,
  conversationFixture,
  conversationListFixture,
  credentialStatusFixture,
  messageFixture,
  runEventFixture,
  runSummaryFixture,
  sessionFixture,
  syncEnvelopeFixture,
  userFixture,
} from './fixtures.js';
import {
  artifactDownloadSchema,
  artifactSchema,
  connectionCheckSchema,
  conversationDetailSchema,
  conversationListSchema,
  conversationSchema,
  credentialStatusSchema,
  messageSchema,
  runEventSchema,
  runSummarySchema,
  sessionSchema,
  syncEnvelopeSchema,
  userSchema,
} from './index.js';

describe('backend contracts', () => {
  it('validate DTO fixtures against their schemas', () => {
    expect(userSchema.parse(userFixture)).toEqual(userFixture);
    expect(sessionSchema.parse(sessionFixture)).toEqual(sessionFixture);
    expect(credentialStatusSchema.parse(credentialStatusFixture)).toEqual(credentialStatusFixture);
    expect(connectionCheckSchema.parse(connectionCheckFixture)).toEqual(connectionCheckFixture);
    expect(conversationSchema.parse(conversationFixture)).toEqual(conversationFixture);
    expect(conversationListSchema.parse(conversationListFixture)).toEqual(conversationListFixture);
    expect(conversationDetailSchema.parse(conversationDetailFixture)).toEqual(
      conversationDetailFixture,
    );
    expect(messageSchema.parse(messageFixture)).toEqual(messageFixture);
    expect(runSummarySchema.parse(runSummaryFixture)).toEqual(runSummaryFixture);
    expect(runEventSchema.parse(runEventFixture)).toEqual(runEventFixture);
    expect(syncEnvelopeSchema.parse(syncEnvelopeFixture)).toEqual(syncEnvelopeFixture);
    expect(artifactSchema.parse(artifactFixture)).toEqual(artifactFixture);
    expect(artifactDownloadSchema.parse(artifactDownloadFixture)).toEqual(artifactDownloadFixture);
  });
});
