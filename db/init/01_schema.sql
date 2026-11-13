-- =============================================================================
-- Bhorsha: PostgreSQL 16 schema v2.0.0
-- Architecture v3.1, section 26 (CSC4161 course release): 13 tables.
--
-- SINGLE SOURCE OF TRUTH for the schema, used by two paths:
--   A. The Docker image runs this file on first start (docker-entrypoint-initdb.d).
--   B. The TypeORM baseline migration (SchemaBaseline1794441600000) executes this
--      same file, so `migration:run` on an empty database builds the same schema.
-- That is why this file has no BEGIN/COMMIT: path B runs it inside the migration's
-- transaction. It must stay plain SQL (no psql backslash commands).
--
-- FROZEN once v2.0.0 is published. Every later change ships as a new migration.
--
-- Conventions
--   keys        integer GENERATED ALWAYS AS IDENTITY: never insert explicit ids
--   money       bigint paisa (*_paisa); 1 Tk = 100 paisa (ADR-008)
--   distance    integer metres (*_m)
--   percent     basis points (*_bps); 2500 = 25.00 %
--   time        timestamptz, stored in UTC
--   names       pk_/fk_/uq_/ck_/ix_/trg_. They are stable, so the API's global
--               exception filter can map a constraint name to a status and message.
--   deletes     ON DELETE RESTRICT everywhere. Users are deactivated, never deleted.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Types. Status enums mirror the state diagrams in the architecture document.
-- OFFERING and AWAITING_HANDOVER belong to the full product (dispatch waves and
-- breakdown handover); course-release code does not use them yet.
-- -----------------------------------------------------------------------------
CREATE TYPE user_role           AS ENUM ('RIDER', 'DRIVER', 'ADMIN', 'SUPPORT');
CREATE TYPE driver_verification AS ENUM ('PENDING', 'VERIFIED', 'REJECTED');
CREATE TYPE driver_status       AS ENUM ('OFFLINE', 'ONLINE');
CREATE TYPE vehicle_type        AS ENUM ('BIKE', 'CAR', 'CNG');
CREATE TYPE ride_status         AS ENUM ('REQUESTED', 'OFFERING', 'ACCEPTED', 'ARRIVED', 'IN_PROGRESS',
                                         'AWAITING_HANDOVER', 'COMPLETED', 'CANCELLED');
CREATE TYPE ride_cancel_reason  AS ENUM ('RIDER_CANCELLED', 'DRIVER_CANCELLED', 'NO_DRIVER_FOUND',
                                         'HANDOVER_FAILED', 'JOINED_ANOTHER_RIDE');
CREATE TYPE passenger_status    AS ENUM ('CONFIRMED', 'PICKED_UP', 'DROPPED', 'CANCELLED', 'NO_SHOW');
CREATE TYPE route_offer_status  AS ENUM ('OPEN', 'CLOSED', 'WITHDRAWN');
CREATE TYPE join_initiator      AS ENUM ('RIDER', 'DRIVER');
CREATE TYPE join_request_status AS ENUM ('PENDING', 'ACCEPTED', 'DECLINED', 'EXPIRED');
CREATE TYPE case_type           AS ENUM ('OVERCHARGE', 'SAFETY', 'CONDUCT', 'OTHER');
CREATE TYPE case_status         AS ENUM ('OPEN', 'UNDER_REVIEW', 'UPHELD', 'DISMISSED', 'WITHDRAWN');
CREATE TYPE strike_status       AS ENUM ('ACTIVE', 'OVERTURNED', 'REVOKED');
CREATE TYPE appeal_status       AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED');

-- Coordinates: about 0.1 m precision, range-checked once here instead of on every column.
-- The course release stores lat/lng and uses straight-line distance (no PostGIS yet).
CREATE DOMAIN geo_lat AS numeric(9,6) CONSTRAINT ck_geo_lat_range CHECK (VALUE BETWEEN -90 AND 90);
CREATE DOMAIN geo_lng AS numeric(9,6) CONSTRAINT ck_geo_lng_range CHECK (VALUE BETWEEN -180 AND 180);

-- -----------------------------------------------------------------------------
-- Shared trigger functions
-- -----------------------------------------------------------------------------

-- Keeps updated_at current on every UPDATE, including raw SQL such as the seat transaction.
CREATE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- Generic state-machine guard. Each trigger passes its allowed edges as 'FROM>TO'
-- arguments, so the DDL itself documents every state machine. Triggers using it fire
-- only when the status really changes (WHEN clause). An illegal edge raises 23514,
-- which the API maps to 409.
CREATE FUNCTION enforce_status_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (OLD.status::text || '>' || NEW.status::text) = ANY (TG_ARGV) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION '% % cannot move from % to %', TG_TABLE_NAME, OLD.id, OLD.status, NEW.status
    USING ERRCODE = 'check_violation',
          CONSTRAINT = TG_NAME,
          TABLE = TG_TABLE_NAME,
          DETAIL = 'Allowed transitions: ' || array_to_string(TG_ARGV, ', ');
END $$;

-- Append-only tables: corrections are new rows, never edits.
CREATE FUNCTION forbid_update_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME
    USING ERRCODE = 'insufficient_privilege', TABLE = TG_TABLE_NAME;
END $$;

-- =============================================================================
-- identity
-- =============================================================================

