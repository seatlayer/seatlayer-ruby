# frozen_string_literal: true

module SeatLayer
  # Fixed Renewable Season organizer operations for trusted backends.
  #
  # Browser selection belongs in the distinct SeasonPicker. Give it only the
  # show-once scoped token returned by +create_season_buyer_access_session+.
  #
  # One thin method per public Season operation (83 of them), so the class is
  # long by design rather than doing too much.
  # rubocop:disable-next Metrics/ClassLength
  class Seasons < Resource
    def list_seasons(workspace_id: nil, structure_state: nil, limit: nil, cursor: nil)
      @client.get("/v1/seasons", compact({ "workspaceId" => workspace_id,
                                           "structureState" => structure_state,
                                           "limit" => limit, "cursor" => cursor }))
    end

    # Read-only compatibility preflight.
    def validate_season(event_keys: nil, source_performance_group_keys: nil)
      @client.post("/v1/seasons/validate",
                   selection(event_keys, source_performance_group_keys))
    end

    def create_season(name:, event_keys: nil, source_performance_group_keys: nil,
                      edition: UNSET, idempotency_key: nil)
      body = selection(event_keys, source_performance_group_keys).merge("name" => name)
      body.merge!(supplied({ "edition" => edition }))
      @client.post("/v1/seasons", body, idempotency_key: idempotency_key,
                                        retry_policy: :header_replay)
    end

    def retrieve_season(season_key)
      @client.get(path(season_key))
    end

    # Rename a draft, or set how the Season sells. +checkout_mode+ ("seatlayer" or
    # "server") cannot go back to undecided and is fixed once a live booking exists.
    # The cutoffs are hours (0 to 720) before a date starts; pass +nil+ to send an
    # explicit JSON null, which means until the date starts.
    def update_season(season_key, expected_revision:, name: nil, edition: UNSET,
                      checkout_mode: nil, transfer_cutoff_hours: UNSET,
                      return_cutoff_hours: UNSET, idempotency_key: nil)
      body = compact({ "expectedRevision" => expected_revision, "name" => name,
                       "checkoutMode" => checkout_mode })
      body.merge!(supplied({ "edition" => edition, "transferCutoffHours" => transfer_cutoff_hours,
                             "returnCutoffHours" => return_cutoff_hours }))
      @client.mutation_with_header_replay(
        "PATCH", path(season_key), body, idempotency_key: idempotency_key
      )
    end

    def delete_season(season_key, idempotency_key: nil)
      @client.mutation_with_header_replay(
        "DELETE", path(season_key), idempotency_key: idempotency_key
      )
    end

    def activate_season(season_key, expected_revision:)
      lifecycle(season_key, "activate", expected_revision)
    end

    def close_season(season_key, expected_revision:)
      lifecycle(season_key, "close", expected_revision)
    end

    def archive_season(season_key, expected_revision:)
      lifecycle(season_key, "archive", expected_revision)
    end

    def retrieve_season_lifecycle(season_key, operation_id)
      @client.get(path(season_key, "/lifecycle/#{encode(operation_id)}"))
    end

    def create_season_plan(season_key, name:, event_keys: nil,
                           source_performance_group_keys: nil, idempotency_key: nil)
      body = selection(event_keys, source_performance_group_keys).merge("name" => name)
      @client.post(path(season_key, "/plans"), body, idempotency_key: idempotency_key,
                                                     retry_policy: :header_replay)
    end

    def retrieve_season_plan(season_key, plan_key)
      @client.get(path(season_key, "/plans/#{encode(plan_key)}"))
    end

    def publish_season_plan(season_key, plan_key, expected_revision:)
      @client.post(path(season_key, "/plans/#{encode(plan_key)}/publish"),
                   { "expectedRevision" => expected_revision })
    end

    def supersede_season_plan(season_key, plan_key, expected_revision:)
      @client.post(path(season_key, "/plans/#{encode(plan_key)}/supersede"),
                   { "expectedRevision" => expected_revision })
    end

    def open_season_sales(season_key, expected_revision:)
      sales(season_key, "open", expected_revision)
    end

    def pause_season_sales(season_key, expected_revision:)
      sales(season_key, "pause", expected_revision)
    end

    def resume_season_sales(season_key, expected_revision:)
      sales(season_key, "resume", expected_revision)
    end

    def end_season_sales(season_key, expected_revision:)
      sales(season_key, "end", expected_revision)
    end

    def duplicate_season_to_live(season_key, event_keys:, name: nil, idempotency_key: nil)
      @client.post(path(season_key, "/duplicate-to-live"),
                   compact({ "eventKeys" => event_keys, "name" => name }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Reveal one show-once browser bearer. This call is deliberately single-attempt.
    def create_season_buyer_access_session(season_key, allowed_origin:, include_public:,
                                           expires_in_seconds: nil, max_quantity: UNSET,
                                           buyer_ref: UNSET)
      body = compact({ "allowedOrigin" => allowed_origin, "includePublic" => include_public,
                       "expiresInSeconds" => expires_in_seconds })
      body.merge!(supplied({ "maxQuantity" => max_quantity, "buyerRef" => buyer_ref }))
      @client.post(path(season_key, "/buyer-access-sessions"), body)
    end

    def list_season_buyer_access_sessions(season_key, limit: nil)
      @client.get(path(season_key, "/buyer-access-sessions"), compact({ "limit" => limit }))
    end

    def revoke_season_buyer_access_session(season_key, session_id)
      @client.delete(path(season_key, "/buyer-access-sessions/#{encode(session_id)}"))
    end

    def retrieve_season_hold(season_key, operation_id)
      @client.get(path(season_key, "/holds/#{encode(operation_id)}"))
    end

    def book_season_hold(season_key, operation_id, book_action_id:, booking_ref:)
      @client.post(path(season_key, "/holds/#{encode(operation_id)}/book"),
                   { "bookActionId" => book_action_id, "bookingRef" => booking_ref })
    end

    def retrieve_season_booking(season_key, action_id)
      @client.get(path(season_key, "/bookings/#{encode(action_id)}"))
    end

    def cancel_season_booking(season_key, action_id, cancel_action_id:, booking_ref:,
                              plan_activation_id:, right_disposition:)
      @client.post(path(season_key, "/bookings/#{encode(action_id)}/cancel"),
                   { "cancelActionId" => cancel_action_id, "bookingRef" => booking_ref,
                     "planActivationId" => plan_activation_id,
                     "rightDisposition" => right_disposition })
    end

    def validate_season_buyer_rehearsal(season_key)
      @client.post(path(season_key, "/buyer-rehearsals/validate"))
    end

    # Import incumbent holders. Each row hash takes "rowId", "holderRef",
    # "priorPlanActivationId", "priorContractRef" and "labels", plus optional
    # "existingBookingRef", "holderEmail" and "holderName".
    def create_season_holder_import(season_key, successor_plan_activation_id:, rows:,
                                    dry_run: UNSET, idempotency_key: nil)
      body = { "successorPlanActivationId" => successor_plan_activation_id, "rows" => rows }
      body.merge!(supplied({ "dryRun" => dry_run }))
      @client.post(path(season_key, "/imports"), body, idempotency_key: idempotency_key,
                                                       retry_policy: :header_replay)
    end

    def retrieve_season_holder_import(season_key, import_id)
      @client.get(path(season_key, "/imports/#{encode(import_id)}"))
    end

    def create_season_renewal_offers(season_key, deadline_at:,
                                     successor_plan_activation_id: nil, contract_ids: nil,
                                     idempotency_key: nil)
      body = compact({ "successorPlanActivationId" => successor_plan_activation_id,
                       "deadlineAt" => deadline_at, "contractIds" => contract_ids })
      @client.post(path(season_key, "/renewal-offers"), body,
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    def list_season_renewal_offers(season_key)
      @client.get(path(season_key, "/renewal-offers"))
    end

    def retrieve_season_renewal_offer(season_key, offer_id)
      @client.get(path(season_key, "/renewal-offers/#{encode(offer_id)}"))
    end

    def extend_season_renewal_offer(season_key, offer_id, deadline_at:)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/extend"),
                   { "deadlineAt" => deadline_at })
    end

    def inspect_season_renewal_offer(season_key, offer_id)
      @client.get(path(season_key, "/renewal-offers/#{encode(offer_id)}/inspect"))
    end

    def commit_season_renewal_offer(season_key, offer_id, commit_action_id:, order_ref:,
                                    booking_ref:, plan_activation_id:)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/commit"),
                   { "commitActionId" => commit_action_id, "orderRef" => order_ref,
                     "bookingRef" => booking_ref, "planActivationId" => plan_activation_id })
    end

    def decline_season_renewal_offer(season_key, offer_id)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/decline"), {})
    end

    def release_season_renewal_offer(season_key, offer_id)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/release"), {})
    end

    def list_season_occurrences(season_key)
      @client.get(path(season_key, "/occurrences"))
    end

    # Amend one date. +kind+ is "reschedule", "replace", "cancel_exception",
    # "postpone" (no new time yet) or "cancel" (the date will not happen). With
    # "cancel" only, +refund+ ("none", "per_date" or "full") refunds the date's
    # SeatLayer orders as a job, and +reason+ is kept on it.
    def create_season_amendment(season_key, event_key:, kind:, starts_at: nil, name: nil,
                                refund: nil, reason: nil, idempotency_key: nil)
      @client.post(path(season_key, "/amendments"),
                   compact({ "eventKey" => event_key, "kind" => kind,
                             "startsAt" => starts_at, "name" => name,
                             "refund" => refund, "reason" => reason }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    def list_season_amendments(season_key)
      @client.get(path(season_key, "/amendments"))
    end

    def retrieve_season_amendment(season_key, amendment_id)
      @client.get(path(season_key, "/amendments/#{encode(amendment_id)}"))
    end

    def retrieve_season_report(season_key)
      @client.get(path(season_key, "/reports"))
    end

    def list_season_operations(season_key)
      @client.get(path(season_key, "/operations"))
    end

    def retrieve_season_support_lookup(season_key, booking_ref: nil, holder_ref: nil)
      @client.get(path(season_key, "/support-lookups"),
                  compact({ "bookingRef" => booking_ref, "holderRef" => holder_ref }))
    end

    def list_season_outbox(season_key)
      @client.get(path(season_key, "/outbox"))
    end

    def replay_season_outbox(season_key, occurrence_id)
      @client.post(path(season_key, "/outbox/#{encode(occurrence_id)}/replay"), {})
    end

    def list_season_audit(season_key)
      @client.get(path(season_key, "/audit"))
    end

    def export_season_support_snapshot(season_key)
      @client.get(path(season_key, "/export"))
    end

    # Dry-run or commit renewal rights derived from a previous Season's holders.
    def create_season_holder_import_from_season(season_key, source_season_id:,
                                                successor_plan_activation_id:, dry_run: UNSET,
                                                idempotency_key: nil)
      body = { "sourceSeasonId" => source_season_id,
               "successorPlanActivationId" => successor_plan_activation_id }
      body.merge!(supplied({ "dryRun" => dry_run }))
      @client.post(path(season_key, "/imports/from-season"), body,
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # List the Season's performances and package membership, in every lifecycle state.
    def list_season_performances(season_key)
      @client.get(path(season_key, "/performances"))
    end

    # Create performances inside a draft Season from a repeat rule. Pass +nil+
    # for +venue+ or +duration_minutes+ to send an explicit JSON null.
    # rubocop:disable-next Metrics/ParameterLists
    def create_season_performances(season_key, title_pattern:, timezone:, repeat:,
                                   first_starts_at: nil, count: nil, dates: nil, venue: UNSET,
                                   duration_minutes: UNSET, region: nil,
                                   attach_to_plan_keys: nil, idempotency_key: nil)
      body = compact({ "titlePattern" => title_pattern, "firstStartsAt" => first_starts_at,
                       "timezone" => timezone, "repeat" => repeat, "count" => count,
                       "dates" => dates, "region" => region,
                       "attachToPlanKeys" => attach_to_plan_keys })
      body.merge!(supplied({ "venue" => venue, "durationMinutes" => duration_minutes }))
      @client.post(path(season_key, "/performances"), body,
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Attach existing events to a draft Season as performances.
    def attach_season_performances(season_key, event_keys:, attach_to_plan_keys: nil,
                                   idempotency_key: nil)
      body = compact({ "eventKeys" => event_keys, "attachToPlanKeys" => attach_to_plan_keys })
      @client.post(path(season_key, "/performances/attach"), body,
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Remove one performance from a draft Season.
    def delete_season_performance(season_key, event_key, idempotency_key: nil)
      @client.mutation_with_header_replay(
        "DELETE", path(season_key, "/performances/#{encode(event_key)}"),
        idempotency_key: idempotency_key
      )
    end

    # Rename a draft package or change the performances it covers.
    def update_season_plan(season_key, plan_key, name: nil, event_keys: nil, idempotency_key: nil)
      @client.mutation_with_header_replay(
        "PATCH", path(season_key, "/plans/#{encode(plan_key)}"),
        compact({ "name" => name, "eventKeys" => event_keys }), idempotency_key: idempotency_key
      )
    end

    # Delete a draft package. The API answers 204, so this returns an empty Hash.
    def delete_season_plan(season_key, plan_key, idempotency_key: nil)
      @client.mutation_with_header_replay(
        "DELETE", path(season_key, "/plans/#{encode(plan_key)}"), idempotency_key: idempotency_key
      )
    end

    # Publish a draft Season. Sends no body.
    def publish_season(season_key, idempotency_key: nil)
      @client.post(path(season_key, "/publish"), nil,
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Run a test checkout against the Season.
    def create_season_checkout_test(season_key, plan_key: nil, quantity: nil, idempotency_key: nil)
      @client.post(path(season_key, "/checkout-tests"),
                   compact({ "planKey" => plan_key, "quantity" => quantity }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # List the Season's test checkouts.
    def list_season_checkout_tests(season_key)
      @client.get(path(season_key, "/checkout-tests"))
    end

    # Replace every price of one package. Each price hash takes "categoryKey" and
    # "unitPrice" (minor units), plus an optional "priceTypeKey": "adult" (the
    # default), "child", "concession", "senior" or "student".
    def replace_season_package_prices(season_key, plan_key, prices:, currency: nil,
                                      idempotency_key: nil)
      @client.mutation_with_header_replay(
        "PUT", path(season_key, "/plans/#{encode(plan_key)}/prices"),
        compact({ "prices" => prices, "currency" => currency }), idempotency_key: idempotency_key
      )
    end

    # List the prices of every package in the Season, each with its
    # "priceTypeKey" and "priceTypeLabel".
    def list_season_prices(season_key)
      @client.get(path(season_key, "/prices"))
    end

    # Add one performance to a package.
    def attach_season_plan_performance(season_key, plan_key, event_key:, idempotency_key: nil)
      @client.post(path(season_key, "/plans/#{encode(plan_key)}/performances"),
                   { "eventKey" => event_key },
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Remove one performance from a package.
    def delete_season_plan_performance(season_key, plan_key, event_key, idempotency_key: nil)
      @client.mutation_with_header_replay(
        "DELETE", path(season_key, "/plans/#{encode(plan_key)}/performances/#{encode(event_key)}"),
        idempotency_key: idempotency_key
      )
    end

    # Mark a performance past so it stops blocking new Season sales.
    def mark_season_performance_past(season_key, event_key, force: nil, idempotency_key: nil)
      @client.post(path(season_key, "/performances/#{encode(event_key)}/past"),
                   compact({ "force" => force }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Return one Season occurrence allocation to ordinary Event inventory.
    # Single-attempt: keep +action_id+ stable and retry it yourself if needed.
    def return_season_occurrence_inventory(season_key, event_key, action_id:, booking_ref:,
                                           plan_activation_id:, labels:, source:)
      @client.post(path(season_key, "/occurrences/#{encode(event_key)}/returns"),
                   { "actionId" => action_id, "bookingRef" => booking_ref,
                     "planActivationId" => plan_activation_id, "labels" => labels,
                     "source" => source })
    end

    # Reclaim returned inventory for a Season occurrence. Single-attempt, like
    # +return_season_occurrence_inventory+.
    def reclaim_season_occurrence_inventory(season_key, event_key, action_id:, return_action_id:,
                                            booking_ref:, plan_activation_id:, labels:, source:)
      @client.post(path(season_key, "/occurrences/#{encode(event_key)}/reclaims"),
                   { "actionId" => action_id, "returnActionId" => return_action_id,
                     "bookingRef" => booking_ref, "planActivationId" => plan_activation_id,
                     "labels" => labels, "source" => source })
    end

    # One page of Season holders. +search+ is sent as the API's +q+ parameter.
    def list_season_holders(season_key, search: nil, status: nil, cursor: nil, limit: nil)
      @client.get(path(season_key, "/holders"),
                  compact({ "q" => search, "status" => status, "cursor" => cursor,
                            "limit" => limit }))
    end

    # Refund a Season order, in full or by +amount_minor+.
    def refund_season_order(season_key, order_id, amount_minor: nil, idempotency_key: nil)
      @client.post(path(season_key, "/orders/#{encode(order_id)}/refund"),
                   compact({ "amountMinor" => amount_minor }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Cancel a Season order.
    def cancel_season_order(season_key, order_id, reason:, note: nil, refund_confirmed: nil,
                            used_tickets_acknowledged: nil, notify_buyer: nil, idempotency_key: nil)
      body = compact({ "reason" => reason, "note" => note, "refundConfirmed" => refund_confirmed,
                       "usedTicketsAcknowledged" => used_tickets_acknowledged,
                       "notifyBuyer" => notify_buyer })
      @client.post(path(season_key, "/orders/#{encode(order_id)}/cancel"), body,
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Cancel one date of a Season order.
    def cancel_season_order_date(season_key, order_id, event_key, action_id: nil,
                                 idempotency_key: nil)
      @client.post(path(season_key, "/orders/#{encode(order_id)}/dates/#{encode(event_key)}/cancel"),
                   compact({ "actionId" => action_id }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Send a Season order's tickets again. Single-attempt: never retried automatically.
    def resend_season_order_tickets(season_key, order_id, email: nil)
      @client.post(path(season_key, "/orders/#{encode(order_id)}/resend"),
                   compact({ "email" => email }))
    end

    # Read the state of hosted renewals for the Season.
    def retrieve_season_hosted_renewals(season_key)
      @client.get(path(season_key, "/renewal-hosted"))
    end

    # Replace a renewal offer's link. The new link is shown once, so this is
    # deliberately single-attempt.
    def rotate_season_renewal_offer_link(season_key, offer_id)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/link"))
    end

    # Set the contact on a renewal offer. Pass +nil+ to send an explicit JSON null.
    def update_season_renewal_offer_contact(season_key, offer_id, email: UNSET, name: UNSET)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/contact"),
                   supplied({ "email" => email, "name" => name }))
    end

    # Send renewal notices, to every open offer or only to +offer_ids+.
    def create_season_renewal_notices(season_key, offer_ids: nil)
      @client.post(path(season_key, "/renewal-notices"), compact({ "offerIds" => offer_ids }))
    end

    # Send one renewal offer again. Single-attempt: never retried automatically.
    def resend_season_renewal_offer(season_key, offer_id)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/resend"))
    end

    # Read the Season's sales report.
    def retrieve_season_sales_report(season_key)
      @client.get(path(season_key, "/reports/sales"))
    end

    # Read the Season's seats report.
    def retrieve_season_seats_report(season_key)
      @client.get(path(season_key, "/reports/seats"))
    end

    # Download the Season's holders as CSV. Returns the raw CSV text.
    def export_season_holders_csv(season_key, search: nil, status: nil)
      @client.get_text(path(season_key, "/reports/holders.csv"),
                       compact({ "q" => search, "status" => status }))
    end

    # Download every Season order SeatLayer took as CSV. Returns the raw CSV text.
    def export_season_orders_csv(season_key)
      @client.get_text(path(season_key, "/reports/orders.csv"))
    end

    # Read the Season's seat counts.
    def retrieve_season_seat_counts(season_key)
      @client.get(path(season_key, "/seat-counts"))
    end

    # Refund every SeatLayer order holding a cancelled date, as a job. +amount+ is
    # "per_date" (the date's share of each order) or "full" (what is left of it).
    # Retried with one Idempotency-Key, which replays the same job.
    def refund_season_performance(season_key, event_key, amount:, reason: nil, idempotency_key: nil)
      @client.post(path(season_key, "/performances/#{encode(event_key)}/refunds"),
                   compact({ "amount" => amount, "reason" => reason }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # List the Season's bulk jobs, newest first (100 at most).
    def list_season_bulk_jobs(season_key)
      @client.get(path(season_key, "/jobs"))
    end

    # Read one bulk job with its counts and up to 500 failed items.
    def retrieve_season_bulk_job(season_key, job_id)
      @client.get(path(season_key, "/jobs/#{encode(job_id)}"))
    end

    private

    def path(season_key, suffix = "")
      "/v1/seasons/#{encode(season_key)}#{suffix}"
    end

    def selection(event_keys, source_performance_group_keys)
      compact({ "eventKeys" => event_keys,
                "sourcePerformanceGroupKeys" => source_performance_group_keys })
    end

    def lifecycle(season_key, action, expected_revision)
      @client.post(path(season_key, "/#{action}"), { "expectedRevision" => expected_revision })
    end

    def sales(season_key, action, expected_revision)
      @client.post(path(season_key, "/sales/#{action}"),
                   { "expectedRevision" => expected_revision })
    end
  end
end
