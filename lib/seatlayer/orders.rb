# frozen_string_literal: true

module SeatLayer
  # Orders SeatLayer took through its own checkout: reads, CSV export,
  # refunds, cancellations and ticket resends.
  class Orders < Resource
    # One page of orders. +from+ and +to+ are epoch milliseconds.
    def list_orders(event_key: nil, season_key: nil, status: nil, from: nil, to: nil,
                    cursor: nil, limit: nil)
      @client.get("/v1/orders", compact({ "eventKey" => event_key, "seasonKey" => season_key,
                                          "status" => status, "from" => from, "to" => to,
                                          "cursor" => cursor, "limit" => limit }))
    end

    # Read one order.
    def retrieve_order(order_id)
      @client.get("/v1/orders/#{encode(order_id)}")
    end

    # List one order's tickets.
    def list_order_tickets(order_id)
      @client.get("/v1/orders/#{encode(order_id)}/tickets")
    end

    # One page of an event's orders. +search+ is sent as the API's +q+
    # parameter; +from+ and +to+ are epoch milliseconds.
    def list_event_orders(event_key, search: nil, status: nil, paid_by: nil, from: nil, to: nil,
                          cursor: nil, limit: nil)
      @client.get("/v1/events/#{encode(event_key)}/orders",
                  compact({ "q" => search, "status" => status, "paidBy" => paid_by,
                            "from" => from, "to" => to, "cursor" => cursor, "limit" => limit }))
    end

    # Read one of an event's orders.
    def retrieve_event_order(event_key, order_id)
      @client.get("/v1/events/#{encode(event_key)}/orders/#{encode(order_id)}")
    end

    # Download an event's orders as CSV, with the same filters as
    # +list_event_orders+. Returns the raw CSV text.
    def export_event_orders_csv(event_key, search: nil, status: nil, paid_by: nil, from: nil,
                                to: nil)
      @client.get_text("/v1/events/#{encode(event_key)}/orders.csv",
                       compact({ "q" => search, "status" => status, "paidBy" => paid_by,
                                 "from" => from, "to" => to }))
    end

    # Refund an event order, in full or by +amount_minor+.
    def refund_event_order(event_key, order_id, amount_minor: nil, idempotency_key: nil)
      @client.post("/v1/events/#{encode(event_key)}/orders/#{encode(order_id)}/refund",
                   compact({ "amountMinor" => amount_minor }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Cancel an event order.
    def cancel_event_order(event_key, order_id, reason:, note: nil, refund_confirmed: nil,
                           used_tickets_acknowledged: nil, notify_buyer: nil, idempotency_key: nil)
      body = compact({ "reason" => reason, "note" => note, "refundConfirmed" => refund_confirmed,
                       "usedTicketsAcknowledged" => used_tickets_acknowledged,
                       "notifyBuyer" => notify_buyer })
      @client.post("/v1/events/#{encode(event_key)}/orders/#{encode(order_id)}/cancel", body,
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Send an event order's tickets again. Single-attempt: never retried automatically.
    def resend_event_order_tickets(event_key, order_id, email: nil)
      @client.post("/v1/events/#{encode(event_key)}/orders/#{encode(order_id)}/resend",
                   compact({ "email" => email }))
    end
  end
end