CREATE TABLE users (
  id               integer      GENERATED ALWAYS AS IDENTITY,
  full_name        varchar(100) NOT NULL,
  phone            varchar(16)  NOT NULL,
  email            varchar(254),
  password_hash    varchar(255) NOT NULL,
  role             user_role    NOT NULL,
  is_active        boolean      NOT NULL DEFAULT true,
  suspended_until  timestamptz,
  created_at       timestamptz  NOT NULL DEFAULT now(),
  updated_at       timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT pk_users PRIMARY KEY (id),
  CONSTRAINT uq_users_phone UNIQUE (phone),
  CONSTRAINT uq_users_email UNIQUE (email),
  CONSTRAINT ck_users_full_name CHECK (btrim(full_name) <> ''),
  -- Bangladesh mobile numbers in E.164 form: +8801[3-9]XXXXXXXX. Normalise in the DTO.
  CONSTRAINT ck_users_phone_format CHECK (phone ~ '^\+8801[3-9][0-9]{8}$'),
  -- Stored lower-case (normalise in the DTO), so UNIQUE is effectively case-insensitive.
  CONSTRAINT ck_users_email_format CHECK (email = lower(email) AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);
CREATE INDEX ix_users_role ON users (role, id DESC);

COMMENT ON TABLE  users IS 'identity module. Every account: rider, driver, admin or support officer. Plural because "user" is reserved.';
COMMENT ON COLUMN users.password_hash IS 'bcrypt hash (cost 12). Never selected by default and never returned or logged.';
COMMENT ON COLUMN users.is_active IS 'false = deactivated by an admin (the soft delete behind DELETE /users/:id).';
COMMENT ON COLUMN users.suspended_until IS 'Suspended while now() < suspended_until (3 active strikes = 7 days, section 16). NULL = not suspended.';

-- =============================================================================
-- fleet
-- =============================================================================

CREATE TABLE driver_profiles (
  user_id           integer             NOT NULL,
  licence_no        varchar(30)         NOT NULL,
  verification      driver_verification NOT NULL DEFAULT 'PENDING',
  reviewed_by       integer,
  reviewed_at       timestamptz,
  rejection_reason  text,
  status            driver_status       NOT NULL DEFAULT 'OFFLINE',
  last_lat          geo_lat,
  last_lng          geo_lng,
  last_location_at  timestamptz,
  created_at        timestamptz         NOT NULL DEFAULT now(),
  updated_at        timestamptz         NOT NULL DEFAULT now(),
  CONSTRAINT pk_driver_profiles PRIMARY KEY (user_id),
  CONSTRAINT fk_driver_profiles_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT fk_driver_profiles_reviewed_by FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT uq_driver_profiles_licence_no UNIQUE (licence_no),
  CONSTRAINT ck_driver_profiles_licence_no CHECK (btrim(licence_no) <> ''),
  -- Only a verified driver can go online. Rejecting an online driver must set OFFLINE in the same UPDATE.
  CONSTRAINT ck_driver_profiles_online_verified CHECK (status = 'OFFLINE' OR verification = 'VERIFIED'),
  -- Every verification decision names the admin who made it and when.
  CONSTRAINT ck_driver_profiles_review CHECK (verification = 'PENDING' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
  CONSTRAINT ck_driver_profiles_rejection_reason CHECK (verification <> 'REJECTED' OR rejection_reason IS NOT NULL),
  CONSTRAINT ck_driver_profiles_location CHECK (
    (last_lat IS NULL) = (last_lng IS NULL) AND (last_lat IS NULL) = (last_location_at IS NULL))
);
-- Admin verification queue (GET /drivers?verification=PENDING).
CREATE INDEX ix_driver_profiles_pending ON driver_profiles (created_at) WHERE verification = 'PENDING';

COMMENT ON TABLE  driver_profiles IS 'fleet module. Driver extension of users (1:1, shared primary key). Created with the user in one transaction.';
COMMENT ON COLUMN driver_profiles.last_lat IS 'Last posted position (PUT /drivers/me/location). Live tracking moves to Redis GEO in the full product.';

CREATE TABLE vehicles (
  id          integer      GENERATED ALWAYS AS IDENTITY,
  driver_id   integer      NOT NULL,
  type        vehicle_type NOT NULL,
  reg_no      varchar(30)  NOT NULL,
  seats       smallint     NOT NULL,
  model       varchar(60),
  color       varchar(30),
  created_at  timestamptz  NOT NULL DEFAULT now(),
  updated_at  timestamptz  NOT NULL DEFAULT now(),
  deleted_at  timestamptz,
  CONSTRAINT pk_vehicles PRIMARY KEY (id),
  CONSTRAINT fk_vehicles_driver FOREIGN KEY (driver_id) REFERENCES driver_profiles (user_id) ON DELETE RESTRICT,
  -- Target of the composite foreign keys from rides and route_offers: they prove in one
  -- check that the vehicle exists, belongs to that driver and has that type.
  CONSTRAINT uq_vehicles_id_driver_type UNIQUE (id, driver_id, type),
  CONSTRAINT ck_vehicles_reg_no CHECK (btrim(reg_no) <> ''),
  -- Passenger seats come from the type (bike 1, CNG 2, car 3).
  CONSTRAINT ck_vehicles_seats CHECK (seats BETWEEN 1 AND 3 AND (type <> 'BIKE' OR seats = 1))
);
-- A registration number belongs to one active vehicle. Soft-deleted rows keep history,
-- so a sold vehicle can be registered again by its next driver.
CREATE UNIQUE INDEX uq_vehicles_reg_no_active ON vehicles (upper(reg_no)) WHERE deleted_at IS NULL;
CREATE INDEX ix_vehicles_driver_active ON vehicles (driver_id) WHERE deleted_at IS NULL;

COMMENT ON TABLE  vehicles IS 'fleet module. Soft delete via deleted_at, because past rides keep pointing at the vehicle. type is never editable.';

-- =============================================================================
-- pricing
-- =============================================================================

-- One editable rule per vehicle type (no version history in the course release).
-- Fare for a distance d:     base_paisa + per_km_paisa * max(d - base_distance_m, 0) / 1000
-- Legal ceiling for d:       ceiling_base_paisa + ceiling_per_km_paisa * max(d - base_distance_m, 0) / 1000
-- Shared fare per passenger: fare * (10000 - share_discount_bps) / 10000, never above the ceiling.
-- Round each result to the nearest paisa (round half up).
CREATE TABLE fare_rules (
  id                    integer      GENERATED ALWAYS AS IDENTITY,
  vehicle_type          vehicle_type NOT NULL,
  base_paisa            bigint       NOT NULL,
  per_km_paisa          bigint       NOT NULL,
  base_distance_m       integer      NOT NULL DEFAULT 2000,
  ceiling_base_paisa    bigint       NOT NULL,
  ceiling_per_km_paisa  bigint       NOT NULL,
  share_discount_bps    integer      NOT NULL DEFAULT 2500,
  updated_by            integer,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT pk_fare_rules PRIMARY KEY (id),
  CONSTRAINT fk_fare_rules_updated_by FOREIGN KEY (updated_by) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT uq_fare_rules_vehicle_type UNIQUE (vehicle_type),
  CONSTRAINT ck_fare_rules_amounts CHECK (
    base_paisa >= 0 AND per_km_paisa >= 0 AND ceiling_base_paisa > 0 AND ceiling_per_km_paisa > 0),
  CONSTRAINT ck_fare_rules_base_distance CHECK (base_distance_m >= 0),
  -- A shared fare must always be lower than the solo fare (section 3).
  CONSTRAINT ck_fare_rules_share_discount CHECK (share_discount_bps BETWEEN 1 AND 9999),
  -- Legal Fare Guard for the tariff: both formulas share base_distance_m, so comparing
  -- them part by part proves fare(d) <= ceiling(d) for every distance d.
  CONSTRAINT ck_fare_rules_within_ceiling CHECK (base_paisa <= ceiling_base_paisa AND per_km_paisa <= ceiling_per_km_paisa)
);

-- The ceiling and its base distance are regulation (Taxicab Service Guidelines 2010), not
-- admin settings. If the admin could edit them, the Legal Fare Guard would be meaningless.
-- Change them only with a migration, which disables this trigger for that one UPDATE.
CREATE FUNCTION fare_rules_regulation_frozen() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.vehicle_type, NEW.base_distance_m, NEW.ceiling_base_paisa, NEW.ceiling_per_km_paisa)
     IS DISTINCT FROM (OLD.vehicle_type, OLD.base_distance_m, OLD.ceiling_base_paisa, OLD.ceiling_per_km_paisa) THEN
    RAISE EXCEPTION 'The legal ceiling of fare rule % is regulation; change it with a migration', OLD.id
      USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_fare_rules_regulation_frozen', TABLE = TG_TABLE_NAME;
  END IF;
  RETURN NEW;
END $$;

COMMENT ON TABLE  fare_rules IS 'pricing module. One rule per vehicle type. The admin edits base_paisa, per_km_paisa and share_discount_bps; the ceiling columns are frozen.';
COMMENT ON COLUMN fare_rules.base_distance_m IS 'Distance included in the base fare: the legal "first 2 km". Shared by the tariff and the ceiling formulas.';

-- =============================================================================
-- trips
-- =============================================================================

-- A ride is one vehicle trip. Riders join it through ride_passengers (many-to-many),
-- so a shared ride has several passengers, each with their own seats, PIN and fare.
CREATE TABLE rides (
  id             integer            GENERATED ALWAYS AS IDENTITY,
  vehicle_type   vehicle_type       NOT NULL,
  is_shared      boolean            NOT NULL DEFAULT false,
  seats_total    smallint           NOT NULL,
  seats_free     smallint           NOT NULL,
  status         ride_status        NOT NULL DEFAULT 'REQUESTED',
  driver_id      integer,
  vehicle_id     integer,
  version        integer            NOT NULL DEFAULT 1,
  cancel_reason  ride_cancel_reason,
  created_at     timestamptz        NOT NULL DEFAULT now(),
  accepted_at    timestamptz,
  started_at     timestamptz,
  completed_at   timestamptz,
  cancelled_at   timestamptz,
  updated_at     timestamptz        NOT NULL DEFAULT now(),
  CONSTRAINT pk_rides PRIMARY KEY (id),
  CONSTRAINT fk_rides_driver FOREIGN KEY (driver_id) REFERENCES driver_profiles (user_id) ON DELETE RESTRICT,
  -- The vehicle exists, belongs to this ride's driver and has the requested type.
  -- MATCH SIMPLE: not checked while vehicle_id is NULL (before a driver accepts).
  CONSTRAINT fk_rides_vehicle FOREIGN KEY (vehicle_id, driver_id, vehicle_type)
    REFERENCES vehicles (id, driver_id, type) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT ck_rides_seats_total CHECK (seats_total BETWEEN 1 AND 3),
  -- NFR-03: the database refuses an oversold seat even if application code has a bug.
  CONSTRAINT ck_rides_seats_free CHECK (seats_free BETWEEN 0 AND seats_total),
  -- A solo ride never gets a co-rider.
  CONSTRAINT ck_rides_solo_no_free_seats CHECK (is_shared OR seats_free = 0),
  -- Bikes are never shared and carry one passenger.
  CONSTRAINT ck_rides_bike_solo CHECK (vehicle_type <> 'BIKE' OR (NOT is_shared AND seats_total = 1)),
  CONSTRAINT ck_rides_version CHECK (version >= 1),
  CONSTRAINT ck_rides_driver_vehicle_pair CHECK ((driver_id IS NULL) = (vehicle_id IS NULL)),
  CONSTRAINT ck_rides_driver_by_status CHECK (
    CASE status
      WHEN 'REQUESTED' THEN driver_id IS NULL
      WHEN 'OFFERING'  THEN driver_id IS NULL
      WHEN 'CANCELLED' THEN true
      ELSE driver_id IS NOT NULL
    END),
  CONSTRAINT ck_rides_accepted_at CHECK (status IN ('REQUESTED', 'OFFERING', 'CANCELLED') OR accepted_at IS NOT NULL),
  CONSTRAINT ck_rides_started_at CHECK (status NOT IN ('IN_PROGRESS', 'AWAITING_HANDOVER', 'COMPLETED') OR started_at IS NOT NULL),
  CONSTRAINT ck_rides_completed CHECK ((status = 'COMPLETED') = (completed_at IS NOT NULL)),
  CONSTRAINT ck_rides_cancelled CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL)),
  CONSTRAINT ck_rides_cancel_reason CHECK ((status = 'CANCELLED') = (cancel_reason IS NOT NULL))
);
-- FR-HO-2 / NFR-03: no driver ever holds two active rides (two parallel accepts -> one 23505).
CREATE UNIQUE INDEX uq_rides_one_active_per_driver ON rides (driver_id)
  WHERE status IN ('ACCEPTED', 'ARRIVED', 'IN_PROGRESS', 'AWAITING_HANDOVER');
