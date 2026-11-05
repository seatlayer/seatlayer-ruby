# frozen_string_literal: true

RSpec.describe SeatLayer::Holders do
  it "maps all 11 holder and customer operations and their replay classes" do
    client, transport = build_client(Array.new(11) { { status: 200 } })
    holders = client.holders
    ref = "hol/a"

    holders.list_customers(email: "ann@example.com", holder_ref: "h 1", limit: 10)
    holders.retrieve_holder(ref)
    holders.update_holder(ref, email: "ann@example.com", phone: nil, idempotency_key: "holder-1")
    holders.revoke_holder_sessions(ref, session_id: "ses/1")
    holders.list_holder_seasons(ref)
    holders.list_holder_tickets(ref, season_key: "sea/a", from: 1, to: 2, cursor: "c/1", limit: 5)
    holders.retrieve_holder_ticket(ref, "tkt/1")
    holders.create_holder_transfer(ref, ticket_ids: ["tkt/1"], to_email: "bo@example.com")
    holders.list_holder_transfers(ref)
    holders.cancel_holder_transfer(ref, "xfer/1")
    holders.accept_holder_transfer(ref, "xfer/1")

    expect(transport.calls.map { |call| request_summary(call) }).to eq(
      [
        ["GET /v1/customers?email=ann%40example.com&holderRef=h+1&limit=10", nil, false],
        ["GET /v1/holders/hol%2Fa", nil, false],
        ["PATCH /v1/holders/hol%2Fa", { "email" => "ann@example.com", "phone" => nil }, true],
        ["POST /v1/holders/hol%2Fa/sessions/revoke", { "sessionId" => "ses/1" }, false],
        ["GET /v1/holders/hol%2Fa/seasons", nil, false],
        ["GET /v1/holders/hol%2Fa/tickets?seasonKey=sea%2Fa&from=1&to=2&cursor=c%2F1&limit=5",
         nil, false],
        ["GET /v1/holders/hol%2Fa/tickets/tkt%2F1", nil, false],
        ["POST /v1/holders/hol%2Fa/transfers",
         { "ticketIds" => ["tkt/1"], "toEmail" => "bo@example.com" }, true],
        ["GET /v1/holders/hol%2Fa/transfers", nil, false],
        ["POST /v1/holders/hol%2Fa/transfers/xfer%2F1/cancel", nil, false],
        ["POST /v1/holders/hol%2Fa/transfers/xfer%2F1/accept", nil, false]
      ]
    )
    expect(transport.calls[2].headers["Idempotency-Key"]).to eq("holder-1")
  end

  it "sends an explicit null only for the contact fields passed as nil" do
    client, transport = build_client([{ status: 200 }])

    client.holders.update_holder("h_1", name: nil)

    expect(JSON.parse(transport.calls[0].body)).to eq("name" => nil)
  end
end
