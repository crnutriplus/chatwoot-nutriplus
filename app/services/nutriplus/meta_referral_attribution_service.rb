class Nutriplus::MetaReferralAttributionService
  CHANNEL_KEYS = {
    instagram: %w[ad_id source type],
    whatsapp: %w[source_id source_type ctwa_clid]
  }.freeze

  class << self
    def sanitize(referral, channel:)
      keys = CHANNEL_KEYS.fetch(channel)
      value = referral.respond_to?(:to_h) ? referral.to_h.deep_stringify_keys : {}

      keys.each_with_object({}) do |key, result|
        item = value[key].to_s.strip
        result[key] = item if item.present?
      end
    end

    def capture(conversation:, contact:, referral:, channel:)
      safe_referral = sanitize(referral, channel: channel)
      return { attributed: false } if safe_referral.blank?

      new(
        conversation: conversation,
        contact: contact,
        referral: safe_referral
      ).perform
    end
  end

  def initialize(conversation:, contact:, referral:)
    @conversation = conversation
    @contact = contact
    @referral = referral
  end

  def perform
    attribution = normalized_attribution
    return { attributed: false } if attribution.blank?
    return { attributed: false } if conflicting_conversation_ad?(attribution[:ad_id])

    persist_contact_first_touch(attribution[:ad_id])
    persist_conversation_attribution(attribution)

    {
      attributed: true,
      ad_id: attribution[:ad_id],
      ctwa_clid: attribution[:ctwa_clid]
    }.compact
  end

  private

  def normalized_attribution
    source = @referral['source'].to_s.strip.upcase
    ad_id = @referral['ad_id'].to_s.strip

    return { source: 'ADS', ad_id: ad_id, ctwa_clid: nil } if source == 'ADS' && ad_id.present?

    source_type = @referral['source_type'].to_s.strip.downcase
    source_id = @referral['source_id'].to_s.strip
    ctwa_clid = @referral['ctwa_clid'].to_s.strip

    return if source_type != 'ad' || source_id.blank?

    { source: 'ADS', ad_id: source_id, ctwa_clid: ctwa_clid.presence }
  end

  def conflicting_conversation_ad?(ad_id)
    existing_ad_id = (@conversation.custom_attributes || {})['meta_ad_id'].to_s.strip
    existing_ad_id.present? && existing_ad_id != ad_id
  end

  def persist_contact_first_touch(ad_id)
    attributes = (@contact.custom_attributes || {}).dup
    return if attributes['first_touch_ad_id'].present?

    @contact.update!(
      custom_attributes: attributes.merge('first_touch_ad_id' => ad_id)
    )
  end

  def persist_conversation_attribution(attribution)
    attributes = (@conversation.custom_attributes || {}).dup
    updates = conversation_updates(attributes, attribution)
    return if updates.empty?

    @conversation.update!(
      custom_attributes: attributes.merge(updates)
    )
  end

  def conversation_updates(attributes, attribution)
    updates = {}
    updates['meta_ad_id'] = attribution[:ad_id] if attributes['meta_ad_id'].blank?
    updates['meta_referral_source'] = attribution[:source] if attributes['meta_referral_source'].blank?
    updates['meta_ctwa_clid'] = attribution[:ctwa_clid] if attribution[:ctwa_clid].present? && attributes['meta_ctwa_clid'].blank?
    updates
  end
end
