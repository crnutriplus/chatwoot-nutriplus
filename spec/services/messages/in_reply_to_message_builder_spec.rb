require 'rails_helper'

describe Messages::InReplyToMessageBuilder do
  let(:conversation) { create(:conversation) }
  let(:reply) do
    build(
      :message,
      message_type: :outgoing,
      account: conversation.account,
      inbox: conversation.inbox,
      conversation: conversation,
      content_attributes: {}
    )
  end

  it 'resolves an internal message id to the canonical external source id' do
    original_message = create(
      :message,
      account: conversation.account,
      inbox: conversation.inbox,
      conversation: conversation,
      source_id: 'mid.original'
    )

    described_class.new(
      message: reply,
      in_reply_to: original_message.id,
      in_reply_to_external_id: nil
    ).perform

    expect(reply.content_attributes[:in_reply_to]).to eq(original_message.id)
    expect(reply.content_attributes[:in_reply_to_external_id]).to eq('mid.original')
  end

  it 'resolves an external source id only inside the same conversation' do
    original_message = create(
      :message,
      account: conversation.account,
      inbox: conversation.inbox,
      conversation: conversation,
      source_id: 'mid.original'
    )

    described_class.new(
      message: reply,
      in_reply_to: nil,
      in_reply_to_external_id: original_message.source_id
    ).perform

    expect(reply.content_attributes[:in_reply_to]).to eq(original_message.id)
    expect(reply.content_attributes[:in_reply_to_external_id]).to eq('mid.original')
  end

  it 'rejects an internal message id from another conversation' do
    foreign_message = create(:message, source_id: 'mid.foreign')

    described_class.new(
      message: reply,
      in_reply_to: foreign_message.id,
      in_reply_to_external_id: nil
    ).perform

    expect(reply.content_attributes[:in_reply_to]).to be_nil
    expect(reply.content_attributes[:in_reply_to_external_id]).to be_nil
  end

  it 'rejects an external source id from another conversation' do
    foreign_message = create(:message, source_id: 'mid.foreign')

    described_class.new(
      message: reply,
      in_reply_to: nil,
      in_reply_to_external_id: foreign_message.source_id
    ).perform

    expect(reply.content_attributes[:in_reply_to]).to be_nil
    expect(reply.content_attributes[:in_reply_to_external_id]).to be_nil
  end
end
