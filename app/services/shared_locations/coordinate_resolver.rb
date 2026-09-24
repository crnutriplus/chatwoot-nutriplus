class SharedLocations::CoordinateResolver
  URL_PATTERN = %r{https?://[^\s<>"']+}
  COORD_PAIR = /(-?\d{1,2}\.\d{4,})\s*,\s*(-?\d{1,3}\.\d{4,})/
  QUERY_KEYS = %w[q query ll sll center destination viewpoint daddr].freeze

  def initialize(content:)
    @content = CGI.unescapeHTML(content.to_s)
  end

  def perform
    geo_result ||
      url_result ||
      plain_coordinate_result
  rescue StandardError
    nil
  end

  private

  def geo_result
    match = @content.match(
      /(?:\A|\s)geo:(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)/i
    )
    return if match.blank?

    build_result(
      match[1],
      match[2],
      resolution_source: 'geo_uri'
    )
  end

  def url_result
    urls.each do |uri|
      result = coordinates_from_uri(uri)
      return result if result.present?
    end

    nil
  end

  def coordinates_from_uri(uri)
    coordinates_from_query(uri) ||
      coordinates_from_at_path(uri) ||
      coordinates_from_3d4d(uri) ||
      coordinates_from_2d3d(uri)
  end

  def coordinates_from_query(uri)
    query_pairs(uri).each do |key, value|
      next unless QUERY_KEYS.include?(key.to_s.downcase)

      pair = exact_coordinate_pair(value)
      next if pair.blank?

      return build_result(
        pair[0],
        pair[1],
        resolution_source: 'url_query'
      )
    end

    nil
  end

  def coordinates_from_at_path(uri)
    decoded = decoded_uri(uri)
    match = decoded.match(
      /@(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)/
    )
    return if match.blank?

    build_result(
      match[1],
      match[2],
      resolution_source: 'url_at'
    )
  end

  def coordinates_from_3d4d(uri)
    decoded = decoded_uri(uri)
    match = decoded.match(
      /!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)/
    )
    return if match.blank?

    build_result(
      match[1],
      match[2],
      resolution_source: 'url_3d4d'
    )
  end

  def coordinates_from_2d3d(uri)
    decoded = decoded_uri(uri)
    match = decoded.match(
      /!2d(-?\d{1,3}(?:\.\d+)?)!3d(-?\d{1,2}(?:\.\d+)?)/
    )
    return if match.blank?

    build_result(
      match[2],
      match[1],
      resolution_source: 'url_2d3d'
    )
  end

  def plain_coordinate_result
    text_without_urls = @content.gsub(URL_PATTERN, ' ')
    match = text_without_urls.match(COORD_PAIR)
    return if match.blank?

    build_result(
      match[1],
      match[2],
      resolution_source: 'plain_coordinates'
    )
  end

  def urls
    @content.scan(URL_PATTERN).filter_map do |candidate|
      URI.parse(candidate.gsub(/[)\],.!?;:]+\z/, ''))
    rescue URI::InvalidURIError
      nil
    end
  end

  def query_pairs(uri)
    URI.decode_www_form(uri.query.to_s)
  rescue ArgumentError
    []
  end

  def exact_coordinate_pair(value)
    decoded = CGI.unescape(value.to_s)
    match = decoded.match(
      /\A\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*\z/
    )
    return if match.blank?

    [match[1], match[2]]
  end

  def decoded_uri(uri)
    CGI.unescape(uri.to_s)
  end

  def build_result(lat, long, resolution_source:)
    latitude = Float(lat)
    longitude = Float(long)

    return unless valid_coordinates?(latitude, longitude)

    {
      latitude: latitude,
      longitude: longitude,
      name: nil,
      city: nil,
      title: 'Shared location',
      map_url: "https://maps.google.com/?q=#{latitude},#{longitude}",
      resolution_source: resolution_source,
      resolution_provider: 'coordinates'
    }
  rescue ArgumentError, TypeError
    nil
  end

  def valid_coordinates?(latitude, longitude)
    latitude.between?(-90, 90) &&
      longitude.between?(-180, 180) &&
      !(latitude.zero? && longitude.zero?)
  end
end
