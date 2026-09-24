require 'rails_helper'

RSpec.describe SharedLocations::LocationResolver do
  subject(:resolver) do
    described_class.new(
      content: content,
      account_id: 1
    )
  end

  let(:content) { 'Sigue mi viaje en Waze' }

  it 'prefers the Waze share-drive resolver' do
    waze_result = {
      latitude: 9.978192,
      longitude: -84.764175,
      title: 'Farmacia Carrizal',
      city: 'Carrizal, Puntarenas',
      map_url: 'https://maps.google.com/?q=9.978192,-84.764175',
      resolution_source: 'calculated_location'
    }

    allow(SharedLocations::WazeShareDriveResolver)
      .to receive(:new)
      .and_return(instance_double(
                    SharedLocations::WazeShareDriveResolver,
                    perform: waze_result
                  ))

    result = resolver.perform

    expect(result).to include(
      latitude: 9.978192,
      longitude: -84.764175,
      resolution_provider: 'waze'
    )
  end

  it 'falls back to deterministic coordinates when Waze does not resolve' do
    allow(SharedLocations::WazeShareDriveResolver)
      .to receive(:new)
      .and_return(instance_double(
                    SharedLocations::WazeShareDriveResolver,
                    perform: nil
                  ))

    coordinate_result = {
      latitude: 9.97920997,
      longitude: -84.76543566,
      title: 'Shared location',
      city: nil,
      map_url: 'https://maps.google.com/?q=9.97920997,-84.76543566',
      resolution_source: 'url_query',
      resolution_provider: 'coordinates'
    }

    allow(SharedLocations::CoordinateResolver)
      .to receive(:new)
      .and_return(instance_double(
                    SharedLocations::CoordinateResolver,
                    perform: coordinate_result
                  ))

    expect(resolver.perform).to eq(coordinate_result)
  end

  it 'returns nil when neither resolver can determine a location' do
    allow(SharedLocations::WazeShareDriveResolver)
      .to receive(:new)
      .and_return(instance_double(
                    SharedLocations::WazeShareDriveResolver,
                    perform: nil
                  ))

    allow(SharedLocations::CoordinateResolver)
      .to receive(:new)
      .and_return(instance_double(
                    SharedLocations::CoordinateResolver,
                    perform: nil
                  ))

    expect(resolver.perform).to be_nil
  end
end
