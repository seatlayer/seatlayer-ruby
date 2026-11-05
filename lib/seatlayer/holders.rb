# frozen_string_literal: true

module SeatLayer
  # Season holders and customers: contact details, sessions, tickets and
  # ticket transfers between holders.
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

    # Offer tickets to another person by email.
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

    private

    def path(holder_ref, suffix = "")
      "/v1/holders/#{encode(holder_ref)}#{suffix}"
    end
  end
end
