require 'rails_helper'

describe Whatsapp::Providers::WhatsappCloudService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'whatsapp_cloud',
      validate_provider_config: false,
      sync_templates: false
    )
  end
  let(:conversation) { create(:conversation, inbox: whatsapp_channel.inbox) }
  let(:response_headers) { { 'Content-Type' => 'application/json' } }
  let(:whatsapp_response) { { messages: [{ id: 'wamid.reply' }] } }

  it 'sends context.message_id with the canonical WhatsApp message id for text replies' do
    original_message = create(
      :message,
      conversation: conversation,
      inbox: whatsapp_channel.inbox,
      message_type: :incoming,
      source_id: 'wamid.original'
    )
    reply = create(
      :message,
      conversation: conversation,
      inbox: whatsapp_channel.inbox,
      message_type: :outgoing,
      content: 'reply',
      content_attributes: { in_reply_to: original_message.id }
    )

    stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages')
      .with(
        body: hash_including(
          'messaging_product' => 'whatsapp',
          'context' => { 'message_id' => 'wamid.original' },
          'type' => 'text'
        )
      )
      .to_return(status: 200, body: whatsapp_response.to_json, headers: response_headers)

    expect(service.send_message('+123456789', reply)).to eq('wamid.reply')
    expect(reply.reload.content_attributes['in_reply_to_external_id']).to eq('wamid.original')
  end

  it 'sends context.message_id for media replies' do
    original_message = create(
      :message,
      conversation: conversation,
      inbox: whatsapp_channel.inbox,
      message_type: :incoming,
      source_id: 'wamid.original'
    )
    reply = create(
      :message,
      conversation: conversation,
      inbox: whatsapp_channel.inbox,
      message_type: :outgoing,
      content: 'image reply',
      content_attributes: { in_reply_to: original_message.id }
    )
    attachment = reply.attachments.new(account_id: reply.account_id, file_type: :image)
    attachment.file.attach(
      io: Rails.root.join('spec/assets/avatar.png').open,
      filename: 'avatar.png',
      content_type: 'image/png'
    )

    stub_request(:post, 'https://graph.facebook.com/v24.0/123456789/messages')
      .with(
        body: hash_including(
          'messaging_product' => 'whatsapp',
          'context' => { 'message_id' => 'wamid.original' },
          'type' => 'image'
        )
      )
      .to_return(status: 200, body: whatsapp_response.to_json, headers: response_headers)

    expect(service.send_message('+123456789', reply)).to eq('wamid.reply')
  end
end
