require 'rails_helper'

describe Messages::NewMessageNotificationService do
  context 'when message is not notifiable' do
    it 'will not create any notifications for activity messages' do
      message = build(:message, message_type: :activity)
      expect(NotificationBuilder).not_to receive(:new)
      described_class.new(message: message).perform
    end

    it 'will not create any notifications for private messages' do
      message = build(:message, message_type: :outgoing, private: true)
      expect(NotificationBuilder).not_to receive(:new)
      described_class.new(message: message).perform
    end
  end

  context 'when message is notifiable' do
    let(:account) { create(:account) }
    let(:assignee) { create(:user, account: account) }
    let(:participating_agent_1) { create(:user, account: account) }
    let(:participating_agent_2) { create(:user, account: account) }
    let(:inbox_only_agent) { create(:user, account: account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: assignee) }

    before do
      create(:inbox_member, inbox: inbox, user: participating_agent_1)
      create(:inbox_member, inbox: inbox, user: participating_agent_2)
      create(:inbox_member, inbox: inbox, user: assignee)
      create(:inbox_member, inbox: inbox, user: inbox_only_agent)
      create(:conversation_participant, conversation: conversation, user: participating_agent_1)
      create(:conversation_participant, conversation: conversation, user: participating_agent_2)
      create(:conversation_participant, conversation: conversation, user: assignee)
    end

    context 'when message is created by a participant' do
      let(:message) { create(:message, conversation: conversation, account: account, sender: participating_agent_1) }

      before do
        described_class.new(message: message).perform
      end

      it 'creates notifications for other participating users' do
        expect(participating_agent_2.notifications.where(notification_type: 'participating_conversation_new_message', account: account,
                                                         primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'creates notifications for assignee' do
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message', account: account,
                                            primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'will not create notifications for the user who created the message' do
        expect(participating_agent_1.notifications.where(notification_type: 'participating_conversation_new_message',
                                                         account: account, primary_actor: message.conversation,
                                                         secondary_actor: message)).not_to exist
      end
    end

    context 'when message is created by a contact' do
      let(:message) { create(:message, conversation: conversation, account: account, message_type: :incoming) }

      before do
        described_class.new(message: message).perform
      end

      it 'creates notifications for assignee' do
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message', account: account,
                                            primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'creates notifications for all participating users' do
        expect(participating_agent_1.notifications.where(notification_type: 'participating_conversation_new_message',
                                                         account: account, primary_actor: message.conversation,
                                                         secondary_actor: message)).to exist
        expect(participating_agent_2.notifications.where(notification_type: 'participating_conversation_new_message',
                                                         account: account, primary_actor: message.conversation,
                                                         secondary_actor: message)).to exist
      end

      it 'creates a notification for an inbox member who is not assigned or participating' do
        expect(inbox_only_agent.notifications.where(notification_type: 'participating_conversation_new_message',
                                                    account: account, primary_actor: message.conversation,
                                                    secondary_actor: message)).to exist
      end
    end

    context 'when an incoming message is created on an unassigned conversation' do
      let(:message) { create(:message, conversation: conversation, account: account, message_type: :incoming) }

      before do
        conversation.update!(assignee: nil)
        described_class.new(message: message).perform
      end

      it 'creates notifications for every inbox member' do
        [assignee, participating_agent_1, participating_agent_2, inbox_only_agent].each do |agent|
          expect(agent.notifications.where(account: account, primary_actor: message.conversation,
                                           secondary_actor: message)).to exist
        end
      end
    end

    context 'when multiple notification conditions are met' do
      let(:message) { create(:message, conversation: conversation, account: account, message_type: :incoming) }

      before do
        described_class.new(message: message).perform
      end

      it 'will not create participating notifications for the assignee if assignee notification was sent' do
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message',
                                            account: account, primary_actor: message.conversation,
                                            secondary_actor: message)).to exist
        expect(assignee.notifications.where(notification_type: 'participating_conversation_new_message',
                                            account: account, primary_actor: message.conversation,
                                            secondary_actor: message)).not_to exist
      end

      it 'creates only one notification per agent for the same message' do
        expect(assignee.notifications.where(account: account, primary_actor: message.conversation,
                                            secondary_actor: message).count).to eq(1)
        expect(participating_agent_1.notifications.where(account: account, primary_actor: message.conversation,
                                                         secondary_actor: message).count).to eq(1)
      end
    end

    context 'when message is created by assignee' do
      let(:message) { create(:message, conversation: conversation, account: account, sender: assignee, message_type: :outgoing) }

      before do
        described_class.new(message: message).perform
      end

      it 'will not create notifications for the user who created the message' do
        expect(assignee.notifications.where(notification_type: 'participating_conversation_new_message',
                                            account: account, primary_actor: message.conversation,
                                            secondary_actor: message)).not_to exist
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message',
                                            account: account, primary_actor: message.conversation,
                                            secondary_actor: message)).not_to exist
      end

      it 'does not notify unrelated inbox members for outgoing messages' do
        expect(inbox_only_agent.notifications.where(account: account, primary_actor: message.conversation,
                                                    secondary_actor: message)).not_to exist
      end
    end
  end
end
