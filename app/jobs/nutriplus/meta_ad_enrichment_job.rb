class Nutriplus::MetaAdEnrichmentJob < ApplicationJob
  queue_as :default

  retry_on Nutriplus::MetaAdEnrichmentService::TransientError,
           wait: :polynomially_longer,
           attempts: 4

  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, ad_id)
    conversation = Conversation.find(conversation_id)

    Nutriplus::MetaAdEnrichmentService.new(
      conversation: conversation,
      ad_id: ad_id
    ).perform
  end
end
