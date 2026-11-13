import {
  Column,
  CreateDateColumn,
  DeleteDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  type Relation,
  UpdateDateColumn,
} from 'typeorm';
import { DriverProfile } from './driver-profile.entity.js';
import { VehicleType } from './enums.js';

/**
 * fleet module. Soft-deleted (DELETE /vehicles/:id) because past rides keep pointing at it.
 * find() hides deleted vehicles: pass { withDeleted: true } when loading ride history.
 */
@Entity('vehicles')
export class Vehicle {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  /** Never changes: a sold vehicle is soft-deleted and registered again by its new driver. */
  @Column({ type: 'integer', update: false })
  driverId!: number;

  @ManyToOne(() => DriverProfile, (driver) => driver.vehicles)
  @JoinColumn({ name: 'driver_id' })
  driver!: Relation<DriverProfile>;

  /** Never editable: rides and route offers reference (id, driver_id, type). */
  @Column({ type: 'enum', enum: VehicleType, enumName: 'vehicle_type', update: false })
  type!: VehicleType;

  /** Unique among active vehicles, case-insensitive (uq_vehicles_reg_no_active). */
  @Column({ type: 'varchar', length: 30 })
  regNo!: string;

  /** Passenger seats from SEAT_CAPACITY[type]: bike 1, CNG 2, car 3. */
  @Column({ type: 'smallint' })
  seats!: number;

  @Column({ type: 'varchar', length: 60, nullable: true })
  model!: string | null;

  @Column({ type: 'varchar', length: 30, nullable: true })
  color!: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;

  @DeleteDateColumn({ type: 'timestamptz' })
  deletedAt!: Date | null;
}
