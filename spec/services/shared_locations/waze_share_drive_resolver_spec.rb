require "rails_helper"

RSpec.describe SharedLocations::WazeShareDriveResolver do
  subject(:resolver) { described_class.new(content: content, account_id: 1) }

  let(:content) do
    "Sigue mi viaje: https://www.waze.com/ul?a=share_drive&sd=Valid_Token-123&env=row"
  end

  def response(body = nil, code: 200, **keyword_body)
    payload = body || keyword_body

    instance_double(
      HTTParty::Response,
      success?: code.between?(200, 299),
      code: code,
      body: payload.to_json
    )
  end

  it "prefers calculatedLocation as the Waze destination" do
    allow(HTTParty).to receive(:get).and_return(
      response(
        status: "ok",
        calculatedLocation: {
          name: "Farmacia Carrizal",
          city: "Carrizal, Puntarenas",
          latitude: 9.978192,
          longitude: -84.764175
        },
        route: [-84.73199, 10.06117, -84.764161, 9.978279]
      )
    )

    result = resolver.perform

    expect(result).to include(
      latitude: 9.978192,
      longitude: -84.764175,
      title: "Farmacia Carrizal",
      city: "Carrizal, Puntarenas",
      resolution_source: "calculated_location"
    )
  end

  it "uses the final route point when calculatedLocation is absent" do
    allow(HTTParty).to receive(:get).and_return(
      response(
        status: "ok",
        route: [-84.73199, 10.06117, -84.76416115234677, 9.978279378229692]
      )
    )

    result = resolver.perform

    expect(result).to include(
      latitude: 9.978279378229692,
      longitude: -84.76416115234677,
      resolution_source: "route_endpoint"
    )
  end

  it "returns nil when Waze reports an error" do
    allow(HTTParty).to receive(:get).and_return(
      response(status: "error", message: "expired")
    )

    expect(resolver.perform).to be_nil
  end

  it "rejects non-Waze hosts without making a request" do
    malicious = described_class.new(
      content: "https://evil.example/ul?a=share_drive&sd=Valid_Token-123&env=row"
    )

    expect(HTTParty).not_to receive(:get)
    expect(malicious.perform).to be_nil
  end

  it "rejects malformed tokens without making a request" do
    malformed = described_class.new(
      content: "https://www.waze.com/ul?a=share_drive&sd=bad%20token!&env=row"
    )

    expect(HTTParty).not_to receive(:get)
    expect(malformed.perform).to be_nil
  end

  it "skips a malformed Waze query and continues with a later valid Waze URL" do
    content = [
      "https://www.waze.com/ul?a=share_drive&sd=%ZZ&env=row",
      "https://www.waze.com/ul?a=share_drive&sd=Valid_Token-123&env=row"
    ].join(" ")

    resolver = described_class.new(content: content, account_id: 1)

    allow(HTTParty).to receive(:get).and_return(
      response(
        status: "ok",
        calculatedLocation: {
          latitude: 9.978192,
          longitude: -84.764175
        }
      )
    )

    result = resolver.perform

    expect(result).to include(
      latitude: 9.978192,
      longitude: -84.764175
    )
    expect(HTTParty).to have_received(:get).once
  end

  it "constructs the fixed Waze endpoint instead of requesting the supplied URL" do
    allow(HTTParty).to receive(:get).and_return(
      response(status: "error")
    )

    resolver.perform

    expect(HTTParty).to have_received(:get).with(
      "https://www.waze.com/row-rtserver/web/PickUpGetDriverInfo",
      hash_including(
        query: hash_including(
          token: "Valid_Token-123",
          getUserInfo: true
        )
      )
    )
  end
end
