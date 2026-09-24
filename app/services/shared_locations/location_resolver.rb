class SharedLocations::LocationResolver
  def initialize(content:, account_id: nil)
    @content = content.to_s
    @account_id = account_id
  end

  def perform
    waze_share_drive_location ||
      coordinate_location
  rescue StandardError
    nil
  end

  private

  def waze_share_drive_location
    result = SharedLocations::WazeShareDriveResolver.new(
      content: @content,
      account_id: @account_id
    ).perform

    return if result.blank?

    result.merge(resolution_provider: 'waze')
  end

  def coordinate_location
    SharedLocations::CoordinateResolver.new(
      content: @content
    ).perform
  end
end
