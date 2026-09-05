require 'rails_helper'

RSpec.describe Instagram::Messenger::SendOnInstagramService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_instagram_fb_page, account: account, instagram_id: 'ig-business-id') }
  let(:inbox) { create(:inbox, channel: channel, account: account, greeting_enabled: false) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'ig-scoped-contact-id') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:success_response) do
    instance_double(
      HTTParty::Response,
      success?: true,
      parsed_response: { 'message_id' => 'mid.sent' },
      body: { message_id: 'mid.sent' }.to_json
    )
  end

  before do
    InstallationConfig.where(name: 'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT').first_or_create(value: false)
    allow(Facebook::Messenger::Configuration::AppSecretProofCalculator).to receive(:call).and_return(nil)
  end

  it 'adds top-level reply_to only on the graph.facebook.com Instagram Messenger route' do
    message = create(
      :message,
      message_type: :outgoing,
      content: 'Native reply canary',
      account: account,
      inbox: inbox,
      conversation: conversation,
      content_attributes: { 'in_reply_to_external_id' => 'mid.original' }
    )

    expect(HTTParty).to receive(:post) do |url, options|
      expect(url).to eq('https://graph.facebook.com/v11.0/me/messages')
      expect(options.dig(:body, :recipient, :id)).to eq('ig-scoped-contact-id')
      expect(options.dig(:body, :message, :text)).to eq('Native reply canary')
      expect(options.dig(:body, :reply_to, :mid)).to eq('mid.original')
      success_response
    end

    described_class.new(message: message).perform

    expect(message.reload.source_id).to eq('mid.sent')
  end

  it 'keeps ordinary Instagram Messenger sends unchanged when there is no reply target' do
    message = create(
      :message,
      message_type: :outgoing,
      content: 'Normal send',
      account: account,
      inbox: inbox,
      conversation: conversation
    )

    expect(HTTParty).to receive(:post) do |url, options|
      expect(url).to eq('https://graph.facebook.com/v11.0/me/messages')
      expect(options[:body]).not_to have_key(:reply_to)
      success_response
    end

    described_class.new(message: message).perform

    expect(message.reload.source_id).to eq('mid.sent')
  end
end
