# frozen_string_literal: true

RSpec.describe SeatLayer::Holders do
  it "maps all 14 holder and customer operations and their replay classes" do
    client, transport = build_client(Array.new(15) { { status: 200 } })
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
    holders.create_holder_return(
      ref, ticket_ids: ["tkt_0123456789abcdef01234567"], idempotency_key: "return-1"
    )
    holders.create_holder_renewal_checkout(
      ref, "offer/1", return_url: "https://tickets.example/renewed", buyer_email: "cara@example.com",
                      buyer_name: "Cara", provider: "stripe", idempotency_key: "renew-1"
    )
    holders.decline_holder_renewal_offer(ref, "offer/1", reason: "Moving away")
    holders.decline_holder_renewal_offer(ref, "offer/1")

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
        ["POST /v1/holders/hol%2Fa/transfers/xfer%2F1/accept", nil, false],
        ["POST /v1/holders/hol%2Fa/returns", { "ticketIds" => ["tkt_0123456789abcdef01234567"] }, true],
        ["POST /v1/holders/hol%2Fa/renewal-offers/offer%2F1/checkout",
         { "returnUrl" => "https://tickets.example/renewed", "buyerEmail" => "cara@example.com",
           "buyerName" => "Cara", "provider" => "stripe" }, true],
        ["POST /v1/holders/hol%2Fa/renewal-offers/offer%2F1/decline", { "reason" => "Moving away" }, false],
        ["POST /v1/holders/hol%2Fa/renewal-offers/offer%2F1/decline", {}, false]
      ]
    )
    expect(transport.calls[2].headers["Idempotency-Key"]).to eq("holder-1")
    expect(transport.calls[11].headers["Idempotency-Key"]).to eq("return-1")
    expect(transport.calls[12].headers["Idempotency-Key"]).to eq("renew-1")
  end

  it "retries a holder return with one Idempotency-Key, generated or the caller's" do
    created = '{"return":{"returnId":"ret_1","state":"returned","seasonKey":"sea_1",' \
              '"tickets":[],"createdAt":1}}'
    responses = [
      { status: 429, headers: { "Retry-After" => "0" } }, { status: 201, body: created },
      { status: 429, headers: { "Retry-After" => "0" } }, { status: 200, body: created }
    ]
    client, transport = build_client(responses)

    first = client.holders.create_holder_return("a/b", ticket_ids: ["tkt_0123456789abcdef01234567"])
    again = client.holders.create_holder_return(
      "a/b", ticket_ids: ["tkt_0123456789abcdef01234567"], idempotency_key: "return-1"
    )

    expect([first, again]).to all(eq(JSON.parse(created)))
    expect(transport.calls.map { |call| request_summary(call) }).to all(
      eq(["POST /v1/holders/a%2Fb/returns", { "ticketIds" => ["tkt_0123456789abcdef01234567"] }, true])
    )
    keys = transport.calls.map { |call| call.headers["Idempotency-Key"] }
    expect(keys[0]).to eq(keys[1])
    expect(keys[2..]).to eq(%w[return-1 return-1])
  end

  it "retries a holder renewal checkout with one key, generated or the caller's, and declines once" do
    responses = [
      { status: 429, headers: { "Retry-After" => "0" } }, { status: 201 },
      { status: 429, headers: { "Retry-After" => "0" } }, { status: 201 },
      { status: 429, headers: { "Retry-After" => "0" } }
    ]
    client, transport = build_client(responses)

    client.holders.create_holder_renewal_checkout("a/b", "offer_1", return_url: "https://tickets.example/r")
    client.holders.create_holder_renewal_checkout("a/b", "offer_1", return_url: "https://tickets.example/r",
                                                                    idempotency_key: "renew-1")
    expect { client.holders.decline_holder_renewal_offer("a/b", "offer_1", reason: "Moving away") }
      .to raise_error(SeatLayer::RateLimitError)

    checkout = ["POST /v1/holders/a%2Fb/renewal-offers/offer_1/checkout",
                { "returnUrl" => "https://tickets.example/r" }, true]
    expect(transport.calls.map { |call| request_summary(call) }).to eq(
      [checkout, checkout, checkout, checkout,
       ["POST /v1/holders/a%2Fb/renewal-offers/offer_1/decline", { "reason" => "Moving away" }, false]]
    )
    keys = transport.calls.map { |call| call.headers["Idempotency-Key"] }
    expect(keys[0]).to eq(keys[1])
    expect(keys[2..3]).to eq(%w[renew-1 renew-1])
  end

  it "sends an explicit null only for the contact fields passed as nil" do
    client, transport = build_client([{ status: 200 }])

    client.holders.update_holder("h_1", name: nil)

    expect(JSON.parse(transport.calls[0].body)).to eq("name" => nil)
  end
end
