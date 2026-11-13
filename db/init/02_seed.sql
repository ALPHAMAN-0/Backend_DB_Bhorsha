-- =============================================================================
-- Bhorsha: demo seed for schema v2.0.0 (development and demo images only; never production)
--
-- Built around the course-release demo (Architecture v3.1, section 26):
--   ride 1  solo car, 10 km, completed. Driver demanded Tk 300 against a locked Tk 260:
--           case upheld, strike issued by Farhana, appeal rejected by Mahmud.
--   ride 2  shared car, completed. Sadia joined through Jamal's invite (the core feature).
--           Co-rider complaint: strike on a RIDER (Tanvir), appeal still pending.
--   ride 3  solo bike, completed, with an OPEN safety case in the support queue.
--   ride 4  shared car IN PROGRESS with ONE seat left and two PENDING requests racing for
--           it: Tanvir's request through Jamal's route offer, and Jamal's invite to Nusrat.
--   ride 5  Nusrat's REQUESTED shared booking, visible in GET /rides/open for Karim.
--   ride 6  CNG ride the rider cancelled before anyone accepted.
--   ride 7  solo bike ACCEPTED: run arrive -> pickup with PIN 9150 -> drop-off.
--   offer 2 Abul is heading home in a CNG with no ride yet; Tanvir asked to join.
--
-- Fares are paisa (1 Tk = 100 paisa) and are COMPUTED from fare_rules by
-- pg_temp.fare_quote below, never typed by hand. 10 km by car: 26000 solo,
-- 19500 shared, legal ceiling 35700.
-- Timestamps are relative to now(), so the data is fresh whenever a container is created.
-- Demo request windows are 2 hours (the app uses 12 s and 60 s) so you can answer them
-- in Swagger. Reset with `docker compose down -v` when they expire.
--
-- Every account's password: Bhorsha@123 (bcrypt, cost 10, to keep demo logins fast).
-- =============================================================================

BEGIN;

-- Applies the formula documented on fare_rules. Seed-only helper (pg_temp is dropped
-- when this session ends).
CREATE FUNCTION pg_temp.fare_quote(p_type vehicle_type, p_distance_m integer, p_shared boolean)
RETURNS TABLE (fare_paisa bigint, ceiling_paisa bigint, snapshot jsonb)
LANGUAGE sql STABLE AS $$
  SELECT f.fare, x.ceiling,
         jsonb_build_object(
           'fareRuleId', r.id, 'vehicleType', r.vehicle_type, 'distanceM', p_distance_m,
           'baseDistanceM', r.base_distance_m, 'basePaisa', r.base_paisa, 'perKmPaisa', r.per_km_paisa,
           'ceilingBasePaisa', r.ceiling_base_paisa, 'ceilingPerKmPaisa', r.ceiling_per_km_paisa,
           'shared', p_shared, 'shareDiscountBps', CASE WHEN p_shared THEN r.share_discount_bps ELSE 0 END,
           'soloFarePaisa', x.solo, 'farePaisa', f.fare, 'ceilingPaisa', x.ceiling)
    FROM fare_rules r
   CROSS JOIN LATERAL (
     SELECT r.base_paisa + round(r.per_km_paisa * GREATEST(p_distance_m - r.base_distance_m, 0) / 1000.0)::bigint AS solo,
            r.ceiling_base_paisa + round(r.ceiling_per_km_paisa * GREATEST(p_distance_m - r.base_distance_m, 0) / 1000.0)::bigint AS ceiling
   ) x
   CROSS JOIN LATERAL (
     SELECT LEAST(CASE WHEN p_shared THEN round(x.solo * (10000 - r.share_discount_bps) / 10000.0)::bigint ELSE x.solo END,
                  x.ceiling) AS fare
   ) f
   WHERE r.vehicle_type = p_type
$$;

