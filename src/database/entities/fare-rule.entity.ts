import { Column, CreateDateColumn, Entity, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';
import { PaisaColumn } from '../columns.js';
import { VehicleType } from './enums.js';

/**
 * pricing module. One rule per vehicle type, edited in place (no history in the course release;
 * ride_passengers.pricingSnapshot keeps what was used). See PricingSnapshot for the formula.
 *
 * The admin may edit basePaisa, perKmPaisa and shareDiscountBps. The ceiling columns and
 * baseDistanceM are regulation: a trigger refuses changes (ck_fare_rules_regulation_frozen),
 * and update: false keeps TypeORM from sending them.
 */
@Entity('fare_rules')
export class FareRule {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  @Column({ type: 'enum', enum: VehicleType, enumName: 'vehicle_type', update: false })
  vehicleType!: VehicleType;

  /** <= ceilingBasePaisa (ck_fare_rules_within_ceiling). */
  @PaisaColumn()
  basePaisa!: number;

  /** <= ceilingPerKmPaisa (ck_fare_rules_within_ceiling). */
  @PaisaColumn()
  perKmPaisa!: number;

  /** Distance included in the base fare: the legal "first 2 km" (2000). */
  @Column({ type: 'integer', update: false })
  baseDistanceM!: number;

  @PaisaColumn({ update: false })
  ceilingBasePaisa!: number;

  @PaisaColumn({ update: false })
  ceilingPerKmPaisa!: number;

  /** Shared-ride discount in basis points (2500 = 25 %); 1..9999 so shared is always cheaper. */
  @Column({ type: 'integer', default: 2500 })
  shareDiscountBps!: number;

  @Column({ type: 'integer', nullable: true })
  updatedBy!: number | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