-- GET /rides/open: requests waiting for a driver, by vehicle type.
CREATE INDEX ix_rides_open ON rides (vehicle_type, created_at) WHERE status = 'REQUESTED';
-- GET /rides/my for drivers (cursor pagination on id).
CREATE INDEX ix_rides_driver ON rides (driver_id, id DESC) WHERE driver_id IS NOT NULL;
-- GET /rides for Support+: filter by status and date.
CREATE INDEX ix_rides_status_created ON rides (status, created_at DESC);
CREATE INDEX ix_rides_created ON rides (created_at DESC);
-- DELETE /vehicles/:id checks for live rides; also serves the composite foreign key.
CREATE INDEX ix_rides_vehicle ON rides (vehicle_id) WHERE vehicle_id IS NOT NULL;

COMMENT ON TABLE  rides IS 'trips module. One vehicle trip. Every transition is a conditional UPDATE (WHERE id = $1 AND status = $expected AND version = $v); 0 rows -> 409.';
COMMENT ON COLUMN rides.seats_total IS 'Bookable passenger seats: the vehicle type capacity, or seats_offered for a ride created from a route offer.';
COMMENT ON COLUMN rides.seats_free IS 'Seats other riders can still take. Solo rides: always 0. Shared rides: seats_total minus the seats of CONFIRMED and PICKED_UP passengers, updated in the same transaction as every passenger change.';
COMMENT ON COLUMN rides.version IS 'Bumped by trigger on every UPDATE. Socket events carry it; clients drop stale versions.';
COMMENT ON COLUMN rides.driver_id IS 'Current driver. Set once on accept; only a breakdown handover (AWAITING_HANDOVER) may replace it.';

