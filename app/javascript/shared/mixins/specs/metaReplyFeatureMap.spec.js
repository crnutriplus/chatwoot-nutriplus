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

describe('Meta reply-to feature map', () => {
  const metaChannels = [INBOX_TYPES.FB, INBOX_TYPES.INSTAGRAM];
  const unsupportedChannels = [
    INBOX_TYPES.EMAIL,
    INBOX_TYPES.LINE,
    INBOX_TYPES.SMS,
    INBOX_TYPES.TWILIO,
  ];

  it('enables specific-message reply actions for Facebook and Instagram', () => {
    metaChannels.forEach(channelType => {
      expect(MIXIN_FEATURE_MAP[MIXIN_FEATURES.REPLY_TO_OUTGOING]).toContain(
        channelType
      );
      expect(
        COMPOSABLE_FEATURE_MAP[COMPOSABLE_FEATURES.REPLY_TO_OUTGOING]
      ).toContain(channelType);
    });
  });

  it('keeps unsupported channels excluded from outgoing reply-to actions', () => {
    unsupportedChannels.forEach(channelType => {
      expect(MIXIN_FEATURE_MAP[MIXIN_FEATURES.REPLY_TO_OUTGOING]).not.toContain(
        channelType
      );
      expect(
        COMPOSABLE_FEATURE_MAP[COMPOSABLE_FEATURES.REPLY_TO_OUTGOING]
      ).not.toContain(channelType);
    });
  });

  it('keeps both frontend feature maps aligned', () => {
    expect(
      COMPOSABLE_FEATURE_MAP[COMPOSABLE_FEATURES.REPLY_TO_OUTGOING]
    ).toEqual(MIXIN_FEATURE_MAP[MIXIN_FEATURES.REPLY_TO_OUTGOING]);
  });
});
