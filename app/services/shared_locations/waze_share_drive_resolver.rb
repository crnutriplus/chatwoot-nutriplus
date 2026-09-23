class SharedLocations::WazeShareDriveResolver
  GEO_ENVS = %w[row il na].freeze
  REQUEST_TIMEOUT = 5
  TOKEN_PATTERN = /\A[A-Za-z0-9_-]{1,256}\z/

  def initialize(content:, account_id: nil)
    @content = content.to_s
    @account_id = account_id
  end

  def perform
    params = share_drive_params
    return if params.blank?

    response = fetch_share_drive(params[:token], params[:env])
    return if response.blank?

    destination_from_response(response) || destination_from_route(response)
  rescue StandardError => e
    log_exception(e)
    nil
  end

  private

  def share_drive_params
    urls.each do |uri|
      query = begin
        URI.decode_www_form(uri.query.to_s).to_h
      rescue ArgumentError
        next
      end

      token =
        if query["a"] == "share_drive"
          query["sd"]
        elsif uri.path.to_s.include?("/live-map/meeting")
          query["token"]
        end

      next if token.blank?
      next unless token.to_s.match?(TOKEN_PATTERN)

      env = normalize_env(query["env"])
      next if env.blank?

      return { token: token, env: env }
    end

    nil
  end

  def urls
    CGI.unescapeHTML(@content).scan(%r{https?://[^\s<>"']+}).filter_map do |candidate|
      uri = URI.parse(candidate.gsub(/[)\],.!?;:]+\z/, ""))
      next unless waze_host?(uri.host)

      uri
    rescue URI::InvalidURIError
      nil
    end
  end

  def waze_host?(host)
    normalized = host.to_s.downcase
    normalized == "waze.com" || normalized.end_with?(".waze.com")
  end

  def normalize_env(env)
    value = env.to_s.downcase
    value = "na" if %w[usa us].include?(value)

    GEO_ENVS.include?(value) ? value : nil
  end

  def fetch_share_drive(token, env)
    response = HTTParty.get(
      "https://www.waze.com/#{env}-rtserver/web/PickUpGetDriverInfo",
      query: {
        token: token,
        getUserInfo: true,
        _: (Time.current.to_f * 1000).to_i
      },
      headers: {
        "Accept" => "application/json, text/plain, */*",
        "User-Agent" => "Mozilla/5.0",
        "Referer" => "https://www.waze.com/live-map/meeting"
      },
      timeout: REQUEST_TIMEOUT
    )

    return log_http_error(response) unless response.success?

    parsed = JSON.parse(response.body).with_indifferent_access
    parsed[:status] == "ok" ? parsed : nil
  end

  def destination_from_response(response)
    location = response[:calculatedLocation]
    return if location.blank?
    return unless valid_coordinates?(location[:latitude], location[:longitude])

    build_result(
      lat: location[:latitude],
      long: location[:longitude],
      name: location[:name],
      city: location[:city],
      source: "calculated_location"
    )
  end

  def destination_from_route(response)
    route = response[:route]
    return unless route.is_a?(Array) && route.length >= 2

    long = route[-2]
    lat = route[-1]
    return unless valid_coordinates?(lat, long)

    build_result(lat: lat, long: long, name: nil, city: nil, source: "route_endpoint")
  end

  def build_result(lat:, long:, name:, city:, source:)
    latitude = Float(lat)
    longitude = Float(long)

    {
      latitude: latitude,
      longitude: longitude,
      name: name.presence,
      city: city.presence,
      title: name.presence || city.presence || "Waze destination",
      map_url: "https://maps.google.com/?q=#{latitude},#{longitude}",
      resolution_source: source
    }
  end

  def valid_coordinates?(lat, long)
    Float(lat).between?(-90, 90) && Float(long).between?(-180, 180)
  rescue ArgumentError, TypeError
    false
  end

  def log_http_error(response)
    Rails.logger.warn("[WazeShareDriveFetchError]: account_id #{@account_id} status #{response.code}")
    nil
  end

  def log_exception(error)
    Rails.logger.warn(
      "[WazeShareDriveFetchError]: account_id #{@account_id} #{error.class}"
    )
  end
end
