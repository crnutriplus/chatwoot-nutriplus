import { describe, expect, it } from 'vitest';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  INBOX_FEATURE_MAP as MIXIN_FEATURE_MAP,
  INBOX_FEATURES as MIXIN_FEATURES,
} from '../inboxMixin';
import {
  INBOX_FEATURE_MAP as COMPOSABLE_FEATURE_MAP,
  INBOX_FEATURES as COMPOSABLE_FEATURES,
} from 'dashboard/composables/useInbox';

describe('WhatsApp Cloud reply-to feature map', () => {
  it('keeps WhatsApp enabled for incoming and outgoing specific-message replies', () => {
    expect(MIXIN_FEATURE_MAP[MIXIN_FEATURES.REPLY_TO]).toContain(
      INBOX_TYPES.WHATSAPP
    );
    expect(MIXIN_FEATURE_MAP[MIXIN_FEATURES.REPLY_TO_OUTGOING]).toContain(
      INBOX_TYPES.WHATSAPP
    );
    expect(COMPOSABLE_FEATURE_MAP[COMPOSABLE_FEATURES.REPLY_TO]).toContain(
      INBOX_TYPES.WHATSAPP
    );
    expect(
      COMPOSABLE_FEATURE_MAP[COMPOSABLE_FEATURES.REPLY_TO_OUTGOING]
    ).toContain(INBOX_TYPES.WHATSAPP);
  });

  it('does not treat Twilio as the native WhatsApp Cloud inbox type', () => {
    expect(MIXIN_FEATURE_MAP[MIXIN_FEATURES.REPLY_TO_OUTGOING]).not.toContain(
      INBOX_TYPES.TWILIO
    );
    expect(
      COMPOSABLE_FEATURE_MAP[COMPOSABLE_FEATURES.REPLY_TO_OUTGOING]
    ).not.toContain(INBOX_TYPES.TWILIO);
  });
});
