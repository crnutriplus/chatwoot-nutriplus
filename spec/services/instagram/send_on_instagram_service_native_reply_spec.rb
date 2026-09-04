require 'rails_helper'

describe Instagram::SendOnInstagramService do
  let!(:account) { create(:account) }
  let!(:instagram_channel) { create(:channel_instagram, account: account, instagram_id: 'instagram-123') }
  let!(:instagram_inbox) { create(:inbox, channel: instagram_channel, account: account, greeting_enabled: false) }
  let!(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: instagram_inbox) }
  let(:conversation) { create(:conversation, contact: contact, inbox: instagram_inbox, contact_inbox: contact_inbox) }

  it 'adds the canonical Meta mid when replying to a specific message' do
    original_message = create(
      :message,
      message_type: :incoming,
      inbox: instagram_inbox,
      account: account,
      conversation: conversation,
      source_id: 'mid.original'
    )
    reply = create(
      :message,
      message_type: :outgoing,
      inbox: instagram_inbox,
      account: account,
      conversation: conversation,
      content_attributes: { 'in_reply_to' => original_message.id }
    )
    service = described_class.new(message: reply)
    allow(service).to receive(:send_message)

    service.perform

    expect(reply.reload.content_attributes['in_reply_to_external_id']).to eq('mid.original')
    expect(service).to have_received(:send_message).with(
      hash_including(
        recipient: { id: contact_inbox.source_id },
        message: { text: reply.content },
        reply_to: { mid: 'mid.original' }
      )
    )
  end

  it 'adds the canonical Meta mid to attachment replies' do
    original_message = create(
      :message,
      message_type: :incoming,
      inbox: instagram_inbox,
      account: account,
      conversation: conversation,
      source_id: 'mid.original'
    )
    reply = build(
      :message,
      content: nil,
      message_type: :outgoing,
      inbox: instagram_inbox,
      account: account,
      conversation: conversation,
      content_attributes: { 'in_reply_to' => original_message.id }
    )
    attachment = reply.attachments.new(account_id: account.id, file_type: :image)
    attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
    reply.save!
    allow(attachment).to receive(:download_url).and_return('https://example.test/avatar.png')
    service = described_class.new(message: reply)
    allow(service).to receive(:send_message)

    service.perform

    expect(service).to have_received(:send_message).with(
      hash_including(
        message: hash_including(:attachment),
        reply_to: { mid: 'mid.original' }
      )
    )
  end
end
