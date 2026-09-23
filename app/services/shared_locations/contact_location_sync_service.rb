class SharedLocations::ContactLocationSyncService
  def initialize(contact:, location:, shared_at:, source:)
    @contact = contact
    @location = location
    @shared_at = shared_at
    @source = source.to_s
  end

  def perform
    return false if @contact.blank? || @location.blank?

    shared_at = normalized_shared_at

    @contact.with_lock do
      return false if newer_location_already_stored?(shared_at)

      @contact.update!(
        custom_attributes: merged_location_attributes(shared_at)
      )
    end

    true
  end

  private

  def normalized_shared_at
    return @shared_at.in_time_zone if @shared_at.respond_to?(:in_time_zone)
    return Time.current if @shared_at.blank?

    if @shared_at.to_s.match?(/\A\d+(?:\.\d+)?\z/)
      timestamp = Float(@shared_at)
      timestamp /= 1000.0 if timestamp > 10_000_000_000
      return Time.zone.at(timestamp)
    end

    Time.zone.parse(@shared_at.to_s)
  rescue ArgumentError, TypeError
    Time.current
  end

  def newer_location_already_stored?(shared_at)
    stored_at = @contact.custom_attributes&.[]("last_shared_location_at")
    return false if stored_at.blank?

    Time.zone.parse(stored_at.to_s) > shared_at
  rescue ArgumentError, TypeError
    false
  end

  def merged_location_attributes(shared_at)
    latitude = @location.coordinates_lat
    longitude = @location.coordinates_long

    location_url =
      @location.external_url.presence ||
      "https://maps.google.com/?q=#{latitude},#{longitude}"

    (@contact.custom_attributes || {}).merge(
      "location_url" => location_url,
      "last_shared_latitude" => latitude,
      "last_shared_longitude" => longitude,
      "last_shared_location_at" => shared_at.iso8601(3),
      "last_shared_location_source" => @source
    )
  end
end
