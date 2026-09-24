require 'rails_helper'

describe Messages::Instagram::BaseMessageBuilder do
  let(:record_class) do
    Class.new do
      attr_accessor :custom_attributes, :account_id, :inbox_id

      def initialize(attributes = {}, account_id: 1, inbox_id: 3)
        @custom_attributes = attributes
        @account_id = account_id
        @inbox_id = inbox_id
      end

      def update!(custom_attributes:)
        @custom_attributes = custom_attributes
      end
    end
  end

  let(:messaging) do
    {
      sender: { id: 'IGSID-CONTACT' },
      recipient: { id: 'IG-BUSINESS' },
      message: { mid: 'ig-mid-ad', text: 'Hola' },
      referral: {
        ad_id: 'IG-AD-123',
        source: 'ADS',
        type: 'OPEN_THREAD',
        ref: 'DO-NOT-STORE',
        health_data: 'DO-NOT-STORE'
      }
    }.with_indifferent_access
  end

  let(:inbox) { OpenStruct.new(account_id: 1, id: 3) }
  let(:contact) { record_class.new }
  let(:conversation) { record_class.new }
  let(:builder) { described_class.new(messaging, inbox) }

  before do
    allow(builder).to receive(:contact).and_return(contact)
    allow(builder).to receive(:conversation).and_return(conversation)
  end

  it 'keeps only approved attribution fields' do
    expect(builder.send(:meta_referral)).to eq(
      'ad_id' => 'IG-AD-123',
      'source' => 'ADS',
      'type' => 'OPEN_THREAD'
    )
  end

  it 'persists Instagram ads attribution' do
    builder.send(:persist_meta_referral)

    expect(contact.custom_attributes['first_touch_ad_id'])
      .to eq('IG-AD-123')

    expect(conversation.custom_attributes).to include(
      'meta_ad_id' => 'IG-AD-123',
      'meta_referral_source' => 'ADS'
    )
  end

  it 'does not attribute outgoing echoes' do
    echo_builder = described_class.new(
      messaging,
      inbox,
      outgoing_echo: true
    )

    allow(echo_builder).to receive(:contact).and_return(contact)
    allow(echo_builder).to receive(:conversation).and_return(conversation)

    echo_builder.send(:persist_meta_referral)

    expect(contact.custom_attributes).to be_empty
    expect(conversation.custom_attributes).to be_empty
  end
end
