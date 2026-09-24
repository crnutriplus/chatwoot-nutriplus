require 'rails_helper'

RSpec.describe SharedLocations::CoordinateResolver do
  subject(:resolver) { described_class.new(content: content) }

  describe '#perform' do
    it 'resolves a geo URI' do
      content = 'geo:9.97920997,-84.76543566'

      result = described_class.new(content: content).perform

      expect(result).to include(
        latitude: 9.97920997,
        longitude: -84.76543566,
        resolution_source: 'geo_uri',
        resolution_provider: 'coordinates'
      )
    end

    it 'resolves coordinates from a Google Maps query parameter' do
      content = 'https://maps.google.com/?q=9.97920997,-84.76543566'

      result = described_class.new(content: content).perform

      expect(result).to include(
        latitude: 9.97920997,
        longitude: -84.76543566,
        resolution_source: 'url_query'
      )
    end

    it 'resolves Google Maps @ coordinates' do
      content = 'https://www.google.com/maps/@9.97920997,-84.76543566,17z'

      result = described_class.new(content: content).perform

      expect(result).to include(
        latitude: 9.97920997,
        longitude: -84.76543566,
        resolution_source: 'url_at'
      )
    end

    it 'resolves Google Maps !3d latitude !4d longitude coordinates' do
      content = 'https://www.google.com/maps/place/x/data=!3d9.97920997!4d-84.76543566'

      result = described_class.new(content: content).perform

      expect(result).to include(
        latitude: 9.97920997,
        longitude: -84.76543566,
        resolution_source: 'url_3d4d'
      )
    end

    it 'resolves Google Maps !2d longitude !3d latitude coordinates' do
      content = 'https://www.google.com/maps/place/x/data=!2d-84.76543566!3d9.97920997'

      result = described_class.new(content: content).perform

      expect(result).to include(
        latitude: 9.97920997,
        longitude: -84.76543566,
        resolution_source: 'url_2d3d'
      )
    end

    it 'resolves a plain coordinate pair outside a URL' do
      content = 'Mi ubicacion es 9.97920997, -84.76543566'

      result = described_class.new(content: content).perform

      expect(result).to include(
        latitude: 9.97920997,
        longitude: -84.76543566,
        resolution_source: 'plain_coordinates'
      )
    end

    it 'does not treat ordinary integer pairs as coordinates' do
      content = 'Necesito 10, 20 unidades'

      expect(described_class.new(content: content).perform).to be_nil
    end

    it 'rejects invalid coordinate ranges' do
      content = '200.12345, -300.54321'

      expect(described_class.new(content: content).perform).to be_nil
    end

    it 'does not treat the known dynamic Google shared-location URL as static coordinates' do
      content = [
        'https://www.google.com/maps/@/data=!4m5!7m4!1m2!',
        '1s102998289525100309194!2sSharedToken!2e2'
      ].join

      expect(described_class.new(content: content).perform).to be_nil
    end
  end
end
