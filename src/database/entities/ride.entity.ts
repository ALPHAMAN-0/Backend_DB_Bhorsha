import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  OneToMany,
  PrimaryGeneratedColumn,
  type Relation,
  UpdateDateColumn,
  VersionColumn,
} from 'typeorm';
import { TimestampColumn } from '../columns.js';
import { DriverProfile } from './driver-profile.entity.js';
import { RideCancelReason, RideStatus, VehicleType } from './enums.js';
import { RidePassenger } from './ride-passenger.entity.js';
import { Vehicle } from './vehicle.entity.js';

/**
 * trips module. One vehicle trip; riders join through RidePassenger (many-to-many).
 *
 * Every transition is a conditional update through QueryBuilder:
 *   UPDATE rides SET ... WHERE id = :id AND status = :expected AND version = :version
 * and the caller checks result.affected (0 -> 409). save() never adds the version check.
 */
@Entity('rides')
export class Ride {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  /** Requested vehicle type; the accepted vehicle must have it (composite FK fk_rides_vehicle). */
  @Column({ type: 'enum', enum: VehicleType, enumName: 'vehicle_type' })
  vehicleType!: VehicleType;

  /** Bikes are never shared (ck_rides_bike_solo). */
  @Column({ type: 'boolean', default: false })
  isShared!: boolean;

  /** SEAT_CAPACITY[vehicleType], or seatsOffered for a ride created from a route offer. */
  @Column({ type: 'smallint' })
  seatsTotal!: number;

  /**
   * Seats other riders can still take: 0 for solo rides; for shared rides, seatsTotal minus the
   * seats of CONFIRMED and PICKED_UP passengers. Change it in the SAME transaction as every
   * passenger change. 0 <= seatsFree <= seatsTotal (ck_rides_seats_free -> "Seat no longer available").
   */
  @Column({ type: 'smallint' })
  seatsFree!: number;

  @Column({ type: 'enum', enum: RideStatus, enumName: 'ride_status', default: RideStatus.REQUESTED })
  status!: RideStatus;

  /** Current driver. Set once on accept; only a breakdown handover may replace it (ck_rides_driver_locked). */
  @Column({ type: 'integer', nullable: true })
  driverId!: number | null;

  @ManyToOne(() => DriverProfile, { nullable: true })
  @JoinColumn({ name: 'driver_id' })
  driver!: Relation<DriverProfile> | null;

  /**
   * The real foreign key is composite: (vehicle_id, driver_id, vehicle_type) -> vehicles.
   * Write driverId and vehicleId as plain columns; treat the relation as read-only.
   */
  @Column({ type: 'integer', nullable: true })
  vehicleId!: number | null;

  @ManyToOne(() => Vehicle, { nullable: true, createForeignKeyConstraints: false })
  @JoinColumn({ name: 'vehicle_id' })
  vehicle!: Relation<Vehicle> | null;

  /** Bumped by a trigger on every UPDATE (and by TypeORM); socket events carry it. */
  @VersionColumn()
  version!: number;

  /** Set exactly when status = CANCELLED. */
  @Column({ type: 'enum', enum: RideCancelReason, enumName: 'ride_cancel_reason', nullable: true })
  cancelReason!: RideCancelReason | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @TimestampColumn({ nullable: true })
  acceptedAt!: Date | null;

  @TimestampColumn({ nullable: true })
  startedAt!: Date | null;

  @TimestampColumn({ nullable: true })
  completedAt!: Date | null;

  @TimestampColumn({ nullable: true })
  cancelledAt!: Date | null;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;

  @OneToMany(() => RidePassenger, (passenger) => passenger.ride)
  passengers!: Relation<RidePassenger[]>;
}