-- =============================================================================
-- sharing
-- =============================================================================

-- "Going this way": a driver with free seats publishes the rest of their route.
CREATE TABLE route_offers (
  id             integer            GENERATED ALWAYS AS IDENTITY,
  driver_id      integer            NOT NULL,
  ride_id        integer,
  vehicle_id     integer            NOT NULL,
  vehicle_type   vehicle_type       NOT NULL,
  from_lat       geo_lat            NOT NULL,
  from_lng       geo_lng            NOT NULL,
  to_lat         geo_lat            NOT NULL,
  to_lng         geo_lng            NOT NULL,
  seats_offered  smallint           NOT NULL,
  status         route_offer_status NOT NULL DEFAULT 'OPEN',
  expires_at     timestamptz        NOT NULL,
  created_at     timestamptz        NOT NULL DEFAULT now(),
  updated_at     timestamptz        NOT NULL DEFAULT now(),
  CONSTRAINT pk_route_offers PRIMARY KEY (id),
  CONSTRAINT fk_route_offers_driver FOREIGN KEY (driver_id) REFERENCES driver_profiles (user_id) ON DELETE RESTRICT,
  CONSTRAINT fk_route_offers_ride FOREIGN KEY (ride_id) REFERENCES rides (id) ON DELETE RESTRICT,
  CONSTRAINT fk_route_offers_vehicle FOREIGN KEY (vehicle_id, driver_id, vehicle_type)
    REFERENCES vehicles (id, driver_id, type) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT ck_route_offers_seats CHECK (seats_offered BETWEEN 1 AND 3),
  CONSTRAINT ck_route_offers_not_bike CHECK (vehicle_type <> 'BIKE'),
  CONSTRAINT ck_route_offers_expiry CHECK (expires_at > created_at)
);
-- GET /route-offers/nearby: open offers by vehicle type (expiry is checked at query time).
CREATE INDEX ix_route_offers_open ON route_offers (vehicle_type, expires_at) WHERE status = 'OPEN';
CREATE INDEX ix_route_offers_driver ON route_offers (driver_id, id DESC);
CREATE INDEX ix_route_offers_ride ON route_offers (ride_id) WHERE ride_id IS NOT NULL;

COMMENT ON TABLE  route_offers IS 'sharing module. ride_id NULL = heading home with no ride yet; the first accepted join creates the ride (lock this row FOR UPDATE first).';
COMMENT ON COLUMN route_offers.expires_at IS 'Offer is live while status = OPEN AND expires_at > now(). Expiry is never stored as a status.';

