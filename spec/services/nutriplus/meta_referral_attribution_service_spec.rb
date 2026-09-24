require 'rails_helper'

describe Nutriplus::MetaReferralAttributionService do
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

  let(:contact) { record_class.new }
  let(:conversation) { record_class.new }

  def perform(referral)
    described_class.new(
      conversation: conversation,
      contact: contact,
      referral: referral
    ).perform
  end

  it 'persists Messenger or Instagram ads attribution' do
    result = perform(
      'source' => 'ADS',
      'ad_id' => 'META-AD-100',
      'type' => 'OPEN_THREAD'
    )

    expect(result).to eq(attributed: true, ad_id: 'META-AD-100')
    expect(contact.custom_attributes['first_touch_ad_id']).to eq('META-AD-100')
    expect(conversation.custom_attributes).to include(
      'meta_ad_id' => 'META-AD-100',
      'meta_referral_source' => 'ADS'
    )
  end

  it 'persists Click-to-WhatsApp attribution' do
    result = perform(
      'source_type' => 'ad',
      'source_id' => 'WA-AD-200',
      'ctwa_clid' => 'CTWA-CLICK-200'
    )

    expect(result).to eq(
      attributed: true,
      ad_id: 'WA-AD-200',
      ctwa_clid: 'CTWA-CLICK-200'
    )

    expect(contact.custom_attributes['first_touch_ad_id']).to eq('WA-AD-200')
    expect(conversation.custom_attributes).to include(
      'meta_ad_id' => 'WA-AD-200',
      'meta_referral_source' => 'ADS',
      'meta_ctwa_clid' => 'CTWA-CLICK-200'
    )
  end

  it 'can add ctwa_clid later only when it belongs to the same ad' do
    conversation.custom_attributes = {
      'meta_ad_id' => 'WA-AD-200',
      'meta_referral_source' => 'ADS'
    }

    perform(
      'source_type' => 'ad',
      'source_id' => 'WA-AD-200',
      'ctwa_clid' => 'CTWA-CLICK-200'
    )

    expect(conversation.custom_attributes['meta_ctwa_clid'])
      .to eq('CTWA-CLICK-200')
  end

  it 'does not mix attribution from different ads' do
    contact.custom_attributes = {
      'first_touch_ad_id' => 'OLD-AD'
    }

    conversation.custom_attributes = {
      'meta_ad_id' => 'OLD-AD',
      'meta_referral_source' => 'ADS',
      'meta_ctwa_clid' => 'OLD-CLICK'
    }

    perform(
      'source_type' => 'ad',
      'source_id' => 'NEW-AD',
      'ctwa_clid' => 'NEW-CLICK'
    )

    expect(contact.custom_attributes['first_touch_ad_id']).to eq('OLD-AD')
    expect(conversation.custom_attributes['meta_ad_id']).to eq('OLD-AD')
    expect(conversation.custom_attributes['meta_ctwa_clid']).to eq('OLD-CLICK')
  end

  it 'does not set contact first-touch when conversation belongs to another ad' do
    conversation.custom_attributes = {
      'meta_ad_id' => 'OLD-AD',
      'meta_referral_source' => 'ADS'
    }

    result = perform(
      'source_type' => 'ad',
      'source_id' => 'NEW-AD',
      'ctwa_clid' => 'NEW-CLICK'
    )

    expect(result).to eq(attributed: false)
    expect(contact.custom_attributes).to be_empty
    expect(conversation.custom_attributes['meta_ad_id']).to eq('OLD-AD')
    expect(conversation.custom_attributes['meta_ctwa_clid']).to be_nil
  end

  it 'rejects non-ad WhatsApp referrals' do
    result = perform(
      'source_type' => 'post',
      'source_id' => 'POST-1',
      'ctwa_clid' => 'CLICK-1'
    )

    expect(result).to eq(attributed: false)
    expect(contact.custom_attributes).to be_empty
    expect(conversation.custom_attributes).to be_empty
  end

  it 'rejects incomplete Meta ads referrals' do
    result = perform('source' => 'ADS')

    expect(result).to eq(attributed: false)
    expect(contact.custom_attributes).to be_empty
    expect(conversation.custom_attributes).to be_empty
  end
end