-- -----------------------------------------------------------------------------
-- identity: 13 accounts. Ids 1-9 are the same people as in v1.
-- -----------------------------------------------------------------------------
INSERT INTO users (id, full_name, phone, email, password_hash, role, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT v.id, v.full_name, v.phone, v.email, h.hash, v.role::user_role, v.created_at, v.created_at
  FROM (VALUES
    ( 1, 'Bhorsha Admin', '+8801700000001', 'admin@bhorsha.test',         'ADMIN',   now() - interval '60 days'),
    ( 2, 'Farhana Islam', '+8801700000002', 'support@bhorsha.test',       'SUPPORT', now() - interval '60 days'),
    ( 3, 'Nusrat Jahan',  '+8801711000003', 'rider@bhorsha.test',         'RIDER',   now() - interval '45 days'),
    ( 4, 'Tanvir Rahman', '+8801811000004', 'rider2@bhorsha.test',        'RIDER',   now() - interval '40 days'),
    ( 5, 'Karim Mia',     '+8801911000005', 'driver.karim@bhorsha.test',  'DRIVER',  now() - interval '50 days'),
    ( 6, 'Jamal Hossain', '+8801511000006', 'driver.jamal@bhorsha.test',  'DRIVER',  now() - interval '50 days'),
    ( 7, 'Rafiq Ahmed',   '+8801611000007', 'driver.rafiq@bhorsha.test',  'DRIVER',  now() - interval '48 days'),
    ( 8, 'Shakil Khan',   '+8801311000008', 'driver.shakil@bhorsha.test', 'DRIVER',  now() - interval '2 days'),
    ( 9, 'Abul Kalam',    '+8801411000009', 'driver.abul@bhorsha.test',   'DRIVER',  now() - interval '30 days'),
    (10, 'Mahmud Hasan',  '+8801700000010', 'support2@bhorsha.test',      'SUPPORT', now() - interval '58 days'),
    (11, 'Sadia Afrin',   '+8801711000011', 'rider3@bhorsha.test',        'RIDER',   now() - interval '35 days'),
    (12, 'Rumana Akter',  '+8801811000012', 'rider4@bhorsha.test',        'RIDER',   now() - interval '20 days'),
    (13, 'Imran Hossain', '+8801911000013', 'rider5@bhorsha.test',        'RIDER',   now() - interval '10 days')
  ) AS v(id, full_name, phone, email, role, created_at)
  CROSS JOIN (SELECT '$2a$10$yI5uXBRzWiiHNUsxYLreo.KMQepUqgIyPBHPyUyBikkRC1hga9b8y'::varchar AS hash) AS h;

-- -----------------------------------------------------------------------------
-- fleet
-- -----------------------------------------------------------------------------
INSERT INTO driver_profiles (user_id, licence_no, verification, reviewed_by, reviewed_at, rejection_reason, status,
                             last_lat, last_lng, last_location_at, created_at, updated_at) VALUES
  -- Karim: car, waiting near Bashundhara gate, about 0.6 km from Nusrat's pickup (ride 5).
  (5, 'DHA-DL-0045121', 'VERIFIED', 1, now() - interval '49 days', NULL, 'ONLINE',  23.813500, 90.424500, now() - interval '15 seconds',
      now() - interval '50 days', now() - interval '15 seconds'),
  -- Jamal: car, driving ride 4 between Uttara and Khilkhet.
  (6, 'DHA-DL-0072388', 'VERIFIED', 1, now() - interval '49 days', NULL, 'ONLINE',  23.845000, 90.412000, now() - interval '5 seconds',
      now() - interval '50 days', now() - interval '5 seconds'),
  -- Rafiq: bike, on his way to Imran's pickup (ride 7).
  (7, 'DHA-DL-0103567', 'VERIFIED', 1, now() - interval '47 days', NULL, 'ONLINE',  23.781000, 90.400000, now() - interval '20 seconds',
      now() - interval '48 days', now() - interval '20 seconds'),
  -- Shakil: bike, waiting in the admin's verification queue.
  (8, 'DHA-DL-0119902', 'PENDING',  NULL, NULL,                    NULL, 'OFFLINE', NULL,      NULL,      NULL,
      now() - interval '2 days',  now() - interval '2 days'),
  -- Abul: CNG, heading home from Motijheel (route offer 2).
  (9, 'DHA-DL-0088140', 'VERIFIED', 1, now() - interval '29 days', NULL, 'ONLINE',  23.733000, 90.417200, now() - interval '30 seconds',
      now() - interval '30 days', now() - interval '30 seconds');

INSERT INTO vehicles (id, driver_id, type, reg_no, seats, model, color, created_at, updated_at, deleted_at)
OVERRIDING SYSTEM VALUE VALUES
  (1, 5, 'CAR',  'DHAKA METRO-GA 11-2345',  3, 'Toyota Axio',      'White',  now() - interval '50 days', now() - interval '50 days', NULL),
  (2, 6, 'CAR',  'DHAKA METRO-GA 27-8812',  3, 'Toyota Allion',    'Silver', now() - interval '50 days', now() - interval '50 days', NULL),
  (3, 7, 'BIKE', 'DHAKA METRO-HA 45-1290',  1, 'Bajaj Pulsar 150', 'Black',  now() - interval '48 days', now() - interval '48 days', NULL),
  (4, 8, 'BIKE', 'DHAKA METRO-HA 61-0077',  1, 'Honda CB Hornet',  'Red',    now() - interval '2 days',  now() - interval '2 days',  NULL),
  (5, 9, 'CNG',  'DHAKA METRO-THA 13-5521', 2, 'Bajaj RE',         'Green',  now() - interval '30 days', now() - interval '30 days', NULL),
  -- Karim sold his bike: soft-deleted, so GET /vehicles/my hides it but history keeps it.
  (6, 5, 'BIKE', 'DHAKA METRO-HA 12-3344',  1, 'Honda Livo',       'Blue',   now() - interval '45 days', now() - interval '10 days', now() - interval '10 days');

-- -----------------------------------------------------------------------------
-- pricing. CAR values follow the reported BRTA ceiling (Tk 85 for the first 2 km,
-- Tk 34/km after); re-check before submission. BIKE and CNG are example values.
-- -----------------------------------------------------------------------------
INSERT INTO fare_rules (id, vehicle_type, base_paisa, per_km_paisa, base_distance_m, ceiling_base_paisa, ceiling_per_km_paisa,
                        share_discount_bps, updated_by, created_at, updated_at)
OVERRIDING SYSTEM VALUE VALUES
  (1, 'BIKE', 3000, 1200, 2000, 4000, 1800, 2500, NULL, now() - interval '60 days', now() - interval '60 days'),
  (2, 'CAR',  6000, 2500, 2000, 8500, 3400, 2500, 1,    now() - interval '60 days', now() - interval '10 days'),
  (3, 'CNG',  4000, 1800, 2000, 5500, 2500, 2500, NULL, now() - interval '60 days', now() - interval '60 days');

-- -----------------------------------------------------------------------------
-- trips: rides
-- -----------------------------------------------------------------------------
INSERT INTO rides (id, vehicle_type, is_shared, seats_total, seats_free, status, driver_id, vehicle_id, version, cancel_reason,
                   created_at, accepted_at, started_at, completed_at, cancelled_at, updated_at)
OVERRIDING SYSTEM VALUE VALUES
  -- 1: Mirpur 10 -> Motijheel, solo car.
  (1, 'CAR',  false, 3, 0, 'COMPLETED',   5, 1, 5, NULL,
      now() - interval '3 days',
      now() - interval '3 days' + interval '2 minutes', now() - interval '3 days' + interval '8 minutes',
      now() - interval '3 days' + interval '40 minutes', NULL, now() - interval '3 days' + interval '40 minutes'),
  -- 2: shared car, two passengers, everyone dropped (all 3 seats free again).
  (2, 'CAR',  true,  3, 3, 'COMPLETED',   6, 2, 9, NULL,
      now() - interval '2 days',
      now() - interval '2 days' + interval '3 minutes', now() - interval '2 days' + interval '10 minutes',
      now() - interval '2 days' + interval '50 minutes', NULL, now() - interval '2 days' + interval '50 minutes'),
  -- 3: Farmgate -> Gulshan 1, solo bike.
  (3, 'BIKE', false, 1, 0, 'COMPLETED',   7, 3, 5, NULL,
      now() - interval '6 hours',
      now() - interval '6 hours' + interval '1 minute', now() - interval '6 hours' + interval '4 minutes',
      now() - interval '6 hours' + interval '22 minutes', NULL, now() - interval '6 hours' + interval '22 minutes'),
  -- 4: shared car in progress. Rumana aboard, Sadia waiting at Khilkhet: 3 - 2 = 1 seat free.
  (4, 'CAR',  true,  3, 1, 'IN_PROGRESS', 6, 2, 6, NULL,
      now() - interval '25 minutes',
      now() - interval '24 minutes', now() - interval '15 minutes', NULL, NULL, now() - interval '10 minutes'),
  -- 5: Nusrat's shared booking (1 seat) waiting for a driver at Kuril.
  (5, 'CAR',  true,  3, 2, 'REQUESTED',   NULL, NULL, 1, NULL,
      now() - interval '3 minutes', NULL, NULL, NULL, NULL, now() - interval '3 minutes'),
  -- 6: Motijheel -> Shahbag by CNG, cancelled by the rider before anyone accepted.
  (6, 'CNG',  false, 2, 0, 'CANCELLED',   NULL, NULL, 2, 'RIDER_CANCELLED',
      now() - interval '5 hours', NULL, NULL, NULL, now() - interval '5 hours' + interval '4 minutes',
      now() - interval '5 hours' + interval '4 minutes'),
  -- 7: Mohakhali -> Kawran Bazar, solo bike. Rafiq accepted and is on his way.
  (7, 'BIKE', false, 1, 0, 'ACCEPTED',    7, 3, 2, NULL,
      now() - interval '4 minutes', now() - interval '3 minutes', NULL, NULL, NULL, now() - interval '3 minutes');

-- -----------------------------------------------------------------------------
-- sharing: route offers ("going this way")
-- -----------------------------------------------------------------------------
INSERT INTO route_offers (id, driver_id, ride_id, vehicle_id, vehicle_type, from_lat, from_lng, to_lat, to_lng,
                          seats_offered, status, expires_at, created_at, updated_at)
OVERRIDING SYSTEM VALUE VALUES
  -- Jamal publishes the rest of ride 4 (Uttara -> Banani). Its seats are counted on ride 4.
  (1, 6, 4,    2, 'CAR', 23.845000, 90.412000, 23.793700, 90.406600, 2, 'OPEN',
      now() + interval '2 hours', now() - interval '12 minutes', now() - interval '12 minutes'),
  -- Abul is heading home to Uttara with no ride yet. The first accepted join creates the ride.
  (2, 9, NULL, 5, 'CNG', 23.733000, 90.417200, 23.874000, 90.398000, 2, 'OPEN',
      now() + interval '2 hours', now() - interval '6 minutes', now() - interval '6 minutes'),
  -- Karim withdrew yesterday's offer (DELETE /route-offers/:id keeps the row).
  (3, 5, NULL, 1, 'CAR', 23.757700, 90.389700, 23.806900, 90.368600, 3, 'WITHDRAWN',
      now() - interval '1 day' + interval '30 minutes', now() - interval '1 day', now() - interval '1 day' + interval '5 minutes');

-- -----------------------------------------------------------------------------
-- sharing: join requests. Every quote is a shared fare from fare_rules.
-- -----------------------------------------------------------------------------
INSERT INTO join_requests (id, ride_id, route_offer_id, rider_id, driver_id, initiated_by, seats,
                           pickup_lat, pickup_lng, drop_lat, drop_lng, distance_m,
                           quoted_fare_paisa, ceiling_paisa, pricing_snapshot,
                           status, expires_at, decided_at, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT v.id, v.ride_id, v.route_offer_id, v.rider_id, v.driver_id, v.initiated_by, v.seats,
       v.pickup_lat, v.pickup_lng, v.drop_lat, v.drop_lng, v.distance_m,
       q.fare_paisa, q.ceiling_paisa, q.snapshot,
       v.status, v.expires_at, v.decided_at, v.created_at, COALESCE(v.decided_at, v.created_at)
  FROM (VALUES
    -- 1: Jamal invited Sadia (waiting at Mohakhali) onto ride 2; she accepted. Became passenger 3.
    (1, 2::integer, NULL::integer, 11, 6, 'DRIVER'::join_initiator, 1::smallint,
        23.777900::numeric, 90.405300::numeric, 23.736000::numeric, 90.413500::numeric, 6000,
        'ACCEPTED'::join_request_status,
        now() - interval '2 days' + interval '14 minutes',
        (now() - interval '2 days' + interval '13 minutes 40 seconds')::timestamptz,
        now() - interval '2 days' + interval '13 minutes'),
    -- 2: Nusrat asked to join ride 2; Jamal declined (the detour was too long).
    (2, 2, NULL, 3, 6, 'RIDER', 1,
        23.780600, 90.416700, 23.733000, 90.417200, 8000,
        'DECLINED',
        now() - interval '2 days' + interval '12 minutes 12 seconds',
        now() - interval '2 days' + interval '12 minutes 6 seconds',
        now() - interval '2 days' + interval '12 minutes'),
    -- 3: Sadia asked to join through Jamal's offer 1; he accepted. Became passenger 6.
    (3, NULL, 1, 11, 6, 'RIDER', 1,
        23.829000, 90.420000, 23.793700, 90.406600, 5000,
        'ACCEPTED',
        now() - interval '9 minutes 58 seconds',
        now() - interval '10 minutes',
        now() - interval '10 minutes 10 seconds'),
    -- 4: LAST-SEAT RACE (A): Tanvir asks to join ride 4 through offer 1. Jamal answers.
    (4, NULL, 1, 4, 6, 'RIDER', 1,
        23.818000, 90.421000, 23.793700, 90.406600, 4000,
        'PENDING',
        now() + interval '2 hours', NULL,
        now() - interval '2 minutes'),
    -- 5: LAST-SEAT RACE (B), the core feature: Jamal invites Nusrat, who is waiting on her
    --    own ride 5. Nusrat answers; accepting cancels her ride 5 first.
    (5, 4, NULL, 3, 6, 'DRIVER', 1,
        23.817000, 90.420000, 23.780600, 90.416700, 6000,
        'PENDING',
        now() + interval '2 hours', NULL,
        now() - interval '1 minute'),
    -- 6: Tanvir asks to join Abul's heading-home CNG (offer 2, no ride yet). Abul answers.
    (6, NULL, 2, 4, 9, 'RIDER', 1,
        23.748000, 90.412000, 23.843400, 90.397800, 9000,
        'PENDING',
        now() + interval '2 hours', NULL,
        now() - interval '5 minutes'),
    -- 7: Jamal invited Rumana onto ride 2; she never answered.
    (7, 2, NULL, 12, 6, 'DRIVER', 1,
        23.777900, 90.405300, 23.733000, 90.417200, 7000,
        'EXPIRED',
        now() - interval '2 days' + interval '21 minutes', NULL,
        now() - interval '2 days' + interval '20 minutes')
  ) AS v(id, ride_id, route_offer_id, rider_id, driver_id, initiated_by, seats,
         pickup_lat, pickup_lng, drop_lat, drop_lng, distance_m, status, expires_at, decided_at, created_at)
  CROSS JOIN LATERAL pg_temp.fare_quote(
    COALESCE((SELECT r.vehicle_type FROM rides r WHERE r.id = v.ride_id),
             (SELECT o.vehicle_type FROM route_offers o WHERE o.id = v.route_offer_id)),
    v.distance_m, true) AS q;

-- -----------------------------------------------------------------------------
-- trips: passengers (users M:N rides). Each fare comes from its ride's vehicle type and
-- sharing mode. For seats created by a join request it equals that request's quote.
-- -----------------------------------------------------------------------------
INSERT INTO ride_passengers (id, ride_id, rider_id, join_request_id, seats, status,
                             pickup_lat, pickup_lng, drop_lat, drop_lng, distance_m,
                             locked_fare_paisa, ceiling_paisa, pricing_snapshot, pickup_pin,
                             arrived_at, picked_up_at, dropped_at, cancelled_at, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT v.id, v.ride_id, v.rider_id, v.join_request_id, v.seats, v.status,
       v.pickup_lat, v.pickup_lng, v.drop_lat, v.drop_lng, v.distance_m,
       q.fare_paisa, q.ceiling_paisa, q.snapshot, v.pin,
       v.arrived_at, v.picked_up_at, v.dropped_at, v.cancelled_at, v.created_at,
       GREATEST(v.created_at, v.arrived_at, v.picked_up_at, v.dropped_at, v.cancelled_at)
  FROM (VALUES
    -- ride 1: Nusrat, Mirpur 10 -> Motijheel, 10 km solo car = 26000.
    (1, 1, 3, NULL::integer, 1::smallint, 'DROPPED'::passenger_status,
        23.806900::numeric, 90.368600::numeric, 23.733000::numeric, 90.417200::numeric, 10000, '4821',
        (now() - interval '3 days' + interval '6 minutes')::timestamptz,
        (now() - interval '3 days' + interval '8 minutes')::timestamptz,
        (now() - interval '3 days' + interval '40 minutes')::timestamptz,
        NULL::timestamptz,
        now() - interval '3 days'),
    -- ride 2: Tanvir booked shared, Banani -> Motijheel, 10 km = 19500.
    (2, 2, 4, NULL, 1, 'DROPPED',
        23.793700, 90.406600, 23.733000, 90.417200, 10000, '3307',
        now() - interval '2 days' + interval '8 minutes', now() - interval '2 days' + interval '10 minutes',
        now() - interval '2 days' + interval '45 minutes', NULL,
        now() - interval '2 days'),
    -- ride 2: Sadia joined through invite 1, Mohakhali -> Paltan, 6 km = 12000.
    (3, 2, 11, 1, 1, 'DROPPED',
        23.777900, 90.405300, 23.736000, 90.413500, 6000, '5172',
        now() - interval '2 days' + interval '16 minutes', now() - interval '2 days' + interval '18 minutes',
        now() - interval '2 days' + interval '50 minutes', NULL,
        now() - interval '2 days' + interval '13 minutes 40 seconds'),
    -- ride 3: Tanvir, Farmgate -> Gulshan 1, 5 km solo bike = 6600.
    (4, 3, 4, NULL, 1, 'DROPPED',
        23.757700, 90.389700, 23.780600, 90.416700, 5000, '6612',
        now() - interval '6 hours' + interval '3 minutes', now() - interval '6 hours' + interval '4 minutes',
        now() - interval '6 hours' + interval '22 minutes', NULL,
        now() - interval '6 hours'),
    -- ride 4: Rumana booked shared, Uttara Sector 7 -> Banani, 10 km = 19500. Aboard.
    (5, 4, 12, NULL, 1, 'PICKED_UP',
        23.874000, 90.398000, 23.793700, 90.406600, 10000, '7720',
        now() - interval '17 minutes', now() - interval '15 minutes', NULL, NULL,
        now() - interval '25 minutes'),
    -- ride 4: Sadia joined through request 3, Khilkhet -> Banani, 5 km = 10125. Waiting.
    (6, 4, 11, 3, 1, 'CONFIRMED',
        23.829000, 90.420000, 23.793700, 90.406600, 5000, '3391',
        NULL, NULL, NULL, NULL,
        now() - interval '10 minutes'),
    -- ride 5: Nusrat waiting at Kuril, -> Gulshan 1, 6 km shared = 12000.
    (7, 5, 3, NULL, 1, 'CONFIRMED',
        23.817000, 90.420000, 23.780600, 90.416700, 6000, '2754',
        NULL, NULL, NULL, NULL,
        now() - interval '3 minutes'),
    -- ride 6: Tanvir cancelled, Motijheel -> Shahbag, 3 km CNG = 5800.
    (8, 6, 4, NULL, 1, 'CANCELLED',
        23.733000, 90.417200, 23.738500, 90.395800, 3000, '1188',
        NULL, NULL, NULL, now() - interval '5 hours' + interval '4 minutes',
        now() - interval '5 hours'),
    -- ride 7: Imran, Mohakhali -> Kawran Bazar, 4 km solo bike = 5400. PIN 9150 for the demo.
    (9, 7, 13, NULL, 1, 'CONFIRMED',
        23.777900, 90.405300, 23.750900, 90.393500, 4000, '9150',
        NULL, NULL, NULL, NULL,
        now() - interval '4 minutes')
  ) AS v(id, ride_id, rider_id, join_request_id, seats, status,
         pickup_lat, pickup_lng, drop_lat, drop_lng, distance_m, pin,
         arrived_at, picked_up_at, dropped_at, cancelled_at, created_at)
  JOIN rides r ON r.id = v.ride_id
  CROSS JOIN LATERAL pg_temp.fare_quote(r.vehicle_type, v.distance_m, r.is_shared) AS q;

INSERT INTO ratings (ride_id, from_user_id, to_user_id, stars, comment, created_at) VALUES
  (1,  3,  5, 2, 'Asked for Tk 300 instead of the Tk 260 the app showed.',      now() - interval '3 days' + interval '45 minutes'),
  (1,  5,  3, 5, NULL,                                                           now() - interval '3 days' + interval '42 minutes'),
  (2,  4,  6, 5, 'Picked up a co-rider on the way and still arrived on time.',  now() - interval '2 days' + interval '47 minutes'),
  (2, 11,  6, 4, NULL,                                                           now() - interval '2 days' + interval '52 minutes'),
  (2, 11,  4, 1, 'Kept asking for my phone number.',                            now() - interval '2 days' + interval '53 minutes'),
  (2,  6,  4, 4, NULL,                                                           now() - interval '2 days' + interval '51 minutes'),
  (2,  6, 11, 5, NULL,                                                           now() - interval '2 days' + interval '51 minutes'),
  (3,  4,  7, 3, 'No passenger helmet.',                                         now() - interval '6 hours' + interval '25 minutes'),
  (3,  7,  4, 4, NULL,                                                           now() - interval '6 hours' + interval '23 minutes');

-- -----------------------------------------------------------------------------
-- trust: cases -> strikes -> appeals (separation of duties: issuer never decides)
-- -----------------------------------------------------------------------------
INSERT INTO support_cases (id, type, status, reporter_id, subject_id, ride_id, assigned_to, description,
                           amount_claimed_paisa, resolution, resolved_at, created_at, updated_at)
OVERRIDING SYSTEM VALUE VALUES
  (1, 'OVERCHARGE', 'UPHELD', 3, 5, 1, 2,
      'Driver asked for Tk 300 at drop-off; the app showed a locked fare of Tk 260.',
      30000,
      'The locked fare was Tk 260 and the trip followed the planned route with no extra stop. Overcharge confirmed; one strike issued.',
      now() - interval '2 days', now() - interval '3 days' + interval '1 hour', now() - interval '2 days'),
  (2, 'CONDUCT', 'UPHELD', 11, 4, 2, 10,
      'My co-rider was abusive and kept asking for my phone number.',
      NULL,
      'The driver''s statement confirms the co-rider''s behaviour. One strike issued to the rider.',
      now() - interval '1 day', now() - interval '2 days' + interval '1 hour', now() - interval '1 day'),
  (3, 'SAFETY', 'OPEN', 4, 7, 3, NULL,
      'Driver had no passenger helmet and was rude when I asked for one.',
      NULL, NULL, NULL, now() - interval '5 hours 30 minutes', now() - interval '5 hours 30 minutes'),
  (4, 'OTHER', 'WITHDRAWN', 12, NULL, NULL, NULL,
      'I thought I was charged twice, but it was my bank''s pending hold.',
      NULL, NULL, NULL, now() - interval '1 day', now() - interval '22 hours');

INSERT INTO strikes (id, user_id, case_id, issued_by, reason, status, issued_at, expires_at, revoked_at, created_at, updated_at)
OVERRIDING SYSTEM VALUE VALUES
  -- A driver strike, issued by Farhana.
  (1, 5, 1, 2,  'Demanded Tk 300 against a locked fare of Tk 260 (case #1).', 'ACTIVE',
      now() - interval '2 days', now() - interval '2 days' + interval '90 days', NULL,
      now() - interval '2 days', now() - interval '2 days'),
  -- A RIDER strike (FR-TS-5), issued by Mahmud. Under appeal, so it does not count.
  (2, 4, 2, 10, 'Harassed a co-rider during a shared ride (case #2).',        'ACTIVE',
      now() - interval '1 day',  now() - interval '1 day' + interval '90 days',  NULL,
      now() - interval '1 day',  now() - interval '1 day');

INSERT INTO appeals (id, strike_id, statement, status, decided_by, decision_reason, decided_at, created_at, updated_at)
OVERRIDING SYSTEM VALUE VALUES
  -- Farhana issued strike 1, so Mahmud decided its appeal.
  (1, 1, 'The rider asked for an extra stop at a pharmacy, so I asked for more.', 'REJECTED', 10,
      'The GPS trace shows no stop between pickup and drop-off. The strike stands and expires after 90 days.',
      now() - interval '30 hours', now() - interval '44 hours', now() - interval '30 hours'),
  -- Mahmud issued strike 2, so only Farhana or the admin may decide this one.
  (2, 2, 'It was a misunderstanding: I only asked whether she wanted a copy of the fare receipt.', 'PENDING', NULL,
      NULL, NULL, now() - interval '20 hours', now() - interval '20 hours');

-- -----------------------------------------------------------------------------
-- audit: before/after values (never secrets: the table rejects them)
-- -----------------------------------------------------------------------------
INSERT INTO audit_logs (user_id, action, entity, entity_id, old_value, new_value, ip_address, request_id, created_at) VALUES
  (1,  'USER_CREATED',          'users',           '10', NULL, '{"role":"SUPPORT","fullName":"Mahmud Hasan"}',
       '203.0.113.10', 'seed-0001', now() - interval '58 days'),
  (1,  'DRIVER_VERIFIED',       'driver_profiles', '5',  '{"verification":"PENDING"}', '{"verification":"VERIFIED"}',
       '203.0.113.10', 'seed-0002', now() - interval '49 days'),
  (1,  'DRIVER_VERIFIED',       'driver_profiles', '6',  '{"verification":"PENDING"}', '{"verification":"VERIFIED"}',
       '203.0.113.10', 'seed-0003', now() - interval '49 days'),
  (1,  'DRIVER_VERIFIED',       'driver_profiles', '7',  '{"verification":"PENDING"}', '{"verification":"VERIFIED"}',
       '203.0.113.10', 'seed-0004', now() - interval '47 days'),
  (1,  'DRIVER_VERIFIED',       'driver_profiles', '9',  '{"verification":"PENDING"}', '{"verification":"VERIFIED"}',
       '203.0.113.10', 'seed-0005', now() - interval '29 days'),
  (1,  'FARE_RULE_UPDATED',     'fare_rules',      '2',  '{"perKmPaisa":2400}', '{"perKmPaisa":2500}',
       '203.0.113.10', 'seed-0006', now() - interval '10 days'),
  (5,  'VEHICLE_REMOVED',       'vehicles',        '6',  '{"deletedAt":null}',
       jsonb_build_object('deletedAt', now() - interval '10 days'),
       '203.0.113.25', 'seed-0007', now() - interval '10 days'),
  (2,  'CASE_DECIDED',          'support_cases',   '1',  '{"status":"UNDER_REVIEW"}', '{"status":"UPHELD"}',
       '203.0.113.11', 'seed-0008', now() - interval '2 days'),
  (2,  'STRIKE_ISSUED',         'strikes',         '1',  NULL, '{"userId":5,"caseId":1}',
       '203.0.113.11', 'seed-0009', now() - interval '2 days'),
  (10, 'APPEAL_DECIDED',        'appeals',         '1',  '{"status":"PENDING"}', '{"status":"REJECTED"}',
       '203.0.113.12', 'seed-0010', now() - interval '30 hours'),
  (10, 'CASE_DECIDED',          'support_cases',   '2',  '{"status":"UNDER_REVIEW"}', '{"status":"UPHELD"}',
       '203.0.113.12', 'seed-0011', now() - interval '1 day'),
  (10, 'STRIKE_ISSUED',         'strikes',         '2',  NULL, '{"userId":4,"caseId":2}',
       '203.0.113.12', 'seed-0012', now() - interval '1 day'),
  (12, 'CASE_WITHDRAWN',        'support_cases',   '4',  '{"status":"OPEN"}', '{"status":"WITHDRAWN"}',
       '203.0.113.31', 'seed-0013', now() - interval '22 hours'),
  (6,  'RIDE_ACCEPTED',         'rides',           '4',  '{"status":"REQUESTED"}', '{"status":"ACCEPTED","driverId":6}',
       '203.0.113.26', 'seed-0014', now() - interval '24 minutes'),
  (6,  'JOIN_REQUEST_ACCEPTED', 'join_requests',   '3',  '{"status":"PENDING"}', '{"status":"ACCEPTED","ridePassengerId":6}',
       '203.0.113.26', 'seed-0015', now() - interval '10 minutes'),
  (9,  'ROUTE_OFFER_CREATED',   'route_offers',    '2',  NULL, '{"vehicleType":"CNG","seatsOffered":2}',
       '203.0.113.29', 'seed-0016', now() - interval '6 minutes'),
  (3,  'RIDE_BOOKED',           'rides',           '5',  NULL, '{"isShared":true,"seats":1}',
       '203.0.113.33', 'seed-0017', now() - interval '3 minutes'),
  (7,  'RIDE_ACCEPTED',         'rides',           '7',  '{"status":"REQUESTED"}', '{"status":"ACCEPTED","driverId":7}',
       '203.0.113.27', 'seed-0018', now() - interval '3 minutes');

-- -----------------------------------------------------------------------------
-- Move every identity sequence past the explicit ids above, so the app's first
-- INSERT gets the next free id.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name, column_name
      FROM information_schema.columns
     WHERE table_schema = 'public' AND is_identity = 'YES'
  LOOP
    EXECUTE format(
      'SELECT setval(pg_get_serial_sequence(%L, %L), COALESCE((SELECT max(%I) FROM %I), 0) + 1, false)',
      r.table_name, r.column_name, r.column_name, r.table_name);
  END LOOP;
END $$;

COMMIT;
