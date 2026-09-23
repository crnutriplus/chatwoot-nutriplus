require "rails_helper"

RSpec.describe SharedLocations::ContactLocationSyncService do
  let(:contact) do
    create(
      :contact,
      custom_attributes: {
        "customer_status" => "active",
        "default_delivery_address" => "Direccion existente"
      }
    )
  end

  let(:location) do
    instance_double(
      Attachment,
      coordinates_lat: 9.978192,
      coordinates_long: -84.764175,
      external_url: "https://maps.google.com/?q=9.978192,-84.764175"
    )
  end

  def perform(shared_at:)
    described_class.new(
      contact: contact,
      location: location,
      shared_at: shared_at,
      source: "waze"
    ).perform
  end

  it "stores the shared location and preserves existing attributes" do
    shared_at = Time.zone.parse("2026-09-22T04:00:00Z")

    expect(perform(shared_at: shared_at)).to be true

    attributes = contact.reload.custom_attributes

    expect(attributes).to include(
      "customer_status" => "active",
      "default_delivery_address" => "Direccion existente",
      "location_url" => "https://maps.google.com/?q=9.978192,-84.764175",
      "last_shared_latitude" => 9.978192,
      "last_shared_longitude" => -84.764175,
      "last_shared_location_at" => shared_at.iso8601(3),
      "last_shared_location_source" => "waze"
    )
  end

  it "does not overwrite a newer stored location" do
    newer_at = Time.zone.parse("2026-09-22T05:00:00Z")

    contact.update!(
      custom_attributes: contact.custom_attributes.merge(
        "location_url" => "https://maps.google.com/?q=1.234,5.678",
        "last_shared_latitude" => 1.234,
        "last_shared_longitude" => 5.678,
        "last_shared_location_at" => newer_at.iso8601(3),
        "last_shared_location_source" => "instagram"
      )
    )

    older_at = Time.zone.parse("2026-09-22T04:00:00Z")

    expect(perform(shared_at: older_at)).to be false

    attributes = contact.reload.custom_attributes

    expect(attributes["location_url"]).to eq(
      "https://maps.google.com/?q=1.234,5.678"
    )
    expect(attributes["last_shared_latitude"]).to eq(1.234)
    expect(attributes["last_shared_longitude"]).to eq(5.678)
    expect(attributes["last_shared_location_at"]).to eq(newer_at.iso8601(3))
    expect(attributes["last_shared_location_source"]).to eq("instagram")
  end

  it "normalizes a millisecond unix timestamp" do
    shared_at = 1_790_047_845_000

    expect(perform(shared_at: shared_at)).to be true

    expect(
      contact.reload.custom_attributes["last_shared_location_at"]
    ).to eq(Time.zone.at(1_790_047_845).iso8601(3))
  end
end
