import { Appeal } from './appeal.entity.js';
import { AuditLog } from './audit-log.entity.js';
import { DriverProfile } from './driver-profile.entity.js';
import { FareRule } from './fare-rule.entity.js';
import { JoinRequest } from './join-request.entity.js';
import { Rating } from './rating.entity.js';
import { RidePassenger } from './ride-passenger.entity.js';
import { Ride } from './ride.entity.js';
import { RouteOffer } from './route-offer.entity.js';
import { Strike } from './strike.entity.js';
import { SupportCase } from './support-case.entity.js';
import { User } from './user.entity.js';
import { Vehicle } from './vehicle.entity.js';

export * from './enums.js';
export type { PricingSnapshot } from './pricing-snapshot.js';
export {
  Appeal, AuditLog, DriverProfile, FareRule, JoinRequest, Rating, Ride, RidePassenger, RouteOffer,
  Strike, SupportCase, User, Vehicle,
};

/** All 13 tables, grouped by owning module. Registered once in the root TypeORM config. */
export const ENTITIES = [
  // identity
  User,
  // fleet
  DriverProfile, Vehicle,
  // pricing
  FareRule,
  // trips
  Ride, RidePassenger, Rating,
  // sharing
  RouteOffer, JoinRequest,
  // trust
  SupportCase, Strike, Appeal,
  // audit
  AuditLog,
];
