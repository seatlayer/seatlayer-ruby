# frozen_string_literal: true

RSpec.describe SeatLayer::Events do
  it "maps all 14 event sales operations, none of them replay-backed" do
    client, transport = build_client(Array.new(14) { { status: 200 } })
    events = client.events
    event = "ev/a"

    events.retrieve_event_buyer_checkout(event)
    events.replace_event_buyer_checkout(event, buyer_checkout: "seatlayer", expected_revision: 3)
    events.retrieve_event_payment_gateway(event, currency: "EUR")
    events.replace_event_payment_gateway(event, connection_id: nil)
    events.retrieve_event_sales_readiness(event)
    events.preflight_event_sales(event, order_id: "ord_1")
    events.transition_event_sales(event, to: "live", expected_revision: 4)
    events.retrieve_event_booking_fee(event)
    events.replace_event_booking_fee(event, booking_fee_minor: nil)
    events.list_event_discount_codes(event)
    events.create_event_discount_code(event, code: "EARLY", kind: "percent", percent: 10,
                                             max_uses: nil)
    events.update_event_discount_code(event, "code/1", state: "paused", ends_at: 1_800_000_000_000)
    events.end_event_discount_code(event, "code/1")
    events.delete_event_discount_code(event, "code/1")

    expect(transport.calls.map { |call| request_summary(call) }).to eq(
      [
        ["GET /v1/events/ev%2Fa/buyer-checkout", nil, false],
        ["PUT /v1/events/ev%2Fa/buyer-checkout",
         { "buyerCheckout" => "seatlayer", "expectedRevision" => 3 }, false],
        ["GET /v1/events/ev%2Fa/payment-gateway?currency=EUR", nil, false],
        ["PUT /v1/events/ev%2Fa/payment-gateway", { "connectionId" => nil }, false],
        ["GET /v1/events/ev%2Fa/sales/readiness", nil, false],
        ["POST /v1/events/ev%2Fa/sales/preflight", { "orderId" => "ord_1" }, false],
        ["POST /v1/events/ev%2Fa/sales/transition", { "to" => "live", "expectedRevision" => 4 }, false],
        ["GET /v1/events/ev%2Fa/booking-fee", nil, false],
        ["PUT /v1/events/ev%2Fa/booking-fee", { "bookingFeeMinor" => nil }, false],
        ["GET /v1/events/ev%2Fa/discount-codes", nil, false],
        ["POST /v1/events/ev%2Fa/discount-codes",
         { "code" => "EARLY", "kind" => "percent", "percent" => 10, "maxUses" => nil }, false],
        ["PATCH /v1/events/ev%2Fa/discount-codes/code%2F1",
         { "state" => "paused", "endsAt" => 1_800_000_000_000 }, false],
        ["POST /v1/events/ev%2Fa/discount-codes/code%2F1/end", nil, false],
        ["DELETE /v1/events/ev%2Fa/discount-codes/code%2F1", nil, false]
      ]
    )
  end

  it "returns an empty result when a discount code is deleted (204)" do
    client, = build_client([{ status: 204, body: "" }])

    expect(client.events.delete_event_discount_code("ev_1", "code_1")).to eq({})
  end
end
