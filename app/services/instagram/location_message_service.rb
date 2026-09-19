class Instagram::LocationMessageService
  def initialize(messaging:, inbox:, outgoing_echo:)
    @messaging = messaging
    @inbox = inbox
    @outgoing_echo = outgoing_echo
  end

  def location_attachment
    return unless location_template_candidate?

    location = fetch_location_template
    return if location.blank?

    build_location_attachment(location)
  end

  def location_params(attachment)
    coordinates = attachment.dig('payload', 'coordinates') || {}

    {
      external_url: attachment['url'],
      coordinates_lat: coordinates['lat'],
      coordinates_long: coordinates['long'],
      fallback_title: attachment['title']
    }
  end

  def sync_contact_location(message:, contact:)
    return if @outgoing_echo

    location = message.attachments.find_by(file_type: :location)
    return if location.blank?

    shared_at = shared_location_timestamp
    return if newer_location_already_stored?(contact, shared_at)

    contact.update!(custom_attributes: merged_location_attributes(contact, location, shared_at))
  end

  private

  def location_template_candidate?
    message = @messaging[:message]
    return false if @outgoing_echo || message[:text].present?

    attachments = message[:attachments]
    attachments.present? && attachments.all? { |attachment| attachment['type'].to_s == 'template' }
  end

  def fetch_location_template
    response = location_graph_response
    unless response.success?
      log_http_error(response)
      return
    end

    graph_attachments(response).filter_map { |attachment| location_from_graph_attachment(attachment) }.first
  rescue StandardError => e
    log_exception(e)
    nil
  end

  def location_graph_response
    HTTParty.get(
      "#{base_uri}/#{message_identifier}",
      query: {
        fields: 'attachments',
        access_token: @inbox.channel.access_token
      }
    )
  end

  def graph_attachments(response)
    JSON.parse(response.body).with_indifferent_access.dig(:attachments, :data) || []
  end

  def location_from_graph_attachment(attachment)
    template = attachment[:generic_template]
    return if template.blank?

    coordinates = coordinates_from_location_media_url(template[:media_url])
    return if coordinates.blank?

    coordinates.merge(title: template[:title].presence || 'Location')
  end

  def coordinates_from_location_media_url(media_url)
    uri = URI.parse(media_url.to_s)
    return unless uri.path&.end_with?('/static_map.php')

    coordinate_pair(decoded_markers(uri))
  end

  def decoded_markers(uri)
    markers = URI.decode_www_form(uri.query.to_s).to_h['markers']
    return if markers.blank?

    2.times { markers = URI.decode_www_form_component(markers) }
    markers
  end

  def coordinate_pair(markers)
    match = markers.to_s.match(/\A\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)/)
    return if match.blank?

    lat_string, long_string = match.captures
    return unless valid_coordinates?(lat_string, long_string)

    {
      lat: lat_string,
      long: long_string,
      map_url: "https://maps.google.com/?q=#{lat_string},#{long_string}"
    }
  end

  def valid_coordinates?(lat_string, long_string)
    Float(lat_string).between?(-90, 90) && Float(long_string).between?(-180, 180)
  end

  def build_location_attachment(location)
    {
      'type' => 'location',
      'title' => location[:title],
      'url' => location[:map_url],
      'payload' => {
        'coordinates' => {
          'lat' => location[:lat],
          'long' => location[:long]
        }
      }
    }.with_indifferent_access
  end

  def shared_location_timestamp
    raw_timestamp = @messaging[:timestamp]
    return Time.current if raw_timestamp.blank?
    return numeric_timestamp(raw_timestamp) if raw_timestamp.to_s.match?(/\A\d+(?:\.\d+)?\z/)

    Time.zone.parse(raw_timestamp.to_s)
  rescue ArgumentError, TypeError
    Time.current
  end

  def numeric_timestamp(raw_timestamp)
    timestamp = Float(raw_timestamp)
    timestamp /= 1000.0 if timestamp > 10_000_000_000
    Time.zone.at(timestamp)
  end

  def newer_location_already_stored?(contact, shared_at)
    stored_at = contact.custom_attributes&.[]('last_shared_location_at')
    return false if stored_at.blank?

    Time.zone.parse(stored_at.to_s) > shared_at
  rescue ArgumentError, TypeError
    false
  end

  def merged_location_attributes(contact, location, shared_at)
    (contact.custom_attributes || {}).merge(
      'location_url' => location.external_url,
      'last_shared_latitude' => location.coordinates_lat,
      'last_shared_longitude' => location.coordinates_long,
      'last_shared_location_at' => shared_at.iso8601(3),
      'last_shared_location_source' => 'instagram'
    )
  end

  def log_http_error(response)
    Rails.logger.warn(
      "[InstagramLocationFetchError]: account_id #{@inbox.account_id} " \
      "message_id #{message_identifier} status #{response.code}"
    )
  end

  def log_exception(error)
    Rails.logger.warn(
      "[InstagramLocationFetchError]: account_id #{@inbox.account_id} " \
      "message_id #{message_identifier} #{error.class}: #{error.message}"
    )
  end

  def message_identifier
    @messaging.dig(:message, :mid)
  end

  def base_uri
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
