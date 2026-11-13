// Mirrors the PostgreSQL enum types in db/init/01_schema.sql. The enumName on each @Column
// must match the Postgres type name. synchronize is off, so TypeORM never creates them.

export enum UserRole { RIDER = 'RIDER', DRIVER = 'DRIVER', ADMIN = 'ADMIN', SUPPORT = 'SUPPORT' }
export enum DriverVerification { PENDING = 'PENDING', VERIFIED = 'VERIFIED', REJECTED = 'REJECTED' }
export enum DriverStatus { OFFLINE = 'OFFLINE', ONLINE = 'ONLINE' }
export enum VehicleType { BIKE = 'BIKE', CAR = 'CAR', CNG = 'CNG' }

/** Ride state machine (architecture document, section 8). Edges are enforced by a trigger. */
export enum RideStatus {
  REQUESTED = 'REQUESTED',
  /** Full product only (dispatch waves). Not used by the course release. */
  OFFERING = 'OFFERING',
  ACCEPTED = 'ACCEPTED',
  ARRIVED = 'ARRIVED',
  IN_PROGRESS = 'IN_PROGRESS',
  /** Full product only (breakdown handover). Not used by the course release. */
  AWAITING_HANDOVER = 'AWAITING_HANDOVER',
  COMPLETED = 'COMPLETED',
  CANCELLED = 'CANCELLED',
}

export enum RideCancelReason {
  RIDER_CANCELLED = 'RIDER_CANCELLED',
  DRIVER_CANCELLED = 'DRIVER_CANCELLED',
  NO_DRIVER_FOUND = 'NO_DRIVER_FOUND',
  HANDOVER_FAILED = 'HANDOVER_FAILED',
  JOINED_ANOTHER_RIDE = 'JOINED_ANOTHER_RIDE',
}

/** Passenger state machine (section 12). Edges are enforced by a trigger. */
export enum PassengerStatus {
  CONFIRMED = 'CONFIRMED',
  PICKED_UP = 'PICKED_UP',
  DROPPED = 'DROPPED',
  CANCELLED = 'CANCELLED',
  NO_SHOW = 'NO_SHOW',
}

export enum RouteOfferStatus { OPEN = 'OPEN', CLOSED = 'CLOSED', WITHDRAWN = 'WITHDRAWN' }
export enum JoinInitiator { RIDER = 'RIDER', DRIVER = 'DRIVER' }

/** Join request state machine (section 12). Edges are enforced by a trigger. */
export enum JoinRequestStatus { PENDING = 'PENDING', ACCEPTED = 'ACCEPTED', DECLINED = 'DECLINED', EXPIRED = 'EXPIRED' }

export enum CaseType { OVERCHARGE = 'OVERCHARGE', SAFETY = 'SAFETY', CONDUCT = 'CONDUCT', OTHER = 'OTHER' }
export enum CaseStatus {
  OPEN = 'OPEN',
  UNDER_REVIEW = 'UNDER_REVIEW',
  UPHELD = 'UPHELD',
  DISMISSED = 'DISMISSED',
  WITHDRAWN = 'WITHDRAWN',
}
export enum StrikeStatus { ACTIVE = 'ACTIVE', OVERTURNED = 'OVERTURNED', REVOKED = 'REVOKED' }
export enum AppealStatus { PENDING = 'PENDING', ACCEPTED = 'ACCEPTED', REJECTED = 'REJECTED' }

/** A driver holds at most one ride in these statuses (unique index uq_rides_one_active_per_driver). */
export const ACTIVE_RIDE_STATUSES = [
  RideStatus.ACCEPTED,
  RideStatus.ARRIVED,
  RideStatus.IN_PROGRESS,
  RideStatus.AWAITING_HANDOVER,
] as const;

/** A rider holds at most one seat in these statuses (uq_ride_passengers_one_live_seat_per_rider). */
export const LIVE_PASSENGER_STATUSES = [PassengerStatus.CONFIRMED, PassengerStatus.PICKED_UP] as const;

/** Passenger seats per vehicle type (section 12: "Seat capacity is configuration"). */
export const SEAT_CAPACITY: Readonly<Record<VehicleType, number>> = {
  [VehicleType.BIKE]: 1,
  [VehicleType.CAR]: 3,
  [VehicleType.CNG]: 2,
};
