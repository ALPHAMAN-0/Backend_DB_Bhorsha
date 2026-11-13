-- =============================================================================
-- Bhorsha: post-start verification for schema v2.0.0 (read-only)
-- docker compose exec db psql -U bhorsha -d bhorsha -f /scripts/verify.sql
-- Prints a few demo views, then ends with "ALL CHECKS PASSED" or stops at the first
-- failed assertion.
-- =============================================================================
\set ON_ERROR_STOP on
\pset footer off

\echo '\n== 1. Tables and row counts (expect 13; typeorm_migrations is migration bookkeeping) =='
SELECT c.relname AS table_name,
       (xpath('/row/n/text()',
              query_to_xml(format('SELECT count(*) AS n FROM %I', c.relname), false, true, '')))[1]::text::int AS row_count
  FROM pg_class c
 WHERE c.relkind = 'r' AND c.relnamespace = 'public'::regnamespace
 ORDER BY c.relname;

\echo '\n== 2. Fares for a 10 km trip, in paisa (car: 26000 solo, 19500 shared, ceiling 35700) =='
SELECT vehicle_type,
       base_paisa + round(per_km_paisa * GREATEST(10000 - base_distance_m, 0) / 1000.0)::bigint                 AS solo_paisa,
       round((base_paisa + round(per_km_paisa * GREATEST(10000 - base_distance_m, 0) / 1000.0))
             * (10000 - share_discount_bps) / 10000.0)::bigint                                                    AS shared_paisa,
       ceiling_base_paisa + round(ceiling_per_km_paisa * GREATEST(10000 - base_distance_m, 0) / 1000.0)::bigint AS ceiling_paisa
  FROM fare_rules
 ORDER BY vehicle_type;

\echo '\n== 3. Live rides and their passengers =='
SELECT r.id AS ride, r.status, r.vehicle_type, r.is_shared AS shared, r.seats_total AS total, r.seats_free AS free,
       d.full_name AS driver,
       string_agg(u.full_name || ' (' || p.status || ', ' || p.locked_fare_paisa || ')', ', ' ORDER BY p.id) AS passengers
  FROM rides r
  LEFT JOIN users d            ON d.id = r.driver_id
  JOIN ride_passengers p       ON p.ride_id = r.id
  JOIN users u                 ON u.id = p.rider_id
 WHERE r.status NOT IN ('COMPLETED', 'CANCELLED')
 GROUP BY r.id, d.full_name
 ORDER BY r.id;

\echo '\n== 4. Last-seat race on ride 4: one free seat, two PENDING requests =='
SELECT j.id AS request, j.initiated_by, u.full_name AS rider, j.seats, j.quoted_fare_paisa, j.status,
       COALESCE(j.ride_id, o.ride_id) AS target_ride
  FROM join_requests j
  JOIN users u              ON u.id = j.rider_id
  LEFT JOIN route_offers o  ON o.id = j.route_offer_id
 WHERE j.status = 'PENDING'
 ORDER BY j.id;

\echo '\n== 5. Trust: cases -> strikes -> appeals (issuer never decides the appeal) =='
SELECT c.id AS case_id, c.type, c.status AS case_status, subj.full_name AS subject,
       s.id AS strike_id, iss.full_name AS issued_by, a.status AS appeal, dec.full_name AS decided_by
  FROM support_cases c
  LEFT JOIN users subj ON subj.id = c.subject_id
  LEFT JOIN strikes s  ON s.case_id = c.id
  LEFT JOIN users iss  ON iss.id = s.issued_by
  LEFT JOIN appeals a  ON a.strike_id = s.id
  LEFT JOIN users dec  ON dec.id = a.decided_by
 ORDER BY c.id;

\echo '\n== 6. Assertions =='
DO $$
DECLARE
  n int;
  missing text;
