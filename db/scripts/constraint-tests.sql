-- =============================================================================
-- Bhorsha: database guarantees for schema v2.0.0, mapped to the architecture document.
-- Each test runs in its own sub-transaction and is ALWAYS rolled back, so every test sees
-- the untouched seed and the order doesn't matter. Safe to run at any time:
--   docker compose exec db psql -U bhorsha -d bhorsha -f /scripts/constraint-tests.sql
-- Output: one PASS/FAIL line per test, then "N passed, M failed".
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off
\pset tuples_only on

BEGIN;

-- The statement must fail with the expected SQLSTATE and, when given, the expected
-- constraint name: the name is what the API's exception filter maps to a response.
CREATE FUNCTION pg_temp.expect_error(label text, stmt text, expected_state text, expected_constraint text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_constraint text;
BEGIN
  BEGIN
    EXECUTE stmt;
    RAISE EXCEPTION 'bhorsha_test_rollback';  -- undo a statement that wrongly succeeded
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF SQLERRM = 'bhorsha_test_rollback' THEN
      RETURN 'FAIL  ' || label || '  (no error raised)';
    ELSIF SQLSTATE = expected_state AND (expected_constraint IS NULL OR v_constraint = expected_constraint) THEN
      RETURN 'PASS  ' || label || COALESCE('  [' || expected_constraint || ']', '');
    END IF;
    RETURN 'FAIL  ' || label || '  (expected ' || expected_state || COALESCE(' ' || expected_constraint, '')
        || ', got ' || SQLSTATE || COALESCE(' ' || NULLIF(v_constraint, ''), '') || ': ' || SQLERRM || ')';
  END;
END $$;

-- The statement must succeed. Its changes are rolled back afterwards.
CREATE FUNCTION pg_temp.expect_ok(label text, stmt text)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
    RAISE EXCEPTION 'bhorsha_test_rollback';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'bhorsha_test_rollback' THEN
      RETURN 'PASS  ' || label;
    END IF;
    RETURN 'FAIL  ' || label || '  (' || SQLSTATE || ': ' || SQLERRM || ')';
  END;
END $$;

CREATE TEMP TABLE results(id serial, line text) ON COMMIT DROP;

INSERT INTO results(line) SELECT r FROM (VALUES
  -- -------------------------------------------------------------------------
  -- Seats and sharing
  -- -------------------------------------------------------------------------
  (pg_temp.expect_error('NFR-03   last seat: taking 2 seats when 1 is free is refused',
     $q$UPDATE rides SET seats_free = seats_free - 2 WHERE id = 4$q$, '23514', 'ck_rides_seats_free')),
  (pg_temp.expect_error('FR-SH-1  a solo ride never offers a seat to a co-rider',
     $q$UPDATE rides SET seats_free = 1 WHERE id = 7$q$, '23514', 'ck_rides_solo_no_free_seats')),
  (pg_temp.expect_error('FR-SH-1  bikes are never shared',
     $q$INSERT INTO rides (vehicle_type, is_shared, seats_total, seats_free) VALUES ('BIKE', true, 1, 0)$q$, '23514', 'ck_rides_bike_solo')),
  (pg_temp.expect_error('FR-SH-1  a shared booking is 1 or 2 seats',
     $q$UPDATE join_requests SET seats = 3 WHERE id = 4$q$, '23514', 'ck_join_requests_seats')),

  -- -------------------------------------------------------------------------
  -- Races: exactly one winner
  -- -------------------------------------------------------------------------
  (pg_temp.expect_error('FR-HO-2  a driver cannot hold two active rides',
     $q$UPDATE rides SET status = 'ACCEPTED', driver_id = 6, vehicle_id = 2, accepted_at = now() WHERE id = 5$q$, '23505', 'uq_rides_one_active_per_driver')),
  (pg_temp.expect_error('NFR-03   an assigned driver is never replaced',
     $q$UPDATE rides SET driver_id = 5, vehicle_id = 1 WHERE id = 4$q$, '23514', 'ck_rides_driver_locked')),
  (pg_temp.expect_ok('NFR-03   accept race: the losing conditional accept updates 0 rows',
     $q$DO $t$
        DECLARE n int;
        BEGIN
          UPDATE rides SET status = 'ACCEPTED', driver_id = 5, vehicle_id = 1, accepted_at = now()
           WHERE id = 5 AND status = 'REQUESTED' AND version = 1;
          GET DIAGNOSTICS n = ROW_COUNT;
          IF n <> 1 THEN RAISE EXCEPTION 'the first accept should win'; END IF;
          UPDATE rides SET status = 'ACCEPTED', driver_id = 6, vehicle_id = 2, accepted_at = now()
           WHERE id = 5 AND status = 'REQUESTED' AND version = 1;
          GET DIAGNOSTICS n = ROW_COUNT;
          IF n <> 0 THEN RAISE EXCEPTION 'the second accept must update 0 rows'; END IF;
        END $t$$q$)),
  (pg_temp.expect_error('FR-SH-6  a rider cannot hold two live seats',
     $q$INSERT INTO ride_passengers (ride_id, rider_id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                                     distance_m, locked_fare_paisa, ceiling_paisa, pricing_snapshot, pickup_pin)
        VALUES (4, 3, 1, 23.817, 90.420, 23.7806, 90.4167, 6000, 12000, 22100, '{}', '1234')$q$, '23505', 'uq_ride_passengers_one_live_seat_per_rider')),

  -- -------------------------------------------------------------------------
  -- State machines (any out-of-order step is refused -> 409)
  -- -------------------------------------------------------------------------
  (pg_temp.expect_error('Ride:      a ride cannot finish while a passenger is waiting or aboard',
     $q$UPDATE rides SET status = 'COMPLETED', completed_at = now() WHERE id = 4$q$, '23514', 'ck_rides_close_with_live_passengers')),
  (pg_temp.expect_error('Ride:      COMPLETED cannot go back to IN_PROGRESS',
     $q$UPDATE rides SET status = 'IN_PROGRESS' WHERE id = 1$q$, '23514', 'trg_rides_status_transition')),
  (pg_temp.expect_error('Ride:      the trip cannot start before the driver arrives',
     $q$UPDATE rides SET status = 'IN_PROGRESS', started_at = now() WHERE id = 7$q$, '23514', 'trg_rides_status_transition')),
  (pg_temp.expect_error('Passenger: DROPPED cannot be picked up again',
     $q$UPDATE ride_passengers SET status = 'PICKED_UP' WHERE id = 1$q$, '23514', 'trg_ride_passengers_status_transition')),
  (pg_temp.expect_error('Passenger: pickup needs the driver to have arrived',
     $q$UPDATE ride_passengers SET status = 'PICKED_UP', picked_up_at = now() WHERE id = 9$q$, '23514', 'ck_ride_passengers_picked_up')),
  (pg_temp.expect_error('Passenger: NO_SHOW is only possible after the driver arrived',
     $q$UPDATE ride_passengers SET status = 'NO_SHOW', cancelled_at = now() WHERE id = 9$q$, '23514', 'ck_ride_passengers_no_show')),
  (pg_temp.expect_error('Request:   an accepted join request cannot be declined',
     $q$UPDATE join_requests SET status = 'DECLINED', decided_at = now() WHERE id = 3$q$, '23514', 'trg_join_requests_status_transition')),
  (pg_temp.expect_error('Request:   targets a ride or a route offer, never both',
     $q$UPDATE join_requests SET ride_id = 4 WHERE id = 4$q$, '23514', 'ck_join_requests_one_target')),

  -- -------------------------------------------------------------------------
  -- Legal Fare Guard
  -- -------------------------------------------------------------------------
  (pg_temp.expect_error('FR-PR-2  a car tariff above the legal ceiling is refused',
     $q$UPDATE fare_rules SET per_km_paisa = 4000 WHERE vehicle_type = 'CAR'$q$, '23514', 'ck_fare_rules_within_ceiling')),
  (pg_temp.expect_error('FR-PR-2  the ceiling is regulation: an admin cannot raise it',
     $q$UPDATE fare_rules SET ceiling_per_km_paisa = 5000 WHERE vehicle_type = 'CAR'$q$, '23514', 'ck_fare_rules_regulation_frozen')),
  (pg_temp.expect_error('FR-PR-2  a locked fare above its ceiling is refused',
     $q$UPDATE ride_passengers SET locked_fare_paisa = 40000 WHERE id = 1$q$, '23514', 'ck_ride_passengers_fare_within_ceiling')),
  (pg_temp.expect_ok('FR-PR-3  an admin can still change the tariff below the ceiling',
     $q$UPDATE fare_rules SET per_km_paisa = 2400, updated_by = 1 WHERE vehicle_type = 'CAR'$q$)),

  -- -------------------------------------------------------------------------
  -- Trust and safety
  -- -------------------------------------------------------------------------
  (pg_temp.expect_error('FR-TS-4  the officer who issued a strike cannot decide its appeal',
     $q$UPDATE appeals SET status = 'REJECTED', decided_by = 10, decision_reason = 'Strike stands.', decided_at = now()
         WHERE id = 2$q$, '23514', 'ck_appeals_separation_of_duties')),
  (pg_temp.expect_ok('FR-TS-4  a different officer can decide it',
     $q$UPDATE appeals SET status = 'REJECTED', decided_by = 2, decision_reason = 'Strike stands.', decided_at = now()
         WHERE id = 2$q$)),
  (pg_temp.expect_error('FR-TS-3  a strike can only name the subject of its case',
     $q$INSERT INTO strikes (user_id, case_id, issued_by, reason, expires_at)
        VALUES (3, 1, 2, 'Wrong person', now() + interval '90 days')$q$, '23503', 'fk_strikes_case_subject')),
  (pg_temp.expect_error('FR-TS-3  one standing strike per person per case',
     $q$INSERT INTO strikes (user_id, case_id, issued_by, reason, expires_at)
        VALUES (5, 1, 2, 'Duplicate click', now() + interval '90 days')$q$, '23505', 'uq_strikes_case_user_live')),
  (pg_temp.expect_error('FR-TS-3  a strike can be appealed only once',
     $q$INSERT INTO appeals (strike_id, statement) VALUES (1, 'Second try')$q$, '23505', 'uq_appeals_strike')),
  (pg_temp.expect_error('FR-TS-2  a case decision needs a written resolution',
     $q$UPDATE support_cases SET status = 'DISMISSED', assigned_to = 2, resolved_at = now() WHERE id = 3$q$, '23514', 'ck_support_cases_decision')),

  -- -------------------------------------------------------------------------
  -- Fleet and identity
  -- -------------------------------------------------------------------------
  (pg_temp.expect_error('Fleet:    a ride can only use its own driver''s vehicle',
     $q$UPDATE rides SET status = 'ACCEPTED', driver_id = 5, vehicle_id = 2, accepted_at = now() WHERE id = 5$q$, '23503', 'fk_rides_vehicle')),
  (pg_temp.expect_error('Fleet:    the vehicle must have the requested type',
     $q$UPDATE rides SET status = 'ACCEPTED', driver_id = 5, vehicle_id = 6, accepted_at = now() WHERE id = 5$q$, '23503', 'fk_rides_vehicle')),
  (pg_temp.expect_error('Fleet:    only a verified driver can go online',
     $q$UPDATE driver_profiles SET status = 'ONLINE' WHERE user_id = 8$q$, '23514', 'ck_driver_profiles_online_verified')),
  (pg_temp.expect_error('Fleet:    a registration number belongs to one active vehicle',
     $q$INSERT INTO vehicles (driver_id, type, reg_no, seats) VALUES (9, 'CNG', 'dhaka metro-ga 11-2345', 2)$q$, '23505', 'uq_vehicles_reg_no_active')),
  (pg_temp.expect_ok('Fleet:    a sold (soft-deleted) vehicle can be registered again',
     $q$INSERT INTO vehicles (driver_id, type, reg_no, seats) VALUES (7, 'BIKE', 'DHAKA METRO-HA 12-3344', 1)$q$)),
  (pg_temp.expect_error('Identity: phone must be a Bangladesh mobile in E.164 form',
     $q$INSERT INTO users (full_name, phone, password_hash, role) VALUES ('Test', '01711000099', 'x', 'RIDER')$q$, '23514', 'ck_users_phone_format')),
  (pg_temp.expect_error('Identity: email is stored lower-case',
     $q$INSERT INTO users (full_name, phone, email, password_hash, role)
        VALUES ('Test', '+8801711000099', 'Mixed@Case.test', 'x', 'RIDER')$q$, '23514', 'ck_users_email_format')),
  (pg_temp.expect_error('Identity: a phone number registers only once',
     $q$INSERT INTO users (full_name, phone, password_hash, role) VALUES ('Test', '+8801711000003', 'x', 'RIDER')$q$, '23505', 'uq_users_phone')),
  (pg_temp.expect_error('Identity: ids come from the database, never from the client',
     $q$INSERT INTO users (id, full_name, phone, password_hash, role)
        VALUES (99, 'Test', '+8801711000099', 'x', 'RIDER')$q$, '428C9')),
  (pg_temp.expect_error('TC-20    coordinates out of range are refused',
     $q$UPDATE driver_profiles SET last_lat = 123, last_lng = 90.4, last_location_at = now() WHERE user_id = 5$q$, '23514', 'ck_geo_lat_range')),

  -- -------------------------------------------------------------------------
  -- Audit log
  -- -------------------------------------------------------------------------
  (pg_temp.expect_error('FR-OP-2  audit log is append-only (UPDATE blocked)',
     $q$UPDATE audit_logs SET action = 'TAMPERED' WHERE id = 1$q$, '42501')),
  (pg_temp.expect_error('FR-OP-2  audit log is append-only (DELETE blocked)',
     $q$DELETE FROM audit_logs WHERE id = 1$q$, '42501')),
  (pg_temp.expect_error('NFR-07   the audit log never stores a password',
     $q$INSERT INTO audit_logs (user_id, action, entity, new_value)
        VALUES (3, 'POST /auth/login', 'users', '{"phone":"+8801711000003","password":"Bhorsha@123"}')$q$, '23514', 'ck_audit_logs_no_secrets')),

  -- -------------------------------------------------------------------------
  -- Whole flows, written the way the API must run them (section 12 and 26)
  -- -------------------------------------------------------------------------
  (pg_temp.expect_ok('Seat transaction: Tanvir takes the last seat on ride 4 through offer 1',
     $q$DO $t$
        DECLARE j join_requests%ROWTYPE; r rides%ROWTYPE; n int;
        BEGIN
          SELECT * INTO j FROM join_requests WHERE id = 4;
          PERFORM 1 FROM route_offers WHERE id = j.route_offer_id FOR UPDATE;            -- 1. lock the offer
          SELECT rd.* INTO r FROM rides rd JOIN route_offers o ON o.ride_id = rd.id
           WHERE o.id = j.route_offer_id FOR UPDATE OF rd;                                -- 2. lock the ride
          IF NOT (r.is_shared AND r.status IN ('ACCEPTED', 'ARRIVED', 'IN_PROGRESS') AND r.seats_free >= j.seats) THEN
            RAISE EXCEPTION 'Seat no longer available';                                   -- 3. check
          END IF;
          INSERT INTO ride_passengers (ride_id, rider_id, join_request_id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                                       distance_m, locked_fare_paisa, ceiling_paisa, pricing_snapshot, pickup_pin)
          VALUES (r.id, j.rider_id, j.id, j.seats, j.pickup_lat, j.pickup_lng, j.drop_lat, j.drop_lng,
                  j.distance_m, j.quoted_fare_paisa, j.ceiling_paisa, j.pricing_snapshot, '4242');  -- 5. seat
          UPDATE rides SET seats_free = seats_free - j.seats WHERE id = r.id;            -- 6. count
          UPDATE join_requests SET status = 'ACCEPTED', decided_at = now()
           WHERE id = j.id AND status = 'PENDING' AND expires_at > now();                -- 7. consent
          GET DIAGNOSTICS n = ROW_COUNT;
          IF n <> 1 THEN RAISE EXCEPTION 'join request was already answered'; END IF;
          IF (SELECT seats_free FROM rides WHERE id = r.id) <> 0 THEN RAISE EXCEPTION 'ride 4 should be full'; END IF;
          IF (SELECT version FROM rides WHERE id = r.id) <> r.version + 1 THEN RAISE EXCEPTION 'version not bumped'; END IF;
        END $t$$q$)),
  (pg_temp.expect_error('Last-seat race: after the seat is taken, the second accept rolls back (no seat left)',
     $q$DO $t$
        BEGIN
          -- Tanvir's request takes the last seat...
          INSERT INTO ride_passengers (ride_id, rider_id, join_request_id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                                       distance_m, locked_fare_paisa, ceiling_paisa, pricing_snapshot, pickup_pin)
          SELECT 4, rider_id, id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                 distance_m, quoted_fare_paisa, ceiling_paisa, pricing_snapshot, '4242'
            FROM join_requests WHERE id = 4;
          UPDATE rides SET seats_free = seats_free - 1 WHERE id = 4;
          UPDATE join_requests SET status = 'ACCEPTED', decided_at = now() WHERE id = 4;
          -- ...then Nusrat accepts Jamal's invite. Even if the app skipped its seat check,
          -- the database refuses the oversold seat and the whole transaction rolls back.
          UPDATE ride_passengers SET status = 'CANCELLED', cancelled_at = now() WHERE id = 7;
          UPDATE rides SET status = 'CANCELLED', cancelled_at = now(), cancel_reason = 'JOINED_ANOTHER_RIDE' WHERE id = 5;
          INSERT INTO ride_passengers (ride_id, rider_id, join_request_id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                                       distance_m, locked_fare_paisa, ceiling_paisa, pricing_snapshot, pickup_pin)
          SELECT 4, rider_id, id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                 distance_m, quoted_fare_paisa, ceiling_paisa, pricing_snapshot, '5353'
            FROM join_requests WHERE id = 5;
          UPDATE rides SET seats_free = seats_free - 1 WHERE id = 4;
        END $t$$q$, '23514', 'ck_rides_seats_free')),
  (pg_temp.expect_ok('Core feature: Nusrat accepts Jamal''s invite; her own request is cancelled first',
     $q$DO $t$
        DECLARE n int;
        BEGIN
          PERFORM 1 FROM rides WHERE id IN (4, 5) ORDER BY id FOR UPDATE;               -- both rides, id order
          UPDATE ride_passengers SET status = 'CANCELLED', cancelled_at = now()
           WHERE ride_id = 5 AND rider_id = 3 AND status = 'CONFIRMED';                   -- her waiting seat...
          UPDATE rides SET status = 'CANCELLED', cancelled_at = now(), cancel_reason = 'JOINED_ANOTHER_RIDE'
           WHERE id = 5 AND status = 'REQUESTED';                                         -- ...then her ride
          GET DIAGNOSTICS n = ROW_COUNT;
          IF n <> 1 THEN RAISE EXCEPTION 'her request was no longer waiting'; END IF;
          INSERT INTO ride_passengers (ride_id, rider_id, join_request_id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                                       distance_m, locked_fare_paisa, ceiling_paisa, pricing_snapshot, pickup_pin)
          SELECT ride_id, rider_id, id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                 distance_m, quoted_fare_paisa, ceiling_paisa, pricing_snapshot, '5353'
            FROM join_requests WHERE id = 5;
          UPDATE rides SET seats_free = seats_free - 1 WHERE id = 4;
          UPDATE join_requests SET status = 'ACCEPTED', decided_at = now()
           WHERE id = 5 AND status = 'PENDING' AND expires_at > now();
          GET DIAGNOSTICS n = ROW_COUNT;
          IF n <> 1 THEN RAISE EXCEPTION 'the invite was already answered'; END IF;
        END $t$$q$)),
  (pg_temp.expect_error('Order matters: seating her before cancelling her own request is refused',
     $q$INSERT INTO ride_passengers (ride_id, rider_id, join_request_id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                                     distance_m, locked_fare_paisa, ceiling_paisa, pricing_snapshot, pickup_pin)
        SELECT ride_id, rider_id, id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
               distance_m, quoted_fare_paisa, ceiling_paisa, pricing_snapshot, '5353'
          FROM join_requests WHERE id = 5$q$, '23505', 'uq_ride_passengers_one_live_seat_per_rider')),
  (pg_temp.expect_ok('Heading home: the first accepted join creates the shared ride (offer 2)',
     $q$DO $t$
        DECLARE o route_offers%ROWTYPE; j join_requests%ROWTYPE; v_ride int;
        BEGIN
          SELECT * INTO j FROM join_requests WHERE id = 6;
          SELECT * INTO o FROM route_offers WHERE id = j.route_offer_id FOR UPDATE;       -- serialises first joins
          IF o.ride_id IS NULL THEN
            INSERT INTO rides (vehicle_type, is_shared, seats_total, seats_free, status, driver_id, vehicle_id, accepted_at)
            VALUES (o.vehicle_type, true, o.seats_offered, o.seats_offered, 'ACCEPTED', o.driver_id, o.vehicle_id, now())
            RETURNING id INTO v_ride;
            UPDATE route_offers SET ride_id = v_ride WHERE id = o.id;
          ELSE
            v_ride := o.ride_id;
          END IF;
          INSERT INTO ride_passengers (ride_id, rider_id, join_request_id, seats, pickup_lat, pickup_lng, drop_lat, drop_lng,
                                       distance_m, locked_fare_paisa, ceiling_paisa, pricing_snapshot, pickup_pin)
          VALUES (v_ride, j.rider_id, j.id, j.seats, j.pickup_lat, j.pickup_lng, j.drop_lat, j.drop_lng,
                  j.distance_m, j.quoted_fare_paisa, j.ceiling_paisa, j.pricing_snapshot, '6464');
          UPDATE rides SET seats_free = seats_free - j.seats WHERE id = v_ride;
          UPDATE join_requests SET status = 'ACCEPTED', decided_at = now() WHERE id = j.id AND status = 'PENDING';
        END $t$$q$)),
  (pg_temp.expect_ok('Driver flow: arrive, pickup with PIN, drop off, complete (ride 7)',
     $q$DO $t$
        BEGIN
          UPDATE rides SET status = 'ARRIVED' WHERE id = 7 AND status = 'ACCEPTED';
          UPDATE ride_passengers SET arrived_at = now() WHERE id = 9;
          UPDATE ride_passengers SET status = 'PICKED_UP', picked_up_at = now()
           WHERE id = 9 AND status = 'CONFIRMED' AND pickup_pin = '9150';
          UPDATE rides SET status = 'IN_PROGRESS', started_at = now() WHERE id = 7 AND status = 'ARRIVED';
          UPDATE ride_passengers SET status = 'DROPPED', dropped_at = now() WHERE id = 9 AND status = 'PICKED_UP';
          UPDATE rides SET status = 'COMPLETED', completed_at = now() WHERE id = 7 AND status = 'IN_PROGRESS';
          IF (SELECT status FROM rides WHERE id = 7) <> 'COMPLETED' THEN RAISE EXCEPTION 'ride 7 did not complete'; END IF;
        END $t$$q$)),
  (pg_temp.expect_ok('Shared ride: each drop-off frees its seat; the ride completes after the last one',
     $q$DO $t$
        BEGIN
          UPDATE ride_passengers SET status = 'DROPPED', dropped_at = now() WHERE id = 5 AND status = 'PICKED_UP';
          UPDATE rides SET seats_free = seats_free + 1 WHERE id = 4;
          UPDATE ride_passengers SET arrived_at = now() WHERE id = 6;
          UPDATE ride_passengers SET status = 'PICKED_UP', picked_up_at = now() WHERE id = 6 AND pickup_pin = '3391';
          UPDATE ride_passengers SET status = 'DROPPED', dropped_at = now() WHERE id = 6 AND status = 'PICKED_UP';
          UPDATE rides SET seats_free = seats_free + 1 WHERE id = 4;
          UPDATE rides SET status = 'COMPLETED', completed_at = now() WHERE id = 4 AND status = 'IN_PROGRESS';
          IF (SELECT seats_free FROM rides WHERE id = 4) <> 3 THEN RAISE EXCEPTION 'all seats should be free'; END IF;
        END $t$$q$)),
  (pg_temp.expect_ok('Rider cancels: the seat first, then the empty ride (ride 5)',
     $q$DO $t$
        BEGIN
          UPDATE ride_passengers SET status = 'CANCELLED', cancelled_at = now() WHERE id = 7 AND status = 'CONFIRMED';
          UPDATE rides SET status = 'CANCELLED', cancelled_at = now(), cancel_reason = 'RIDER_CANCELLED'
           WHERE id = 5 AND status = 'REQUESTED';
        END $t$$q$))
) AS t(r);

SELECT line FROM results ORDER BY id;
SELECT format('%s passed, %s failed',
              count(*) FILTER (WHERE line LIKE 'PASS%'),
              count(*) FILTER (WHERE line LIKE 'FAIL%'))
  FROM results;

ROLLBACK;