-- A proposal to share a seat. It becomes a ride_passengers row (the contract) only
-- through the seat transaction, after both sides agree.
CREATE TABLE join_requests (
  id                 integer             GENERATED ALWAYS AS IDENTITY,
  ride_id            integer,
  route_offer_id     integer,
  rider_id           integer             NOT NULL,
  driver_id          integer             NOT NULL,
  initiated_by       join_initiator      NOT NULL,
  seats              smallint            NOT NULL DEFAULT 1,
  pickup_lat         geo_lat             NOT NULL,
  pickup_lng         geo_lng             NOT NULL,
  drop_lat           geo_lat             NOT NULL,
  drop_lng           geo_lng             NOT NULL,
  distance_m         integer             NOT NULL,
  quoted_fare_paisa  bigint              NOT NULL,
  ceiling_paisa      bigint              NOT NULL,
  pricing_snapshot   jsonb               NOT NULL,
  status             join_request_status NOT NULL DEFAULT 'PENDING',
  expires_at         timestamptz         NOT NULL,
  decided_at         timestamptz,
  created_at         timestamptz         NOT NULL DEFAULT now(),
  updated_at         timestamptz         NOT NULL DEFAULT now(),
  CONSTRAINT pk_join_requests PRIMARY KEY (id),
  CONSTRAINT fk_join_requests_ride FOREIGN KEY (ride_id) REFERENCES rides (id) ON DELETE RESTRICT,
  CONSTRAINT fk_join_requests_route_offer FOREIGN KEY (route_offer_id) REFERENCES route_offers (id) ON DELETE RESTRICT,
  CONSTRAINT fk_join_requests_rider FOREIGN KEY (rider_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT fk_join_requests_driver FOREIGN KEY (driver_id) REFERENCES driver_profiles (user_id) ON DELETE RESTRICT,
  -- Exactly one target. Through an offer, the ride is found via route_offers.ride_id.
  CONSTRAINT ck_join_requests_one_target CHECK (num_nonnulls(ride_id, route_offer_id) = 1),
  -- FR-SH-1: a shared booking is 1 or 2 seats.
  CONSTRAINT ck_join_requests_seats CHECK (seats BETWEEN 1 AND 2),
  CONSTRAINT ck_join_requests_distance CHECK (distance_m > 0),
  CONSTRAINT ck_join_requests_quoted_fare CHECK (quoted_fare_paisa > 0),
  CONSTRAINT ck_join_requests_fare_within_ceiling CHECK (quoted_fare_paisa <= ceiling_paisa),
  CONSTRAINT ck_join_requests_pricing_snapshot CHECK (jsonb_typeof(pricing_snapshot) = 'object'),
  CONSTRAINT ck_join_requests_rider_not_driver CHECK (rider_id <> driver_id),
  CONSTRAINT ck_join_requests_expiry CHECK (expires_at > created_at),
  CONSTRAINT ck_join_requests_decided CHECK (status NOT IN ('ACCEPTED', 'DECLINED') OR decided_at IS NOT NULL)
);
-- GET /join-requests/my: sent or received, for riders and for drivers.
CREATE INDEX ix_join_requests_rider ON join_requests (rider_id, id DESC);
CREATE INDEX ix_join_requests_driver ON join_requests (driver_id, id DESC);
CREATE INDEX ix_join_requests_ride ON join_requests (ride_id) WHERE ride_id IS NOT NULL;
CREATE INDEX ix_join_requests_route_offer ON join_requests (route_offer_id) WHERE route_offer_id IS NOT NULL;
-- Lazy expiry sweep: PENDING requests past expires_at become EXPIRED.
CREATE INDEX ix_join_requests_pending_expiry ON join_requests (expires_at) WHERE status = 'PENDING';

COMMENT ON TABLE  join_requests IS 'sharing module. A rider asks to join (initiated_by RIDER) or a driver invites a waiting rider (initiated_by DRIVER). The other party answers.';
COMMENT ON COLUMN join_requests.driver_id IS 'The driver on the other side, copied from the ride or offer at creation. Used for "my requests" and authorisation.';
COMMENT ON COLUMN join_requests.quoted_fare_paisa IS 'Shared fare shown to the rider. Copied to ride_passengers.locked_fare_paisa when accepted; later joins never raise it.';
COMMENT ON COLUMN join_requests.expires_at IS 'Rider requests: driver must answer within 12 s; driver invites: rider within 60 s (configurable). No answer counts as no.';

-- =============================================================================
-- trips (continued): passengers link users and rides many-to-many
-- =============================================================================

CREATE TABLE ride_passengers (
  id                 integer          GENERATED ALWAYS AS IDENTITY,
  ride_id            integer          NOT NULL,
  rider_id           integer          NOT NULL,
  join_request_id    integer,
  seats              smallint         NOT NULL DEFAULT 1,
  status             passenger_status NOT NULL DEFAULT 'CONFIRMED',
  pickup_lat         geo_lat          NOT NULL,
  pickup_lng         geo_lng          NOT NULL,
  drop_lat           geo_lat          NOT NULL,
  drop_lng           geo_lng          NOT NULL,
  distance_m         integer          NOT NULL,
  locked_fare_paisa  bigint           NOT NULL,
  ceiling_paisa      bigint           NOT NULL,
  pricing_snapshot   jsonb            NOT NULL,
  pickup_pin         varchar(4)       NOT NULL,
  arrived_at         timestamptz,
  picked_up_at       timestamptz,
  dropped_at         timestamptz,
  cancelled_at       timestamptz,
  created_at         timestamptz      NOT NULL DEFAULT now(),
  updated_at         timestamptz      NOT NULL DEFAULT now(),
  CONSTRAINT pk_ride_passengers PRIMARY KEY (id),
  CONSTRAINT fk_ride_passengers_ride FOREIGN KEY (ride_id) REFERENCES rides (id) ON DELETE RESTRICT,
  CONSTRAINT fk_ride_passengers_rider FOREIGN KEY (rider_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT fk_ride_passengers_join_request FOREIGN KEY (join_request_id) REFERENCES join_requests (id) ON DELETE RESTRICT,
  -- A join request creates at most one seat.
  CONSTRAINT uq_ride_passengers_join_request UNIQUE (join_request_id),
  CONSTRAINT ck_ride_passengers_seats CHECK (seats BETWEEN 1 AND 3),
  CONSTRAINT ck_ride_passengers_distance CHECK (distance_m > 0),
  CONSTRAINT ck_ride_passengers_fare CHECK (locked_fare_paisa > 0),
  -- Legal Fare Guard: the fare locked at booking never exceeds the ceiling applied to it.
  CONSTRAINT ck_ride_passengers_fare_within_ceiling CHECK (locked_fare_paisa <= ceiling_paisa),
  CONSTRAINT ck_ride_passengers_pricing_snapshot CHECK (jsonb_typeof(pricing_snapshot) = 'object'),
  CONSTRAINT ck_ride_passengers_pickup_pin CHECK (pickup_pin ~ '^[0-9]{4}$'),
  -- The driver must arrive before a pickup, and NO_SHOW is only possible after arriving
  -- (the 5-minute wait is measured from arrived_at).
  CONSTRAINT ck_ride_passengers_picked_up CHECK (
    status NOT IN ('PICKED_UP', 'DROPPED') OR (arrived_at IS NOT NULL AND picked_up_at IS NOT NULL)),
  CONSTRAINT ck_ride_passengers_no_show CHECK (status <> 'NO_SHOW' OR arrived_at IS NOT NULL),
  CONSTRAINT ck_ride_passengers_dropped CHECK ((status = 'DROPPED') = (dropped_at IS NOT NULL)),
  CONSTRAINT ck_ride_passengers_cancelled CHECK ((status IN ('CANCELLED', 'NO_SHOW')) = (cancelled_at IS NOT NULL))
);
-- One live seat per rider: a rider can't be booked on two rides at once. A partial
-- unique index can't be deferred, so the seat transaction cancels a waiting rider's own
-- REQUESTED seat BEFORE it inserts the new one.
CREATE UNIQUE INDEX uq_ride_passengers_one_live_seat_per_rider ON ride_passengers (rider_id)
  WHERE status IN ('CONFIRMED', 'PICKED_UP');
CREATE INDEX ix_ride_passengers_ride ON ride_passengers (ride_id);
-- GET /rides/my for riders (cursor pagination on id).
CREATE INDEX ix_ride_passengers_rider ON ride_passengers (rider_id, id DESC);

COMMENT ON TABLE  ride_passengers IS 'trips module. Junction for users M:N rides: one row per rider per ride, with their own seats, PIN, stops, fare and state.';
COMMENT ON COLUMN ride_passengers.join_request_id IS 'The accepted join request that created this seat. NULL for the rider who booked the ride.';
COMMENT ON COLUMN ride_passengers.seats IS 'Seats this passenger occupies. Shared bookings: 1 or 2 (FR-SH-1). Solo: the party size.';
COMMENT ON COLUMN ride_passengers.pricing_snapshot IS 'Rule id, inputs, discount and ceiling used for this fare, so a dispute can be reproduced after the rule is edited.';
COMMENT ON COLUMN ride_passengers.pickup_pin IS 'Shown only to this rider; the driver types it at pickup. Never returned to drivers or co-riders.';

-- -----------------------------------------------------------------------------
-- Ride guards (they read ride_passengers, so they are created after it)
-- -----------------------------------------------------------------------------
CREATE FUNCTION rides_update_guards() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- 1. Every change produces a new version (optimistic concurrency, stale socket events).
  NEW.version := OLD.version + 1;

  -- 2. Exactly one winner: an assigned driver is never silently replaced. Only a breakdown
  --    handover (AWAITING_HANDOVER) may give the ride to a new driver.
  IF OLD.driver_id IS NOT NULL
     AND NEW.driver_id IS DISTINCT FROM OLD.driver_id
     AND OLD.status <> 'AWAITING_HANDOVER' THEN
    RAISE EXCEPTION 'Ride % already has driver %', OLD.id, OLD.driver_id
      USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_rides_driver_locked', TABLE = TG_TABLE_NAME;
  END IF;

  -- 3. A ride finishes only after every passenger is closed (DROPPED, CANCELLED or
  --    NO_SHOW). Otherwise that rider keeps a live seat and can never book again.
  IF NEW.status IN ('COMPLETED', 'CANCELLED')
     AND NEW.status IS DISTINCT FROM OLD.status
     AND EXISTS (SELECT 1 FROM ride_passengers p
                  WHERE p.ride_id = NEW.id AND p.status IN ('CONFIRMED', 'PICKED_UP')) THEN
    RAISE EXCEPTION 'Ride % still has waiting or onboard passengers; close them first', NEW.id
      USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_rides_close_with_live_passengers', TABLE = TG_TABLE_NAME;
  END IF;

  RETURN NEW;
END $$;

-- BEFORE triggers on one table fire in name order: status_transition, update_guards, updated_at.
CREATE TRIGGER trg_rides_status_transition
  BEFORE UPDATE OF status ON rides
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION enforce_status_transition(
    'REQUESTED>OFFERING', 'REQUESTED>ACCEPTED', 'REQUESTED>CANCELLED',
    'OFFERING>ACCEPTED', 'OFFERING>CANCELLED',
    'ACCEPTED>ARRIVED', 'ACCEPTED>CANCELLED',
    'ARRIVED>IN_PROGRESS', 'ARRIVED>CANCELLED',
    'IN_PROGRESS>COMPLETED', 'IN_PROGRESS>AWAITING_HANDOVER', 'IN_PROGRESS>CANCELLED',
    'AWAITING_HANDOVER>IN_PROGRESS', 'AWAITING_HANDOVER>CANCELLED');

CREATE TRIGGER trg_rides_update_guards
  BEFORE UPDATE ON rides
  FOR EACH ROW EXECUTE FUNCTION rides_update_guards();

CREATE TRIGGER trg_ride_passengers_status_transition
  BEFORE UPDATE OF status ON ride_passengers
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION enforce_status_transition(
    'CONFIRMED>PICKED_UP', 'CONFIRMED>CANCELLED', 'CONFIRMED>NO_SHOW',
    'PICKED_UP>DROPPED');

CREATE TRIGGER trg_join_requests_status_transition
  BEFORE UPDATE OF status ON join_requests
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION enforce_status_transition(
    'PENDING>ACCEPTED', 'PENDING>DECLINED', 'PENDING>EXPIRED');

CREATE TRIGGER trg_fare_rules_regulation_frozen
  BEFORE UPDATE OF vehicle_type, base_distance_m, ceiling_base_paisa, ceiling_per_km_paisa ON fare_rules
  FOR EACH ROW EXECUTE FUNCTION fare_rules_regulation_frozen();

CREATE TABLE ratings (
  id            integer      GENERATED ALWAYS AS IDENTITY,
  ride_id       integer      NOT NULL,
  from_user_id  integer      NOT NULL,
  to_user_id    integer      NOT NULL,
  stars         smallint     NOT NULL,
  comment       varchar(500),
  created_at    timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT pk_ratings PRIMARY KEY (id),
  CONSTRAINT fk_ratings_ride FOREIGN KEY (ride_id) REFERENCES rides (id) ON DELETE RESTRICT,
  CONSTRAINT fk_ratings_from_user FOREIGN KEY (from_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT fk_ratings_to_user FOREIGN KEY (to_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  -- One rating per direction per ride: a rider can rate the driver and each co-rider once.
  CONSTRAINT uq_ratings_ride_from_to UNIQUE (ride_id, from_user_id, to_user_id),
  CONSTRAINT ck_ratings_stars CHECK (stars BETWEEN 1 AND 5),
  CONSTRAINT ck_ratings_not_self CHECK (from_user_id <> to_user_id)
);
-- A user's rating is computed on read: SELECT avg(stars), count(*) WHERE to_user_id = $1
-- (an index-only scan), so there is no stored average to drift.
CREATE INDEX ix_ratings_to_user ON ratings (to_user_id) INCLUDE (stars);

COMMENT ON TABLE ratings IS 'trips module. Stars from one user to another for a ride (driver <-> passenger, passenger <-> co-rider).';

-- =============================================================================
-- trust
-- =============================================================================

CREATE TABLE support_cases (
  id                    integer     GENERATED ALWAYS AS IDENTITY,
  type                  case_type   NOT NULL,
  status                case_status NOT NULL DEFAULT 'OPEN',
  reporter_id           integer     NOT NULL,
  subject_id            integer,
  ride_id               integer,
  assigned_to           integer,
  description           text        NOT NULL,
  amount_claimed_paisa  bigint,
  resolution            text,
  resolved_at           timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_support_cases PRIMARY KEY (id),
  CONSTRAINT fk_support_cases_reporter FOREIGN KEY (reporter_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT fk_support_cases_subject FOREIGN KEY (subject_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT fk_support_cases_ride FOREIGN KEY (ride_id) REFERENCES rides (id) ON DELETE RESTRICT,
  CONSTRAINT fk_support_cases_assigned_to FOREIGN KEY (assigned_to) REFERENCES users (id) ON DELETE RESTRICT,
  -- Target of strikes(case_id, user_id): a strike can only name the case's subject.
  CONSTRAINT uq_support_cases_id_subject UNIQUE (id, subject_id),
  CONSTRAINT ck_support_cases_description CHECK (char_length(btrim(description)) BETWEEN 1 AND 4000),
  CONSTRAINT ck_support_cases_not_self CHECK (subject_id IS NULL OR subject_id <> reporter_id),
  -- OVERCHARGE: what the driver demanded (e.g. Tk 300 against a Tk 260 locked fare).
  CONSTRAINT ck_support_cases_amount_claimed CHECK (
    amount_claimed_paisa IS NULL OR (type = 'OVERCHARGE' AND amount_claimed_paisa > 0)),
  -- Every decision has a written reason, a time and a named officer.
  CONSTRAINT ck_support_cases_decision CHECK (
    status NOT IN ('UPHELD', 'DISMISSED') OR (resolution IS NOT NULL AND resolved_at IS NOT NULL AND assigned_to IS NOT NULL)),
  CONSTRAINT ck_support_cases_resolution CHECK (resolution IS NULL OR char_length(resolution) <= 4000)
);
-- GET /cases: the queue, filtered by status.
CREATE INDEX ix_support_cases_status ON support_cases (status, id DESC);
CREATE INDEX ix_support_cases_reporter ON support_cases (reporter_id, id DESC);
CREATE INDEX ix_support_cases_subject ON support_cases (subject_id) WHERE subject_id IS NOT NULL;
CREATE INDEX ix_support_cases_ride ON support_cases (ride_id) WHERE ride_id IS NOT NULL;

COMMENT ON TABLE  support_cases IS 'trust module. Complaints about an overcharge, safety or a co-rider. "cases" in the API. DELETE /cases/:id sets WITHDRAWN.';

CREATE TABLE strikes (
  id          integer       GENERATED ALWAYS AS IDENTITY,
  user_id     integer       NOT NULL,
  case_id     integer       NOT NULL,
  issued_by   integer       NOT NULL,
  reason      text          NOT NULL,
  status      strike_status NOT NULL DEFAULT 'ACTIVE',
  issued_at   timestamptz   NOT NULL DEFAULT now(),
  expires_at  timestamptz   NOT NULL,
  revoked_at  timestamptz,
  created_at  timestamptz   NOT NULL DEFAULT now(),
  updated_at  timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT pk_strikes PRIMARY KEY (id),
  CONSTRAINT fk_strikes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  -- Due process: a strike comes from a case and names that case's subject.
  CONSTRAINT fk_strikes_case_subject FOREIGN KEY (case_id, user_id)
    REFERENCES support_cases (id, subject_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_strikes_issued_by FOREIGN KEY (issued_by) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT ck_strikes_reason CHECK (char_length(btrim(reason)) BETWEEN 1 AND 2000),
  CONSTRAINT ck_strikes_not_self CHECK (issued_by <> user_id),
  CONSTRAINT ck_strikes_window CHECK (expires_at > issued_at),
  CONSTRAINT ck_strikes_revoked CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL))
);
-- One standing strike per person per case (a double-clicked POST /strikes gets 409).
CREATE UNIQUE INDEX uq_strikes_case_user_live ON strikes (case_id, user_id) WHERE status <> 'REVOKED';
-- GET /strikes?userId=..., and the threshold count (ACTIVE, unexpired, no PENDING appeal).
CREATE INDEX ix_strikes_user ON strikes (user_id, status, expires_at);

COMMENT ON TABLE  strikes IS 'trust module. Applies to riders and drivers (FR-TS-5). Counts toward thresholds while ACTIVE, expires_at > now() and no appeal is PENDING. DELETE /strikes/:id sets REVOKED.';
COMMENT ON COLUMN strikes.issued_by IS 'Officer who issued the strike. That officer can never decide its appeal (separation of duties).';

CREATE TABLE appeals (
  id               integer       GENERATED ALWAYS AS IDENTITY,
  strike_id        integer       NOT NULL,
  statement        text          NOT NULL,
  status           appeal_status NOT NULL DEFAULT 'PENDING',
  decided_by       integer,
  decision_reason  text,
  decided_at       timestamptz,
  created_at       timestamptz   NOT NULL DEFAULT now(),
  updated_at       timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT pk_appeals PRIMARY KEY (id),
  CONSTRAINT fk_appeals_strike FOREIGN KEY (strike_id) REFERENCES strikes (id) ON DELETE RESTRICT,
  CONSTRAINT fk_appeals_decided_by FOREIGN KEY (decided_by) REFERENCES users (id) ON DELETE RESTRICT,
  -- A strike can be appealed once.
  CONSTRAINT uq_appeals_strike UNIQUE (strike_id),
  CONSTRAINT ck_appeals_statement CHECK (char_length(btrim(statement)) BETWEEN 1 AND 4000),
  CONSTRAINT ck_appeals_decision CHECK (
    status = 'PENDING' OR (decided_by IS NOT NULL AND decision_reason IS NOT NULL AND decided_at IS NOT NULL)),
  CONSTRAINT ck_appeals_pending CHECK (status <> 'PENDING' OR (decided_by IS NULL AND decided_at IS NULL))
);
-- 72-hour decision SLA: scan only pending appeals.
CREATE INDEX ix_appeals_pending ON appeals (created_at) WHERE status = 'PENDING';

COMMENT ON TABLE appeals IS 'trust module. Accepting an appeal sets its strike to OVERTURNED in the same transaction.';

-- FR-TS-4: the officer who issued a strike (or the struck user) can't decide its appeal.
-- The API returns 403 before this runs; the trigger is the backstop.
CREATE FUNCTION appeals_separation_of_duties() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_issued_by integer;
  v_struck    integer;
BEGIN
  IF NEW.decided_by IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT s.issued_by, s.user_id INTO v_issued_by, v_struck FROM strikes s WHERE s.id = NEW.strike_id;
  IF NEW.decided_by IN (v_issued_by, v_struck) THEN
    RAISE EXCEPTION 'User % issued or received strike % and cannot decide its appeal', NEW.decided_by, NEW.strike_id
      USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_appeals_separation_of_duties', TABLE = TG_TABLE_NAME;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_appeals_separation_of_duties
  BEFORE INSERT OR UPDATE OF decided_by, strike_id ON appeals
  FOR EACH ROW EXECUTE FUNCTION appeals_separation_of_duties();

-- =============================================================================
-- audit
-- =============================================================================

CREATE TABLE audit_logs (
  id          bigint       GENERATED ALWAYS AS IDENTITY,
  user_id     integer,
  action      varchar(100) NOT NULL,
  entity      varchar(50)  NOT NULL,
  entity_id   varchar(64),
  old_value   jsonb,
  new_value   jsonb,
  ip_address  inet,
  request_id  varchar(64),
  created_at  timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT pk_audit_logs PRIMARY KEY (id),
  CONSTRAINT fk_audit_logs_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  -- Backstop for the AuditInterceptor: an append-only table must never receive a secret,
  -- because it could never be deleted. (Top-level keys only; the interceptor allowlists fields.)
  CONSTRAINT ck_audit_logs_no_secrets CHECK (
    NOT (COALESCE(old_value, '{}'::jsonb) ?| ARRAY['password', 'passwordHash', 'password_hash', 'pickupPin', 'pickup_pin'])
    AND NOT (COALESCE(new_value, '{}'::jsonb) ?| ARRAY['password', 'passwordHash', 'password_hash', 'pickupPin', 'pickup_pin']))
);
-- GET /audit-logs: filter by entity, by user and by date; cursor pagination on id.
CREATE INDEX ix_audit_logs_entity ON audit_logs (entity, entity_id, id DESC);
CREATE INDEX ix_audit_logs_user ON audit_logs (user_id, id DESC) WHERE user_id IS NOT NULL;
CREATE INDEX ix_audit_logs_created ON audit_logs (created_at);

COMMENT ON TABLE  audit_logs IS 'audit module. Append-only record of every POST, PUT, PATCH and DELETE. entity + entity_id point at any table (no foreign key).';
COMMENT ON COLUMN audit_logs.user_id IS 'Who acted. NULL = system or scheduled job.';

CREATE TRIGGER trg_audit_logs_append_only
  BEFORE UPDATE OR DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION forbid_update_delete();

-- -----------------------------------------------------------------------------
-- updated_at maintenance on every mutable table
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_users_updated_at           BEFORE UPDATE ON users           FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_driver_profiles_updated_at BEFORE UPDATE ON driver_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_vehicles_updated_at        BEFORE UPDATE ON vehicles        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_fare_rules_updated_at      BEFORE UPDATE ON fare_rules      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_rides_updated_at           BEFORE UPDATE ON rides           FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_route_offers_updated_at    BEFORE UPDATE ON route_offers    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_join_requests_updated_at   BEFORE UPDATE ON join_requests   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ride_passengers_updated_at BEFORE UPDATE ON ride_passengers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_support_cases_updated_at   BEFORE UPDATE ON support_cases   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_strikes_updated_at         BEFORE UPDATE ON strikes         FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_appeals_updated_at         BEFORE UPDATE ON appeals         FOR EACH ROW EXECUTE FUNCTION set_updated_at();
