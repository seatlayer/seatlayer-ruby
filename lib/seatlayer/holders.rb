# frozen_string_literal: true

module SeatLayer
  # Season holders and customers: contact details, sessions, tickets, ticket
  # transfers between holders, returns, and renewals.
  class Holders < Resource
    # One page of customers, or the one matching +email+ or +holder_ref+.
    def list_customers(email: nil, holder_ref: nil, cursor: nil, limit: nil)
      @client.get("/v1/customers", compact({ "email" => email, "holderRef" => holder_ref,
                                             "cursor" => cursor, "limit" => limit }))
    end

    # Read one holder.
    def retrieve_holder(holder_ref)
      @client.get(path(holder_ref))
    end

    # Set a holder's email, name or phone. Pass +nil+ for +name+ or +phone+ to
    # send an explicit JSON null.
    def update_holder(holder_ref, email: nil, name: UNSET, phone: UNSET, idempotency_key: nil)
      body = compact({ "email" => email })
      body.merge!(supplied({ "name" => name, "phone" => phone }))
      @client.mutation_with_header_replay(
        "PATCH", path(holder_ref), body, idempotency_key: idempotency_key
      )
    end

    # Sign a holder out of every session, or only out of +session_id+.
    # Single-attempt.
    def revoke_holder_sessions(holder_ref, session_id: nil)
      @client.post(path(holder_ref, "/sessions/revoke"), compact({ "sessionId" => session_id }))
    end

    # List the Seasons a holder belongs to.
    def list_holder_seasons(holder_ref)
      @client.get(path(holder_ref, "/seasons"))
    end

    # One page of a holder's tickets. +from+ and +to+ are epoch milliseconds.
    def list_holder_tickets(holder_ref, season_key: nil, from: nil, to: nil, cursor: nil,
                            limit: nil)
      @client.get(path(holder_ref, "/tickets"),
                  compact({ "seasonKey" => season_key, "from" => from, "to" => to,
                            "cursor" => cursor, "limit" => limit }))
    end

    # Read one of a holder's tickets.
    def retrieve_holder_ticket(holder_ref, ticket_id)
      @client.get(path(holder_ref, "/tickets/#{encode(ticket_id)}"))
    end

    # Offer tickets to another person by email. Turning customer sends off in
    # Settings › Ticket site doesn't stop your server; cut-offs still apply.
    def create_holder_transfer(holder_ref, ticket_ids:, to_email:, idempotency_key: nil)
      @client.post(path(holder_ref, "/transfers"),
                   { "ticketIds" => ticket_ids, "toEmail" => to_email },
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # List a holder's ticket transfers.
    def list_holder_transfers(holder_ref)
      @client.get(path(holder_ref, "/transfers"))
    end

    # Cancel a transfer that has not been accepted yet. Single-attempt.
    def cancel_holder_transfer(holder_ref, transfer_id)
      @client.post(path(holder_ref, "/transfers/#{encode(transfer_id)}/cancel"))
    end

    # Accept a transfer for its recipient. Single-attempt.
    def accept_holder_transfer(holder_ref, transfer_id)
      @client.post(path(holder_ref, "/transfers/#{encode(transfer_id)}/accept"))
    end

    # Give back a holder's seat on one date, one per ticket: 1 to 20 tickets,
    # all of one Season. A repeat with the same key answers with the same return.
    # Turning give-backs off in Settings › Ticket site doesn't stop your server;
    # cut-offs still apply.
    def create_holder_return(holder_ref, ticket_ids:, idempotency_key: nil)
      @client.post(path(holder_ref, "/returns"), { "ticketIds" => ticket_ids },
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Start a SeatLayer checkout that renews one of a holder's offers (+renewalOffer+
    # on +list_holder_seasons+). Send the buyer to +payment.url+. Retried with one
    # Idempotency-Key, which answers the same order.
    def create_holder_renewal_checkout(holder_ref, offer_id, return_url:, buyer_email: nil,
                                       buyer_name: nil, provider: nil, idempotency_key: nil)
      @client.post(path(holder_ref, "/renewal-offers/#{encode(offer_id)}/checkout"),
                   compact({ "returnUrl" => return_url, "buyerEmail" => buyer_email,
                             "buyerName" => buyer_name, "provider" => provider }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Decline one of a holder's renewal offers and release its seats. +reason+
    # (1 to 200 characters) is kept on the offer as +declineReason+; declining
    # again answers the same offer, with the first reason. Single-attempt.
    def decline_holder_renewal_offer(holder_ref, offer_id, reason: nil)
      @client.post(path(holder_ref, "/renewal-offers/#{encode(offer_id)}/decline"),
                   compact({ "reason" => reason }))
    end

    private

    def path(holder_ref, suffix = "")
      "/v1/holders/#{encode(holder_ref)}#{suffix}"
    end
  end
end
