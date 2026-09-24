module Messages::Instagram::NutriplusExtensions
  private

  def process_waze_shared_location
    return if @message.blank?

    SharedLocations::WazeMessageService.new(
      message: @message,
      contact: contact,
      content: message_content,
      shared_at: @messaging[:timestamp]
    ).perform
  end

  def meta_referral
    Nutriplus::MetaReferralAttributionService.sanitize(
      @messaging[:referral],
      channel: :instagram
    )
  end

  def persist_meta_referral
    return if @outgoing_echo

    Nutriplus::MetaReferralAttributionService.capture(
      conversation: conversation,
      contact: contact,
      referral: @messaging[:referral],
      channel: :instagram
    )
  end
end
