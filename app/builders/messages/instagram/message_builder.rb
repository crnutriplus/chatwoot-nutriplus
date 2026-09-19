class Messages::Instagram::MessageBuilder < Messages::Instagram::BaseMessageBuilder
  def initialize(messaging, inbox, outgoing_echo: false)
    super(messaging, inbox, outgoing_echo: outgoing_echo)
  end

  private

  def prepare_location_attachment
    return unless location_template_candidate?

    location = fetch_location_template
    return if location.blank?

    @messaging[:message][:attachments] = [
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
    ]
  end

  def location_template_candidate?
    return false if @outgoing_echo
    return false if message_content.present?
    return false if attachments.blank?

    attachments.all? { |attachment| attachment['type'].to_s == 'template' }
  end

  def fetch_location_template
    response = HTTParty.get(
      "#{base_uri}/#{message_identifier}",
      query: {
        fields: 'attachments',
        access_token: @inbox.channel.access_token
      }
    )

    unless response.success?
      Rails.logger.warn(
        "[InstagramLocationFetchError]: account_id #{@inbox.account_id} " \
        "message_id #{message_identifier} status #{response.code}"
      )
      return
    end

    result = JSON.parse(response.body).with_indifferent_access
    graph_attachments = result.dig(:attachments, :data) || []

    graph_attachments.each do |attachment|
      template = attachment[:generic_template]
      next if template.blank?

      coordinates = coordinates_from_location_media_url(template[:media_url])
      next if coordinates.blank?

      return coordinates.merge(title: template[:title].presence || 'Location')
    end

    nil
  rescue StandardError => e
    Rails.logger.warn(
      "[InstagramLocationFetchError]: account_id #{@inbox.account_id} " \
      "message_id #{message_identifier} #{e.class}: #{e.message}"
    )
    nil
  end

  def coordinates_from_location_media_url(media_url)
    uri = URI.parse(media_url.to_s)
    return unless uri.path&.end_with?('/static_map.php')

    markers = URI.decode_www_form(uri.query.to_s).to_h['markers']
    return if markers.blank?

    2.times do
      decoded = URI.decode_www_form_component(markers)
      break if decoded == markers

      markers = decoded
    end

    match = markers.match(/\A\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)/)
    return if match.blank?

    lat_string = match[1]
    long_string = match[2]
    lat = Float(lat_string)
    long = Float(long_string)

    return unless lat.between?(-90, 90) && long.between?(-180, 180)

    {
      lat: lat_string,
      long: long_string,
      map_url: "https://maps.google.com/?q=#{lat_string},#{long_string}"
    }
  end

  def get_story_object_from_source_id(source_id)
    url = "#{base_uri}/#{source_id}?fields=story,from&access_token=#{@inbox.channel.access_token}"

    response = HTTParty.get(url)

    return JSON.parse(response.body).with_indifferent_access if response.success?

    # Create message first if it doesn't exist
    @message ||= conversation.messages.create!(message_params)
    handle_error_response(response)
    nil
  end

  def handle_error_response(response)
    parsed_response = JSON.parse(response.body)
    error_code = parsed_response.dig('error', 'code')

    # https://developers.facebook.com/docs/messenger-platform/error-codes
    # Access token has expired or become invalid.
    channel.authorization_error! if error_code == 190

    # There was a problem scraping data from the provided link.
    # https://developers.facebook.com/docs/graph-api/guides/error-handling/ search for error code 1609005
    if error_code == 1_609_005
      @message.attachments.destroy_all
      @message.update(content: I18n.t('conversations.messages.instagram_deleted_story_content'))
    end

    Rails.logger.error("[InstagramStoryFetchError]: #{parsed_response.dig('error', 'message')} #{error_code}")
  end

  def base_uri
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
