import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  OneToMany,
  OneToOne,
  PrimaryColumn,
  type Relation,
  UpdateDateColumn,
} from 'typeorm';
import { GeoColumn, TimestampColumn } from '../columns.js';
import { DriverStatus, DriverVerification } from './enums.js';
import { User } from './user.entity.js';
import { Vehicle } from './vehicle.entity.js';

/**
 * fleet module. Driver extension of users (1:1, shared primary key). Register creates the
 * user and this row in one transaction. A driver's rating is computed from ratings on read.
 */
@Entity('driver_profiles')
export class DriverProfile {
  @PrimaryColumn({ type: 'integer' })
  userId!: number;

  @OneToOne(() => User)
  @JoinColumn({ name: 'user_id' })
  user!: Relation<User>;

  /** Unique (uq_driver_profiles_licence_no -> 409 on register). */
  @Column({ type: 'varchar', length: 30 })
  licenceNo!: string;

  @Column({ type: 'enum', enum: DriverVerification, enumName: 'driver_verification', default: DriverVerification.PENDING })
  verification!: DriverVerification;

  /** Admin who verified or rejected (required once verification is not PENDING). */
  @Column({ type: 'integer', nullable: true })
  reviewedBy!: number | null;

  @ManyToOne(() => User, { nullable: true })
  @JoinColumn({ name: 'reviewed_by' })
  reviewer!: Relation<User> | null;

  @TimestampColumn({ nullable: true })
  reviewedAt!: Date | null;

  /** Required when REJECTED. */
  @Column({ type: 'text', nullable: true })
  rejectionReason!: string | null;

  /** ONLINE only while VERIFIED. Rejecting an online driver must also set OFFLINE in the same UPDATE. */
  @Column({ type: 'enum', enum: DriverStatus, enumName: 'driver_status', default: DriverStatus.OFFLINE })
  status!: DriverStatus;

  /** Last posted position (PUT /drivers/me/location). lastLat, lastLng and lastLocationAt are set together. */
  @GeoColumn({ nullable: true })
  lastLat!: number | null;

  @GeoColumn({ nullable: true })
  lastLng!: number | null;

  @TimestampColumn({ nullable: true })
  lastLocationAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;

  @OneToMany(() => Vehicle, (vehicle) => vehicle.driver)
  vehicles!: Relation<Vehicle[]>;
}