BEGIN
  -- Shape ---------------------------------------------------------------------
  SELECT count(*) INTO n FROM pg_class
   WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace AND relname <> 'typeorm_migrations';
  ASSERT n = 13, format('expected 13 tables, found %s', n);

  ASSERT EXISTS (SELECT 1 FROM typeorm_migrations WHERE name = 'SchemaBaseline1794441600000'),
         'the schema baseline must be recorded in typeorm_migrations';

  -- The API's exception filter maps these names to HTTP responses: they must exist.
  SELECT string_agg(x.name, ', ') INTO missing
    FROM unnest(ARRAY[
           'uq_users_phone', 'uq_users_email', 'uq_driver_profiles_licence_no', 'uq_vehicles_reg_no_active',
           'ck_rides_seats_free', 'ck_rides_solo_no_free_seats', 'uq_rides_one_active_per_driver',
           'uq_ride_passengers_one_live_seat_per_rider', 'ck_ride_passengers_fare_within_ceiling',
           'ck_fare_rules_within_ceiling', 'ck_join_requests_one_target', 'fk_rides_vehicle',
           'fk_strikes_case_subject', 'uq_strikes_case_user_live', 'uq_appeals_strike', 'ck_audit_logs_no_secrets',
           'trg_rides_status_transition', 'trg_ride_passengers_status_transition', 'trg_join_requests_status_transition',
           'trg_rides_update_guards', 'trg_fare_rules_regulation_frozen', 'trg_appeals_separation_of_duties',
           'trg_audit_logs_append_only']) AS x(name)
   WHERE NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = x.name)
     AND NOT EXISTS (SELECT 1 FROM pg_class      WHERE relname = x.name AND relkind = 'i')
     AND NOT EXISTS (SELECT 1 FROM pg_trigger    WHERE tgname  = x.name);
  ASSERT missing IS NULL, format('missing constraints, indexes or triggers: %s', missing);

  -- Every 'FROM>TO' argument of a status-transition trigger names real enum labels.
  -- A typo would silently block a legal step, so the build fails on it instead.
  SELECT string_agg(t.tgname || ': ' || a.arg, ', ') INTO missing
    FROM pg_trigger t
    JOIN pg_attribute col ON col.attrelid = t.tgrelid AND col.attname = 'status'
   CROSS JOIN LATERAL unnest(string_to_array(encode(t.tgargs, 'escape'), '\000')) AS a(arg)
   WHERE t.tgname LIKE '%status_transition' AND a.arg <> ''
     AND (a.arg !~ '^[A-Z_]+>[A-Z_]+$'
          OR split_part(a.arg, '>', 1) NOT IN (SELECT enumlabel FROM pg_enum WHERE enumtypid = col.atttypid)
          OR split_part(a.arg, '>', 2) NOT IN (SELECT enumlabel FROM pg_enum WHERE enumtypid = col.atttypid));
  ASSERT missing IS NULL, format('invalid state-machine edges: %s', missing);
  ASSERT (SELECT count(*) FROM pg_trigger WHERE tgname LIKE '%status_transition') = 3,
         'expected status-transition triggers on rides, ride_passengers and join_requests';

  -- Pricing ---------------------------------------------------------------------
  ASSERT (SELECT base_paisa + round(per_km_paisa * GREATEST(10000 - base_distance_m, 0) / 1000.0)
            FROM fare_rules WHERE vehicle_type = 'CAR') = 26000,
         'car fare for 10 km should be 26000 paisa (Tk 260)';
  ASSERT (SELECT ceiling_base_paisa + round(ceiling_per_km_paisa * GREATEST(10000 - base_distance_m, 0) / 1000.0)
            FROM fare_rules WHERE vehicle_type = 'CAR') = 35700,
         'car ceiling for 10 km should be 35700 paisa (Tk 357)';
  ASSERT (SELECT locked_fare_paisa FROM ride_passengers WHERE id = 2) = 19500,
         'shared 10 km car fare (ride 2) should be 19500 paisa (Tk 195)';

  -- The pricing snapshot is the evidence in a dispute: it must agree with the columns.
  ASSERT NOT EXISTS (SELECT 1 FROM ride_passengers
                      WHERE (pricing_snapshot->>'farePaisa')::bigint    <> locked_fare_paisa
                         OR (pricing_snapshot->>'ceilingPaisa')::bigint <> ceiling_paisa),
         'every passenger snapshot must match its locked fare and ceiling';
  ASSERT NOT EXISTS (SELECT 1 FROM join_requests
                      WHERE (pricing_snapshot->>'farePaisa')::bigint    <> quoted_fare_paisa
                         OR (pricing_snapshot->>'ceilingPaisa')::bigint <> ceiling_paisa),
         'every join request snapshot must match its quote and ceiling';
  -- A seat created by a join request keeps the fare the rider agreed to.
  ASSERT NOT EXISTS (SELECT 1 FROM ride_passengers p JOIN join_requests j ON j.id = p.join_request_id
                      WHERE p.locked_fare_paisa <> j.quoted_fare_paisa OR j.status <> 'ACCEPTED'),
         'a seat from a join request must keep the quoted fare, and the request must be ACCEPTED';

  -- Seats -----------------------------------------------------------------------
  -- Shared rides: free seats = total seats - seats of passengers waiting or aboard.
  ASSERT NOT EXISTS (
    SELECT 1 FROM rides r
     WHERE r.is_shared AND r.status NOT IN ('COMPLETED', 'CANCELLED')
       AND r.seats_free <> r.seats_total - (SELECT COALESCE(sum(p.seats), 0) FROM ride_passengers p
                                              WHERE p.ride_id = r.id AND p.status IN ('CONFIRMED', 'PICKED_UP'))),
    'seat accounting: seats_free must equal seats_total minus live passenger seats on every live shared ride';
  ASSERT NOT EXISTS (
    SELECT 1 FROM rides r
     WHERE NOT r.is_shared
       AND (SELECT count(*) FROM ride_passengers p WHERE p.ride_id = r.id AND p.status IN ('CONFIRMED', 'PICKED_UP')) > 1),
    'a solo ride never has a co-rider';
  ASSERT NOT EXISTS (
    SELECT 1 FROM rides r
     WHERE r.status IN ('COMPLETED', 'CANCELLED')
       AND EXISTS (SELECT 1 FROM ride_passengers p WHERE p.ride_id = r.id AND p.status IN ('CONFIRMED', 'PICKED_UP'))),
    'a finished ride must not leave a passenger waiting or aboard';
  ASSERT NOT EXISTS (
    SELECT 1 FROM rides r
     WHERE r.status NOT IN ('COMPLETED', 'CANCELLED')
       AND NOT EXISTS (SELECT 1 FROM ride_passengers p WHERE p.ride_id = r.id AND p.status IN ('CONFIRMED', 'PICKED_UP'))),
    'every live ride has at least one passenger';

  -- Demo story --------------------------------------------------------------------
  ASSERT (SELECT seats_free FROM rides WHERE id = 4) = 1, 'ride 4 should have exactly one free seat';
  ASSERT (SELECT count(*) FROM join_requests j LEFT JOIN route_offers o ON o.id = j.route_offer_id
           WHERE j.status = 'PENDING' AND COALESCE(j.ride_id, o.ride_id) = 4) = 2,
         'two PENDING requests should race for the last seat on ride 4';

  -- Trust ---------------------------------------------------------------------------
  ASSERT NOT EXISTS (SELECT 1 FROM appeals a JOIN strikes s ON s.id = a.strike_id WHERE a.decided_by = s.issued_by),
         'separation of duties: no appeal is decided by the officer who issued the strike';
  -- Threshold count (section 16): ACTIVE, unexpired, and not under a PENDING appeal.
  ASSERT (SELECT count(*) FROM strikes s
           WHERE s.user_id = 5 AND s.status = 'ACTIVE' AND s.expires_at > now()
             AND NOT EXISTS (SELECT 1 FROM appeals a WHERE a.strike_id = s.id AND a.status = 'PENDING')) = 1,
         'driver 5 should have one counting strike';
  ASSERT (SELECT count(*) FROM strikes s
           WHERE s.user_id = 4 AND s.status = 'ACTIVE' AND s.expires_at > now()
             AND NOT EXISTS (SELECT 1 FROM appeals a WHERE a.strike_id = s.id AND a.status = 'PENDING')) = 0,
         'rider 4''s strike is under appeal, so it must not count';

  -- Ratings are computed on read.
  ASSERT (SELECT round(avg(stars), 2) FROM ratings WHERE to_user_id = 6) = 4.50, 'driver 6 should average 4.50 stars';

  RAISE NOTICE 'ALL CHECKS PASSED';
END $$;
