require 'rails_helper'

RSpec.describe SharedLocations::WazeMessageService do
  let(:conversation) { create(:conversation) }
  let(:contact) { conversation.contact }

  let(:message) do
    create(
      :message,
      account: conversation.account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: contact,
      message_type: :incoming,
      content: 'Sigue mi viaje en Waze'
    )
  end

  let(:location) do
    {
      latitude: 9.978192,
      longitude: -84.764175,
      title: 'Farmacia Carrizal',
      city: 'Carrizal, Puntarenas',
      map_url: 'https://maps.google.com/?q=9.978192,-84.764175',
      resolution_source: 'calculated_location',
      resolution_provider: 'waze'
    }
  end

  let(:resolver) do
    instance_double(
      SharedLocations::LocationResolver,
      perform: location
    )
  end

  before do
    allow(SharedLocations::LocationResolver)
      .to receive(:new)
      .and_return(resolver)
  end

  def perform
    described_class.new(
      message: message,
      contact: contact,
      content: message.content,
      shared_at: Time.zone.parse('2026-09-22T04:00:00Z')
    ).perform
  end

  it 'creates one native location attachment' do
    perform

    attachment = message.reload.attachments.find_by(file_type: :location)

    expect(attachment).to be_present
    expect(attachment.coordinates_lat).to eq(9.978192)
    expect(attachment.coordinates_long).to eq(-84.764175)
    expect(attachment.external_url).to eq(
      'https://maps.google.com/?q=9.978192,-84.764175'
    )
    expect(attachment.fallback_title).to eq('Farmacia Carrizal')
  end

  it 'truncates long fallback titles to 255 characters' do
    long_title = 'Destino Waze ' * 40
    location[:title] = long_title

    perform

    attachment = message.reload.attachments.find_by!(file_type: :location)

    expect(attachment.fallback_title).to eq(long_title.first(255))
    expect(attachment.fallback_title.length).to eq(255)
  end

  it 'syncs the contact with Waze as the location source' do
    sync_service = instance_double(
      SharedLocations::ContactLocationSyncService,
      perform: true
    )

    expect(SharedLocations::ContactLocationSyncService)
      .to receive(:new)
      .with(
        contact: contact,
        location: instance_of(Attachment),
        shared_at: instance_of(ActiveSupport::TimeWithZone),
        source: 'waze'
      )
      .and_return(sync_service)

    expect(sync_service).to receive(:perform)

    perform
  end

  it 'uses Instagram as the contact source for deterministic coordinates received on Instagram' do
    location[:resolution_provider] = 'coordinates'

    instagram_inbox = instance_double(
      Inbox,
      channel_type: 'Channel::Instagram'
    )

    allow(message)
      .to receive(:inbox)
      .and_return(instagram_inbox)

    sync_service = instance_double(
      SharedLocations::ContactLocationSyncService,
      perform: true
    )

    expect(SharedLocations::ContactLocationSyncService)
      .to receive(:new)
      .with(
        contact: contact,
        location: instance_of(Attachment),
        shared_at: instance_of(ActiveSupport::TimeWithZone),
        source: 'instagram'
      )
      .and_return(sync_service)

    expect(sync_service).to receive(:perform)

    perform
  end

  it 'does not write an unsupported contact source for deterministic coordinates from Facebook' do
    location[:resolution_provider] = 'coordinates'

    facebook_inbox = instance_double(
      Inbox,
      channel_type: 'Channel::FacebookPage'
    )

    allow(message)
      .to receive(:inbox)
      .and_return(facebook_inbox)

    expect(SharedLocations::ContactLocationSyncService)
      .not_to receive(:new)

    perform

    expect(
      message.reload.attachments.where(file_type: :location).count
    ).to eq(1)
  end

  it 'does not create duplicate location attachments' do
    perform
    perform

    expect(
      message.reload.attachments.where(file_type: :location).count
    ).to eq(1)
  end

  it 'leaves the original message intact when Waze cannot resolve' do
    allow(resolver).to receive(:perform).and_return(nil)

    expect { perform }.not_to change(Attachment, :count)

    expect(message.reload.content).to eq('Sigue mi viaje en Waze')
  end

  it 'ignores outgoing messages' do
    allow(message).to receive(:incoming?).and_return(false)
    expect(resolver).not_to receive(:perform)

    perform

    expect(message.reload.attachments.where(file_type: :location)).to be_empty
  end
end
