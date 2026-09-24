class SharedLocations::WazeMessageService
  def initialize(message:, contact:, content:, shared_at:)
    @message = message
    @contact = contact
    @content = content.to_s
    @shared_at = shared_at
  end

  def perform
    return unless enrichable?

    location = resolve_location
    return if location.blank?

    attach_location(location)
  rescue StandardError => e
    log_exception(e)
    nil
  end

  private

  def enrichable?
    @message.present? &&
      @contact.present? &&
      @message.incoming? &&
      @content.present? &&
      !location_attachment_exists?
  end

  def attach_location(location)
    @message.with_lock do
      return if location_attachment_exists?

      attachment = create_location_attachment(location)
      sync_contact_location(attachment, location)
    end
  end

  def location_attachment_exists?
    @message.attachments.exists?(file_type: :location)
  end

  def resolve_location
    SharedLocations::LocationResolver.new(
      content: @content,
      account_id: @message.account_id
    ).perform
  end

  def create_location_attachment(location)
    @message.attachments.create!(
      account_id: @message.account_id,
      file_type: :location,
      coordinates_lat: location[:latitude],
      coordinates_long: location[:longitude],
      external_url: location[:map_url],
      fallback_title: location[:title].to_s.first(255)
    )
  end

  def sync_contact_location(attachment, location)
    source = contact_location_source(location)
    return if source.blank?

    SharedLocations::ContactLocationSyncService.new(
      contact: @contact,
      location: attachment,
      shared_at: @shared_at,
      source: source
    ).perform
  end

  def contact_location_source(location)
    return 'waze' if location[:resolution_provider] == 'waze'

    channel_location_source
  end

  def channel_location_source
    channel_type = @message.inbox&.channel_type.to_s

    return 'instagram' if channel_type == 'Channel::Instagram'
    return 'whatsapp' if channel_type.match?(/Whatsapp/i)

    nil
  end

  def log_exception(error)
    Rails.logger.warn(
      "[WazeMessageEnrichmentError]: account_id #{@message&.account_id} " \
      "message_id #{@message&.id} #{error.class}"
    )
  end
end
