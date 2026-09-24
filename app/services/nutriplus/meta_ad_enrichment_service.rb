class Nutriplus::MetaAdEnrichmentService
  GRAPH_FIELDS = [
    'id',
    'name',
    'adset{id,name}',
    'campaign{id,name}',
    'adset_id',
    'campaign_id',
    'creative{id,name,thumbnail_url}'
  ].join(',').freeze

  TRANSIENT_HTTP_CODES = [429, 500, 502, 503, 504].freeze

  class TransientError < StandardError; end

  def initialize(conversation:, ad_id:, access_token: nil, graph_version: nil)
    @conversation = conversation
    @ad_id = ad_id.to_s.strip
    @access_token = access_token
    @graph_version = graph_version.presence ||
                     ENV['NUTRIPLUS_META_GRAPH_API_VERSION'].presence ||
                     GlobalConfigService.load('FB_API_VERSION', 'v22.0')
  end

  def perform
    return result(false, :missing_ad_id) if @ad_id.blank?
    return result(false, :invalid_ad_id) unless @ad_id.match?(/\A\d+\z/)
    return result(false, :stale_attribution) unless current_ad_matches?

    token = resolved_access_token
    return missing_token_result if token.blank?

    response = fetch_ad(token)
    raise TransientError, "Meta Graph API returned HTTP #{response.code}" if TRANSIENT_HTTP_CODES.include?(response.code)

    return graph_error_result(response) unless response.success?

    data = response.parsed_response
    return result(false, :invalid_response) unless data.is_a?(Hash)
    return result(false, :ad_id_mismatch) unless data['id'].to_s == @ad_id

    refresh_conversation
    return result(false, :stale_attribution) unless current_ad_matches?

    updates = enrichment_attributes(data)
    persist_updates(updates)

    {
      enriched: true,
      ad_id: @ad_id,
      adset_id: updates['meta_adset_id'],
      campaign_id: updates['meta_campaign_id'],
      creative_id: updates['meta_creative_id']
    }.compact
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED => e
    raise TransientError, e.message
  rescue TransientError
    raise
  rescue StandardError => e
    Rails.logger.warn(
      "[NUTRIPLUS_META_AD_ENRICHMENT] conversation_id=#{conversation_id_for_log} ad_id=#{@ad_id} " \
      "error=#{e.class}: #{e.message}"
    )
    result(false, :error)
  end

  private

  def fetch_ad(token)
    HTTParty.get(
      "https://graph.facebook.com/#{@graph_version}/#{@ad_id}",
      query: { fields: GRAPH_FIELDS },
      headers: { 'Authorization' => "Bearer #{token}" }
    )
  end

  def resolved_access_token
    direct_token = @access_token.to_s.strip
    return direct_token if direct_token.present?

    token_file = ENV['NUTRIPLUS_META_ADS_READ_TOKEN_FILE'].to_s.strip
    return File.read(token_file).strip if token_file.present? && File.file?(token_file)

    ENV['NUTRIPLUS_META_ADS_READ_TOKEN'].to_s.strip
  rescue StandardError => e
    Rails.logger.warn(
      "[NUTRIPLUS_META_AD_ENRICHMENT] conversation_id=#{conversation_id_for_log} ad_id=#{@ad_id} " \
      "token_file_error=#{e.class}"
    )
    ''
  end

  def current_ad_matches?
    attributes = @conversation.custom_attributes || {}
    attributes['meta_ad_id'].to_s.strip == @ad_id
  end

  def refresh_conversation
    @conversation.reload if @conversation.respond_to?(:reload)
  end

  def enrichment_attributes(data)
    {
      'meta_adset_id' => data['adset_id'].presence || data.dig('adset', 'id').presence,
      'meta_campaign_id' => data['campaign_id'].presence || data.dig('campaign', 'id').presence,
      'meta_ad_name' => data['name'].presence,
      'meta_adset_name' => data.dig('adset', 'name').presence,
      'meta_campaign_name' => data.dig('campaign', 'name').presence,
      'meta_creative_id' => data.dig('creative', 'id').presence,
      'meta_creative_name' => data.dig('creative', 'name').presence,
      'meta_ad_thumbnail_url' => data.dig('creative', 'thumbnail_url').presence
    }.compact
  end

  def persist_updates(updates)
    attributes = (@conversation.custom_attributes || {}).dup
    changes = updates.each_with_object({}) do |(key, value), memo|
      memo[key] = value if value.present? && attributes[key].blank?
    end
    return if changes.empty?

    @conversation.update!(custom_attributes: attributes.merge(changes))
  end

  def missing_token_result
    Rails.logger.warn(
      "[NUTRIPLUS_META_AD_ENRICHMENT] conversation_id=#{conversation_id_for_log} ad_id=#{@ad_id} missing_ads_read_token=true"
    )
    result(false, :missing_token)
  end

  def graph_error_result(response)
    parsed = response.parsed_response
    error_code = parsed.is_a?(Hash) ? parsed.dig('error', 'code') : nil
    error_type = parsed.is_a?(Hash) ? parsed.dig('error', 'type') : nil

    Rails.logger.warn(
      "[NUTRIPLUS_META_AD_ENRICHMENT] conversation_id=#{conversation_id_for_log} ad_id=#{@ad_id} " \
      "http_status=#{response.code} meta_error_code=#{error_code} meta_error_type=#{error_type}"
    )

    result(false, :graph_error)
  end

  def conversation_id_for_log
    @conversation.respond_to?(:id) ? @conversation.id : nil
  end

  def result(enriched, reason)
    { enriched: enriched, reason: reason }
  end
end
