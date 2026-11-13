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
import { GeoColumn } from '../columns.js';
import { DriverProfile } from './driver-profile.entity.js';
import { RouteOfferStatus, VehicleType } from './enums.js';
import { Ride } from './ride.entity.js';
import { Vehicle } from './vehicle.entity.js';

/**
 * sharing module. "Going this way": a driver with free seats publishes the rest of their route.
 * rideId null = heading home with no ride yet; the first accepted join creates the ride, so the
 * seat transaction locks this row FOR UPDATE first. Live while status = OPEN AND expiresAt > now().
 */
@Entity('route_offers')
export class RouteOffer {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  @Column({ type: 'integer' })
  driverId!: number;

  @ManyToOne(() => DriverProfile)
  @JoinColumn({ name: 'driver_id' })
  driver!: Relation<DriverProfile>;

  @Column({ type: 'integer', nullable: true })
  rideId!: number | null;

  @ManyToOne(() => Ride, { nullable: true })
  @JoinColumn({ name: 'ride_id' })
  ride!: Relation<Ride> | null;

  /** Composite FK (vehicle_id, driver_id, vehicle_type) -> vehicles: write the plain columns. */
  @Column({ type: 'integer' })
  vehicleId!: number;

  @ManyToOne(() => Vehicle, { createForeignKeyConstraints: false })
  @JoinColumn({ name: 'vehicle_id' })
  vehicle!: Relation<Vehicle>;

  /** CAR or CNG: bikes are never shared (ck_route_offers_not_bike). */
  @Column({ type: 'enum', enum: VehicleType, enumName: 'vehicle_type' })
  vehicleType!: VehicleType;

  @GeoColumn()
  fromLat!: number;

  @GeoColumn()
  fromLng!: number;

  @GeoColumn()
  toLat!: number;

  @GeoColumn()
  toLng!: number;

  /** Seats on offer when published. Once a ride exists, rides.seatsFree is the only seat count. */
  @Column({ type: 'smallint' })
  seatsOffered!: number;

  /** DELETE /route-offers/:id sets WITHDRAWN. */
  @Column({ type: 'enum', enum: RouteOfferStatus, enumName: 'route_offer_status', default: RouteOfferStatus.OPEN })
  status!: RouteOfferStatus;

  @Column({ type: 'timestamptz' })
  expiresAt!: Date;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
