require 'rails_helper'

describe Nutriplus::MetaAdEnrichmentService do
  let(:record_class) do
    Class.new do
      attr_accessor :custom_attributes, :id

      def initialize(attributes = {}, id: nil)
        @custom_attributes = attributes
        @id = id
      end

      def update!(custom_attributes:)
        @custom_attributes = custom_attributes
      end

      def reload
        self
      end
    end
  end

  let(:ad_id) { '52602950547742' }
  let(:conversation) { record_class.new({ 'meta_ad_id' => ad_id }, id: 145) }
  let(:endpoint) { "https://graph.facebook.com/v22.0/#{ad_id}" }
  let(:response_body) do
    {
      id: ad_id,
      name: 'Omega Teen',
      adset_id: '52602950332342',
      campaign_id: '52602934970542',
      adset: {
        id: '52602950332342',
        name: 'Niños'
      },
      campaign: {
        id: '52602934970542',
        name: 'Interacción GAM'
      },
      creative: {
        id: '1529933415553924',
        name: 'Ultimate Omega Teen',
        thumbnail_url: 'https://scontent.example.test/omega-teen.png'
      }
    }
  end

  def perform(access_token: 'ads-read-token')
    described_class.new(
      conversation: conversation,
      ad_id: ad_id,
      access_token: access_token,
      graph_version: 'v22.0'
    ).perform
  end

  it 'enriches the conversation with ad hierarchy and visual metadata' do
    stub_request(:get, endpoint)
      .with(
        query: { fields: described_class::GRAPH_FIELDS },
        headers: { 'Authorization' => 'Bearer ads-read-token' }
      )
      .to_return(
        status: 200,
        body: response_body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    result = perform

    expect(result).to include(
      enriched: true,
      ad_id: ad_id,
      adset_id: '52602950332342',
      campaign_id: '52602934970542',
      creative_id: '1529933415553924'
    )

    expect(conversation.custom_attributes).to include(
      'meta_ad_id' => ad_id,
      'meta_adset_id' => '52602950332342',
      'meta_campaign_id' => '52602934970542',
      'meta_ad_name' => 'Omega Teen',
      'meta_adset_name' => 'Niños',
      'meta_campaign_name' => 'Interacción GAM',
      'meta_creative_id' => '1529933415553924',
      'meta_creative_name' => 'Ultimate Omega Teen',
      'meta_ad_thumbnail_url' => 'https://scontent.example.test/omega-teen.png'
    )
  end

  it 'does not overwrite an existing attribution snapshot' do
    conversation.custom_attributes['meta_ad_name'] = 'Original Omega Teen'

    stub_request(:get, endpoint)
      .to_return(
        status: 200,
        body: response_body.merge(name: 'Renamed Omega Teen').to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    perform

    expect(conversation.custom_attributes['meta_ad_name']).to eq('Original Omega Teen')
    expect(conversation.custom_attributes['meta_adset_name']).to eq('Niños')
  end

  it 'does not query Meta when the conversation belongs to another ad' do
    conversation.custom_attributes['meta_ad_id'] = '11111111111111'

    expect(HTTParty).not_to receive(:get)

    expect(perform).to eq(enriched: false, reason: :stale_attribution)
  end

  it 'raises a transient error for retryable Meta responses' do
    stub_request(:get, endpoint).to_return(status: 503, body: '{}')

    expect { perform }.to raise_error(
      Nutriplus::MetaAdEnrichmentService::TransientError,
      /HTTP 503/
    )
  end

  it 'does not persist data when Meta returns a non-retryable error' do
    stub_request(:get, endpoint)
      .to_return(
        status: 400,
        body: { error: { code: 100, type: 'OAuthException', message: 'Unsupported get request' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    expect(perform).to eq(enriched: false, reason: :graph_error)
    expect(conversation.custom_attributes).to eq('meta_ad_id' => ad_id)
  end
end
