import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  OneToOne,
  PrimaryGeneratedColumn,
  type Relation,
  UpdateDateColumn,
} from 'typeorm';
import { GeoColumn, PaisaColumn, TimestampColumn } from '../columns.js';
import { PassengerStatus } from './enums.js';
import { JoinRequest } from './join-request.entity.js';
import type { PricingSnapshot } from './pricing-snapshot.js';
import { Ride } from './ride.entity.js';
import { User } from './user.entity.js';

/**
 * trips module. The users M:N rides junction, mapped as its own entity: one row per rider
 * per ride, with their own seats, stops, PIN, locked fare and state.
 * A rider holds at most one CONFIRMED or PICKED_UP seat (uq_ride_passengers_one_live_seat_per_rider).
 */
@Entity('ride_passengers')
export class RidePassenger {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  @Column({ type: 'integer' })
  rideId!: number;

  @ManyToOne(() => Ride, (ride) => ride.passengers)
  @JoinColumn({ name: 'ride_id' })
  ride!: Relation<Ride>;

  @Column({ type: 'integer' })
  riderId!: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'rider_id' })
  rider!: Relation<User>;

  /** The accepted join request that created this seat; null for the rider who booked the ride. */
  @Column({ type: 'integer', nullable: true })
  joinRequestId!: number | null;

  @OneToOne(() => JoinRequest, { nullable: true })
  @JoinColumn({ name: 'join_request_id' })
  joinRequest!: Relation<JoinRequest> | null;

  /** Shared bookings: 1 or 2 (FR-SH-1). Solo: the party size. */
  @Column({ type: 'smallint', default: 1 })
  seats!: number;

  @Column({ type: 'enum', enum: PassengerStatus, enumName: 'passenger_status', default: PassengerStatus.CONFIRMED })
  status!: PassengerStatus;

  @GeoColumn()
  pickupLat!: number;

  @GeoColumn()
  pickupLng!: number;

  @GeoColumn()
  dropLat!: number;

  @GeoColumn()
  dropLng!: number;

  /** This passenger's own trip distance in metres (straight-line in the course release). */
  @Column({ type: 'integer' })
  distanceM!: number;

  /** Locked at booking; never raised by later joins or detours. <= ceilingPaisa (Legal Fare Guard). */
  @PaisaColumn()
  lockedFarePaisa!: number;

  @PaisaColumn()
  ceilingPaisa!: number;

  @Column({ type: 'jsonb' })
  pricingSnapshot!: PricingSnapshot;

  /** Four digits, shown only to this rider; the driver types it at pickup. Never selected by default. */
  @Column({ type: 'varchar', length: 4, select: false })
  pickupPin!: string;

  /** Driver arrived at this passenger's pickup; NO_SHOW is allowed 5 minutes after this. */
  @TimestampColumn({ nullable: true })
  arrivedAt!: Date | null;

  @TimestampColumn({ nullable: true })
  pickedUpAt!: Date | null;

  @TimestampColumn({ nullable: true })
  droppedAt!: Date | null;

  /** Set for CANCELLED and NO_SHOW. */
  @TimestampColumn({ nullable: true })
  cancelledAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
