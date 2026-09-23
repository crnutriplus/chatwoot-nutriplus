require 'rails_helper'

describe Integrations::Facebook::MessageParser do
  describe '#referral' do
    it 'keeps only the approved Meta attribution fields' do
      payload = {
        messaging: {
          sender: { id: 'PSID-1' },
          recipient: { id: 'PAGE-1' },
          message: { mid: 'mid-1', text: 'Hola' },
          referral: {
            ad_id: '123456789',
            source: 'ADS',
            type: 'OPEN_THREAD',
            ref: 'must-not-be-stored',
            ads_context_data: { ad_title: 'must-not-be-stored' },
            health_data: 'must-not-be-stored'
          }
        }
      }.to_json

      referral = described_class.new(payload).referral

      expect(referral).to eq(
        'ad_id' => '123456789',
        'source' => 'ADS',
        'type' => 'OPEN_THREAD'
      )
    end

    it 'returns an empty hash when referral is absent or invalid' do
      no_referral = {
        messaging: {
          sender: { id: 'PSID-1' },
          recipient: { id: 'PAGE-1' },
          message: { mid: 'mid-1', text: 'Hola' }
        }
      }.to_json

      invalid_referral = {
        messaging: {
          referral: 'not-a-hash'
        }
      }.to_json

      expect(described_class.new(no_referral).referral).to eq({})
      expect(described_class.new(invalid_referral).referral).to eq({})
    end
  end
end
