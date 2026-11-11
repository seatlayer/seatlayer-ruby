# frozen_string_literal: true

RSpec.describe SeatLayer::Orders do
  it "maps all 9 order operations and their replay classes" do
    client, transport = build_client(Array.new(9) { { status: 200 } })
    orders = client.orders
    event = "ev/a"

    orders.list_orders(season_key: "sea/a", holder_ref: "ord/1", status: "confirmed",
                       from: 1, to: 2, limit: 20)
    orders.retrieve_order("ord/1")
    orders.list_order_tickets("ord/1")
    orders.list_event_orders(event, search: "ann lee", paid_by: "card", cursor: "c/1")
    orders.retrieve_event_order(event, "ord/1")
    orders.export_event_orders_csv(event, status: "refunded", from: 3, to: 4)
    orders.refund_event_order(event, "ord/1", amount_minor: 250, idempotency_key: "refund-1")
    orders.cancel_event_order(
      event, "ord/1", reason: "lost_dispute", refund_confirmed: true,
                      used_tickets_acknowledged: false
    )
    orders.resend_event_order_tickets(event, "ord/1")

    expect(transport.calls.map { |call| request_summary(call) }).to eq(
      [
        ["GET /v1/orders?seasonKey=sea%2Fa&holderRef=ord%2F1&status=confirmed&from=1&to=2&limit=20",
         nil, false],
        ["GET /v1/orders/ord%2F1", nil, false],
        ["GET /v1/orders/ord%2F1/tickets", nil, false],
        ["GET /v1/events/ev%2Fa/orders?q=ann+lee&paidBy=card&cursor=c%2F1", nil, false],
        ["GET /v1/events/ev%2Fa/orders/ord%2F1", nil, false],
        ["GET /v1/events/ev%2Fa/orders.csv?status=refunded&from=3&to=4", nil, false],
        ["POST /v1/events/ev%2Fa/orders/ord%2F1/refund", { "amountMinor" => 250 }, true],
        ["POST /v1/events/ev%2Fa/orders/ord%2F1/cancel",
         { "reason" => "lost_dispute", "refundConfirmed" => true,
           "usedTicketsAcknowledged" => false }, true],
        ["POST /v1/events/ev%2Fa/orders/ord%2F1/resend", {}, false]
      ]
    )
    expect(transport.calls[6].headers["Idempotency-Key"]).to eq("refund-1")
  end

  it "returns the event orders CSV as raw text" do
    csv = "orderId,email\nord_1,ann@example.com\n"
    client, transport = build_client([{ status: 200, body: csv,
                                        headers: { "Content-Type" => "text/csv" } }])

    expect(client.orders.export_event_orders_csv("ev_1", search: "ann")).to eq(csv)
    expect(transport.calls[0].headers["Accept"]).to eq("text/csv")
  end

  it "never retries an unsupported ticket resend" do
    client, transport = build_client([{ status: 500, body: '{"code":"internal"}' },
                                      { status: 200 }])

    expect { client.orders.resend_event_order_tickets("ev_1", "ord_1", email: "ann@example.com") }
      .to raise_error(SeatLayer::APIError)
    expect(transport.calls.length).to eq(1)
  end
end
