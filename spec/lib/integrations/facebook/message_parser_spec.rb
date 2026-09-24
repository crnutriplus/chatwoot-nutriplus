require 'rails_helper'

describe Integrations::Facebook::MessageParser do
  describe '#sent_from_chatwoot_app?' do
    before do
      allow(GlobalConfigService).to receive(:load).with('FB_APP_ID', '').and_return('1134227931892276')
    end

    it 'returns true when the echo app_id is a numeric value matching FB_APP_ID' do
      response = described_class.new({ messaging: { message: { is_echo: true, app_id: 1_134_227_931_892_276 } } }.to_json)
      expect(response.sent_from_chatwoot_app?).to be true
    end

    it 'returns true when the echo app_id is a string matching FB_APP_ID' do
      response = described_class.new({ messaging: { message: { is_echo: true, app_id: '1134227931892276' } } }.to_json)
      expect(response.sent_from_chatwoot_app?).to be true
    end

    it 'returns false when the echo app_id does not match FB_APP_ID' do
      response = described_class.new({ messaging: { message: { is_echo: true, app_id: 999_999_999_999_999 } } }.to_json)
      expect(response.sent_from_chatwoot_app?).to be false
    end

    it 'returns false when app_id is absent from the payload' do
      response = described_class.new({ messaging: { message: { is_echo: true } } }.to_json)
      expect(response.sent_from_chatwoot_app?).to be false
    end
  end

  describe '#echo?' do
    it 'returns true when message.is_echo is true' do
      response = described_class.new({ messaging: { message: { is_echo: true } } }.to_json)
      expect(response).to be_echo
    end

    it 'returns falsey when message.is_echo is absent' do
      response = described_class.new({ messaging: { message: {} } }.to_json)
      expect(response).not_to be_echo
    end
  end

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
