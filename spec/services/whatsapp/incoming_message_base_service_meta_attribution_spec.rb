require 'rails_helper'

describe Whatsapp::IncomingMessageBaseService do
  let(:record_class) do
    Class.new do
      attr_accessor :custom_attributes

      def initialize(attributes = {})
        @custom_attributes = attributes
      end

      def update!(custom_attributes:)
        @custom_attributes = custom_attributes
      end
    end
  end

  let(:message) do
    {
      referral: {
        source_url: 'https://fb.me/example',
        source_id: 'WA-AD-500',
        source_type: 'ad',
        body: 'DO-NOT-SEND',
        headline: 'DO-NOT-SEND',
        ctwa_clid: 'CTWA-CLICK-500',
        welcome_message: { text: 'DO-NOT-SEND' }
      }
    }.with_indifferent_access
  end

  let(:contact) { record_class.new }
  let(:conversation) { record_class.new }
  let(:service) { described_class.allocate }

  before do
    service.instance_variable_set(:@contact, contact)
    service.instance_variable_set(:@conversation, conversation)
    allow(service).to receive(:outgoing_echo).and_return(false)
  end

  it 'exposes only approved fields to NutriPlus' do
    referral = Nutriplus::MetaReferralAttributionService.sanitize(message[:referral], channel: :whatsapp)

    expect(referral).to eq(
      'source_id' => 'WA-AD-500',
      'source_type' => 'ad',
      'ctwa_clid' => 'CTWA-CLICK-500'
    )

    expect(referral).not_to have_key('body')
    expect(referral).not_to have_key('headline')
    expect(referral).not_to have_key('source_url')
    expect(referral).not_to have_key('welcome_message')
  end

  it 'preserves the full Chatwoot referral' do
    referral = service.send(:message_content_attributes, message)[:referral]

    expect(referral).to include(
      'source_id' => 'WA-AD-500',
      'body' => 'DO-NOT-SEND',
      'headline' => 'DO-NOT-SEND',
      'ctwa_clid' => 'CTWA-CLICK-500'
    )
  end

  it 'persists Click-to-WhatsApp attribution' do
    service.send(:persist_meta_referral_attribution, message)

    expect(contact.custom_attributes['first_touch_ad_id'])
      .to eq('WA-AD-500')

    expect(conversation.custom_attributes).to include(
      'meta_ad_id' => 'WA-AD-500',
      'meta_referral_source' => 'ADS',
      'meta_ctwa_clid' => 'CTWA-CLICK-500'
    )
  end
end
