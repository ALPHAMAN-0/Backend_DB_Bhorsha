import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  type Relation,
  UpdateDateColumn,
} from 'typeorm';
import { GeoColumn, PaisaColumn, TimestampColumn } from '../columns.js';
import { DriverProfile } from './driver-profile.entity.js';
import { JoinInitiator, JoinRequestStatus } from './enums.js';
import type { PricingSnapshot } from './pricing-snapshot.js';
import { Ride } from './ride.entity.js';
import { RouteOffer } from './route-offer.entity.js';
import { User } from './user.entity.js';

/**
 * sharing module. A proposal to share a seat: a rider asks to join (initiatedBy RIDER) or a
 * driver invites a waiting rider (initiatedBy DRIVER); the other party answers. It becomes a
 * RidePassenger (the contract) only through the seat transaction.
 * Exactly one target: rideId or routeOfferId (ck_join_requests_one_target).
 */
@Entity('join_requests')
export class JoinRequest {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  @Column({ type: 'integer', nullable: true })
  rideId!: number | null;

  @ManyToOne(() => Ride, { nullable: true })
  @JoinColumn({ name: 'ride_id' })
  ride!: Relation<Ride> | null;

  @Column({ type: 'integer', nullable: true })
  routeOfferId!: number | null;

  @ManyToOne(() => RouteOffer, { nullable: true })
  @JoinColumn({ name: 'route_offer_id' })
  routeOffer!: Relation<RouteOffer> | null;

  @Column({ type: 'integer' })
  riderId!: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'rider_id' })
  rider!: Relation<User>;

  /** The driver on the other side, copied from the ride or offer: used for "my requests" and authorisation. */
  @Column({ type: 'integer' })
  driverId!: number;

  @ManyToOne(() => DriverProfile)
  @JoinColumn({ name: 'driver_id' })
  driver!: Relation<DriverProfile>;

  @Column({ type: 'enum', enum: JoinInitiator, enumName: 'join_initiator' })
  initiatedBy!: JoinInitiator;

  /** 1 or 2 (FR-SH-1). */
  @Column({ type: 'smallint', default: 1 })
  seats!: number;

  @GeoColumn()
  pickupLat!: number;

  @GeoColumn()
  pickupLng!: number;

  @GeoColumn()
  dropLat!: number;

  @GeoColumn()
  dropLng!: number;

  @Column({ type: 'integer' })
  distanceM!: number;

  /** Shared fare shown to the rider; becomes RidePassenger.lockedFarePaisa when accepted. */
  @PaisaColumn()
  quotedFarePaisa!: number;

  @PaisaColumn()
  ceilingPaisa!: number;

  @Column({ type: 'jsonb' })
  pricingSnapshot!: PricingSnapshot;

  @Column({ type: 'enum', enum: JoinRequestStatus, enumName: 'join_request_status', default: JoinRequestStatus.PENDING })
  status!: JoinRequestStatus;

  /** Rider requests: 12 s; driver invites: 60 s (configurable). No answer counts as no. */
  @Column({ type: 'timestamptz' })
  expiresAt!: Date;

  /** Required for ACCEPTED and DECLINED. */
  @TimestampColumn({ nullable: true })
  decidedAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
