require 'rails_helper'

describe Facebook::SendOnFacebookService do
  let(:account) { create(:account) }
  let(:bot) { class_double(Facebook::Messenger::Bot).as_stubbed_const }
  let(:facebook_channel) { create(:channel_facebook_page, account: account) }
  let(:facebook_inbox) { create(:inbox, channel: facebook_channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: facebook_inbox) }
  let(:conversation) { create(:conversation, contact: contact, inbox: facebook_inbox, contact_inbox: contact_inbox) }

  before do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(bot).to receive(:deliver).and_return({ recipient_id: '123', message_id: 'mid.reply' }.to_json)
    GlobalConfig.clear_cache
  end

  it 'adds the canonical Meta mid when replying to a specific message' do
    original_message = create(
      :message,
      message_type: :incoming,
      inbox: facebook_inbox,
      account: account,
      conversation: conversation,
      source_id: 'mid.original'
    )
    reply = create(
      :message,
      message_type: :outgoing,
      inbox: facebook_inbox,
      account: account,
      conversation: conversation,
      content_attributes: { 'in_reply_to' => original_message.id }
    )

    described_class.new(message: reply).perform

    expect(reply.reload.content_attributes['in_reply_to_external_id']).to eq('mid.original')
    expect(bot).to have_received(:deliver).with(
      hash_including(
        recipient: { id: contact_inbox.source_id },
        message: { text: reply.content },
        reply_to: { mid: 'mid.original' }
      ),
      { page_id: facebook_channel.page_id }
    )
  end

  it 'adds the canonical Meta mid to attachment replies' do
    original_message = create(
      :message,
      message_type: :incoming,
      inbox: facebook_inbox,
      account: account,
      conversation: conversation,
      source_id: 'mid.original'
    )
    reply = build(
      :message,
      content: nil,
      message_type: :outgoing,
      inbox: facebook_inbox,
      account: account,
      conversation: conversation,
      content_attributes: { 'in_reply_to' => original_message.id }
    )
    attachment = reply.attachments.new(account_id: account.id, file_type: :image)
    attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
    reply.save!
    allow(attachment).to receive(:download_url).and_return('https://example.test/avatar.png')

    described_class.new(message: reply).perform

    expect(bot).to have_received(:deliver).with(
      hash_including(
        message: hash_including(:attachment),
        reply_to: { mid: 'mid.original' }
      ),
      { page_id: facebook_channel.page_id }
    )
  end
end
