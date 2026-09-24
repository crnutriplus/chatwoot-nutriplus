require 'rails_helper'

describe Nutriplus::MetaAdEnrichmentJob do
  it 'delegates enrichment for the requested conversation and ad' do
    conversation = instance_double(Conversation)
    service = instance_double(Nutriplus::MetaAdEnrichmentService, perform: { enriched: true })

    allow(Conversation).to receive(:find).with(145).and_return(conversation)

    expect(Nutriplus::MetaAdEnrichmentService).to receive(:new).with(
      conversation: conversation,
      ad_id: '52602950547742'
    ).and_return(service)

    described_class.perform_now(145, '52602950547742')

    expect(service).to have_received(:perform)
  end
end
