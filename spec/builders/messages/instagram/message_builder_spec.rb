require 'rails_helper'

describe Messages::Instagram::MessageBuilder do
  subject(:instagram_direct_message_builder) { described_class }

  before do
    stub_request(:post, /graph\.instagram\.com/)
    stub_request(:get, 'https://www.example.com/test.jpeg')
      .to_return(status: 200, body: '', headers: {})
  end

  let!(:account) { create(:account) }
  let!(:instagram_channel) { create(:channel_instagram, account: account, instagram_id: 'chatwoot-app-user-id-1') }
  let!(:instagram_inbox) { create(:inbox, channel: instagram_channel, account: account, greeting_enabled: false) }
  let!(:dm_params) { build(:instagram_message_create_event).with_indifferent_access }
  let!(:story_mention_params) { build(:instagram_story_mention_event).with_indifferent_access }
  let!(:shared_reel_params) { build(:instagram_shared_reel_event).with_indifferent_access }
  let!(:instagram_story_reply_event) { build(:instagram_story_reply_event).with_indifferent_access }
  let!(:instagram_message_reply_event) { build(:instagram_message_reply_event).with_indifferent_access }

  def location_template_messaging(message_id, timestamp: nil)
    messaging = dm_params[:entry][0]['messaging'][0]
    messaging['timestamp'] = timestamp if timestamp
    messaging['message']['mid'] = message_id
    messaging['message'].delete('text')
    messaging['message']['attachments'] = [location_template_attachment]
    messaging
  end

  def location_template_attachment
    { 'type' => 'template', 'payload' => { 'generic' => { 'elements' => [] } } }
  end

  def stub_location_graph(message_id, media_url:, title: 'Live location')
    stub_request(:get, %r{https://graph\.instagram\.com/.*/#{Regexp.escape(message_id)}\?.*})
      .to_return(
        status: 200,
        body: location_graph_body(media_url, title),
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def location_graph_body(media_url, title)
    {
      attachments: {
        data: [{ generic_template: { title: title, media_url: media_url } }]
      }
    }.to_json
  end

  describe '#perform' do
    before do
      instagram_channel.update(access_token: 'valid_instagram_token')

      stub_request(:get, %r{https://graph\.instagram\.com/.*?/Sender-id-.*?\?.*})
        .to_return(
          status: 200,
          body: proc { |request|
            sender_id = request.uri.path.split('/').last.split('?').first
            {
              name: 'Jane',
              username: 'some_user_name',
              profile_pic: 'https://chatwoot-assets.local/sample.png',
              id: sender_id,
              follower_count: 100,
              is_user_follow_business: true,
              is_business_follow_user: true,
              is_verified_user: false
            }.to_json
          },
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates contact and message for the instagram direct inbox' do
      messaging = dm_params[:entry][0]['messaging'][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      described_class.new(messaging, instagram_inbox).perform

      instagram_inbox.reload

      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1

      message = instagram_inbox.messages.first
      expect(message.content).to eq('This is the first message from the customer')
    end

    it 'passes incoming Waze text to the shared location service' do
      messaging = dm_params[:entry][0]['messaging'][0]
      waze_text = 'Sigue mi viaje en Waze: https://www.waze.com/ul?a=share_drive&sd=Valid_Token-123&env=row'
      messaging['message']['text'] = waze_text
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      waze_service = instance_double(SharedLocations::WazeMessageService)

      allow(waze_service).to receive(:perform)
      allow(SharedLocations::WazeMessageService).to receive(:new).and_return(waze_service)

      described_class.new(messaging, instagram_inbox).perform

      message = instagram_inbox.reload.messages.find_by!(source_id: messaging['message']['mid'])

      expect(SharedLocations::WazeMessageService).to have_received(:new).with(
        message: message,
        contact: contact,
        content: waze_text,
        shared_at: messaging['timestamp']
      )
      expect(waze_service).to have_received(:perform).once
    end

    it 'discard echo message already sent by chatwoot' do
      messaging = dm_params[:entry][0]['messaging'][0]
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id, contact_id: contact.id)
      create(:message, account_id: account.id, inbox_id: instagram_inbox.id, conversation_id: conversation.id, message_type: 'outgoing',
                       source_id: 'message-id-1')

      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1

      messaging[:message][:mid] = 'message-id-1' # Set same source_id as the existing message
      described_class.new(messaging, instagram_inbox, outgoing_echo: true).perform

      instagram_inbox.reload

      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1
    end

    it 'discards duplicate messages from webhook events with the same message_id' do
      messaging = dm_params[:entry][0]['messaging'][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      described_class.new(messaging, instagram_inbox).perform

      initial_message_count = instagram_inbox.messages.count
      expect(initial_message_count).to be 1

      described_class.new(messaging, instagram_inbox).perform

      expect(instagram_inbox.messages.count).to eq initial_message_count
    end

    it 'creates message for shared reel' do
      messaging = shared_reel_params[:entry][0]['messaging'][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      described_class.new(messaging, instagram_inbox).perform

      message = instagram_inbox.messages.first
      expect(message.attachments.first.file_type).to eq('ig_reel')
      expect(message.attachments.first.external_url).to eq(
        shared_reel_params[:entry][0]['messaging'][0]['message']['attachments'][0]['payload']['url']
      )
    end

    it 'creates message with story id' do
      messaging = instagram_story_reply_event[:entry][0]['messaging'][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      story_url = messaging['message']['reply_to']['story']['url']

      stub_request(:get, story_url)
        .to_return(status: 200, body: 'image_data', headers: { 'Content-Type' => 'image/png' })

      described_class.new(messaging, instagram_inbox).perform

      message = instagram_inbox.messages.first

      expect(message.content).to eq('This is the story reply')
      expect(message.content_attributes[:story_sender]).to eq(instagram_inbox.channel.instagram_id)
      expect(message.content_attributes[:story_id]).to eq('chatwoot-app-user-id-1')
      expect(message.content_attributes[:image_type]).to eq('ig_story_reply')
      expect(message.attachments.first.file_type).to eq('ig_story')
      expect(message.attachments.first.external_url).to eq(story_url)
    end

    it 'creates message with reply to mid' do
      # Create first message to ensure reply to is valid
      first_messaging = dm_params[:entry][0]['messaging'][0]
      sender_id = first_messaging['sender']['id']
      create_instagram_contact_for_sender(sender_id, instagram_inbox)
      described_class.new(first_messaging, instagram_inbox).perform

      # Create second message with reply to mid, using same sender_id
      messaging = instagram_message_reply_event[:entry][0]['messaging'][0]
      messaging['sender']['id'] = sender_id
      described_class.new(messaging, instagram_inbox).perform

      first_message = instagram_inbox.messages.first
      reply_message = instagram_inbox.messages.last

      expect(reply_message.content).to eq('This is message with replyto mid')
      expect(reply_message.content_attributes[:in_reply_to_external_id]).to eq(first_message.source_id)
    end

    it 'handles deleted story' do
      messaging = story_mention_params[:entry][0][:messaging][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      story_source_id = messaging['message']['mid']

      stub_request(:get, %r{https://graph\.instagram\.com/.*?/#{story_source_id}\?.*})
        .to_return(status: 404, body: { error: { message: 'Story not found', code: 1_609_005 } }.to_json)

      described_class.new(messaging, instagram_inbox).perform

      message = instagram_inbox.messages.first

      expect(message.content).to eq('This story is no longer available.')
      expect(message.attachments.count).to eq(0)
    end

    it 'creates a location message from an Instagram generic template and syncs contact location', :aggregate_failures do
      messaging = location_template_messaging('instagram-location-message-id', timestamp: 1_789_851_158_285)
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      contact.update!(custom_attributes: { 'customer_status' => 'active' })
      media_url =
        'https://external-yyz1-1.xx.fbcdn.net/static_map.php?v=2069&size=545x280&zoom=15&markers=10.06120560%252C-84.73201644&language=en'
      stub_location_graph('instagram-location-message-id', media_url: media_url)

      described_class.new(messaging, instagram_inbox).perform

      message = instagram_inbox.reload.messages.first
      location = message.attachments.first
      attributes = contact.reload.custom_attributes

      expect(instagram_inbox.messages.count).to eq(1)
      expect(message.source_id).to eq('instagram-location-message-id')
      expect(message.attachments.count).to eq(1)
      expect(location.file_type).to eq('location')
      expect(location.coordinates_lat).to be_within(0.00000001).of(10.06120560)
      expect(location.coordinates_long).to be_within(0.00000001).of(-84.73201644)
      expect(location.external_url).to eq('https://maps.google.com/?q=10.06120560,-84.73201644')
      expect(location.fallback_title).to eq('Live location')
      expect(attributes['customer_status']).to eq('active')
      expect(attributes['location_url']).to eq('https://maps.google.com/?q=10.06120560,-84.73201644')
      expect(attributes['last_shared_latitude'].to_f).to be_within(0.00000001).of(10.06120560)
      expect(attributes['last_shared_longitude'].to_f).to be_within(0.00000001).of(-84.73201644)
      expect(attributes['last_shared_location_source']).to eq('instagram')
      expect(attributes['last_shared_location_at']).to eq(Time.zone.at(messaging['timestamp'] / 1000.0).iso8601(3))
      expect(
        a_request(:get, %r{https://graph\.instagram\.com/.*/instagram-location-message-id})
          .with(query: hash_including('fields' => 'attachments', 'access_token' => 'valid_instagram_token'))
      ).to have_been_made.once
    end

    it 'does not treat a non-location Instagram generic template as a location' do
      messaging = location_template_messaging('instagram-generic-template-id')
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      stub_location_graph(
        'instagram-generic-template-id',
        media_url: 'https://www.example.com/not-a-location.jpeg',
        title: 'Generic content'
      )

      described_class.new(messaging, instagram_inbox).perform

      expect(instagram_inbox.reload.messages.count).to eq(0)
      expect(contact.reload.custom_attributes['location_url']).to be_nil
    end

    it 'rejects an Instagram location template with coordinates outside valid ranges' do
      messaging = location_template_messaging('instagram-invalid-location-id')
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      stub_location_graph(
        'instagram-invalid-location-id',
        media_url: 'https://external.example.com/static_map.php?markers=999.00000000%252C-200.00000000'
      )

      described_class.new(messaging, instagram_inbox).perform

      expect(instagram_inbox.reload.messages.count).to eq(0)
      expect(contact.reload.custom_attributes['location_url']).to be_nil
    end

    it 'does not overwrite a newer contact location with an older Instagram location', :aggregate_failures do
      messaging = location_template_messaging('instagram-older-location-id', timestamp: 1_789_851_158_285)
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      newer_location_at = '2030-01-01T00:00:00.000Z'
      contact.update!(
        custom_attributes: {
          'customer_status' => 'active',
          'location_url' => 'https://maps.google.com/?q=1.234,5.678',
          'last_shared_latitude' => 1.234,
          'last_shared_longitude' => 5.678,
          'last_shared_location_at' => newer_location_at,
          'last_shared_location_source' => 'instagram'
        }
      )
      stub_location_graph(
        'instagram-older-location-id',
        media_url: 'https://external.example.com/static_map.php?markers=10.06120560%252C-84.73201644'
      )

      described_class.new(messaging, instagram_inbox).perform

      message = instagram_inbox.reload.messages.first
      attributes = contact.reload.custom_attributes

      expect(instagram_inbox.messages.count).to eq(1)
      expect(message.attachments.first.file_type).to eq('location')
      expect(attributes['customer_status']).to eq('active')
      expect(attributes['location_url']).to eq('https://maps.google.com/?q=1.234,5.678')
      expect(attributes['last_shared_latitude'].to_f).to eq(1.234)
      expect(attributes['last_shared_longitude'].to_f).to eq(5.678)
      expect(attributes['last_shared_location_at']).to eq(newer_location_at)
      expect(attributes['last_shared_location_source']).to eq('instagram')
    end

    it 'does not create message for unsupported file type' do
      messaging = story_mention_params[:entry][0][:messaging][0]
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id, contact_id: contact.id)

      # try to create a message with unsupported file type
      messaging['message']['attachments'][0]['type'] = 'unsupported_type'

      described_class.new(messaging, instagram_inbox, outgoing_echo: false).perform

      # Conversation should exist but no new message should be created
      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 0
    end

    it 'does not create message if the message is already exists' do
      messaging = dm_params[:entry][0]['messaging'][0]
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id, contact_id: contact.id)
      create(:message, account_id: account.id, inbox_id: instagram_inbox.id, conversation_id: conversation.id, message_type: 'outgoing',
                       source_id: 'message-id-1')

      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1

      messaging = dm_params[:entry][0]['messaging'][0]
      messaging[:message][:mid] = 'message-id-1' # Set same source_id as the existing message
      described_class.new(messaging, instagram_inbox, outgoing_echo: false).perform

      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1
    end

    it 'handles authorization errors' do
      instagram_channel.update(access_token: 'invalid_token')

      # Stub the request to return authorization error status
      stub_request(:get, %r{https://graph\.instagram\.com/.*?/Sender-id-.*?\?.*})
        .to_return(
          status: 401,
          body: { error: { message: 'unauthorized access token', code: 190 } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      messaging = dm_params[:entry][0]['messaging'][0]

      # The method should complete without raising an error
      expect do
        described_class.new(messaging, instagram_inbox).perform
      end.not_to raise_error
    end
  end

  context 'when lock to single conversation is disabled' do
    before do
      instagram_inbox.update!(lock_to_single_conversation: false)
    end

    it 'creates a new conversation if existing conversation is not present' do
      initial_count = Conversation.count
      messaging = dm_params[:entry][0]['messaging'][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)

      described_class.new(messaging, instagram_inbox).perform

      expect(instagram_inbox.conversations.count).to eq(1)
      expect(Conversation.count).to eq(initial_count + 1)
    end

    it 'will not create a new conversation if last conversation is not resolved' do
      messaging = dm_params[:entry][0]['messaging'][0]
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      existing_conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id,
                                                    contact_id: contact.id, status: :open)

      described_class.new(messaging, instagram_inbox).perform

      expect(instagram_inbox.conversations.last.id).to eq(existing_conversation.id)
    end

    it 'creates a new conversation if last conversation is resolved' do
      messaging = dm_params[:entry][0]['messaging'][0]
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      existing_conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id,
                                                    contact_id: contact.id, status: :resolved)

      initial_count = Conversation.count

      described_class.new(messaging, instagram_inbox).perform

      expect(instagram_inbox.conversations.last.id).not_to eq(existing_conversation.id)
      expect(Conversation.count).to eq(initial_count + 1)
    end
  end

  context 'when lock to single conversation is enabled' do
    before do
      instagram_inbox.update!(lock_to_single_conversation: true)
    end

    it 'creates a new conversation if existing conversation is not present' do
      initial_count = Conversation.count
      messaging = dm_params[:entry][0]['messaging'][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)

      described_class.new(messaging, instagram_inbox).perform

      expect(instagram_inbox.conversations.count).to eq(1)
      expect(Conversation.count).to eq(initial_count + 1)
    end

    it 'reopens last conversation if last conversation is resolved' do
      messaging = dm_params[:entry][0]['messaging'][0]
      contact = create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      existing_conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id,
                                                    contact_id: contact.id, status: :resolved)

      initial_count = Conversation.count
      messaging = dm_params[:entry][0]['messaging'][0]

      described_class.new(messaging, instagram_inbox).perform

      expect(instagram_inbox.conversations.last.id).to eq(existing_conversation.id)
      expect(Conversation.count).to eq(initial_count)
    end
  end

  describe '#fetch_story_link' do
    let(:story_data) do
      {
        'story' => {
          'mention' => {
            'link' => 'https://example.com/story-link',
            'id' => '18094414321535710'
          }
        },
        'from' => {
          'username' => 'instagram_user',
          'id' => '2450757355263608'
        },
        'id' => 'story-source-id-123'
      }.with_indifferent_access
    end

    before do
      # Stub the HTTP request to Instagram API
      stub_request(:get, %r{https://graph\.instagram\.com/.*?fields=story,from})
        .to_return(
          status: 200,
          body: story_data.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'saves story information when story mention is processed' do
      messaging = story_mention_params[:entry][0][:messaging][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      described_class.new(messaging, instagram_inbox).perform

      message = instagram_inbox.messages.first

      expect(message.content).to include('instagram_user')
      expect(message.attachments.count).to eq(1)
      expect(message.content_attributes[:story_sender]).to eq('instagram_user')
      expect(message.content_attributes[:story_id]).to eq('18094414321535710')
      expect(message.content_attributes[:image_type]).to eq('story_mention')
    end

    it 'handles deleted stories' do
      # Override the stub for this test to return a 404 error
      stub_request(:get, %r{https://graph\.instagram\.com/.*?fields=story,from})
        .to_return(
          status: 404,
          body: { error: { message: 'Story not found', code: 1_609_005 } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      messaging = story_mention_params[:entry][0][:messaging][0]
      create_instagram_contact_for_sender(messaging['sender']['id'], instagram_inbox)
      described_class.new(messaging, instagram_inbox).perform

      message = instagram_inbox.messages.first

      expect(message.content).to eq('This story is no longer available.')
      expect(message.attachments.count).to eq(0)
    end
  end
end
