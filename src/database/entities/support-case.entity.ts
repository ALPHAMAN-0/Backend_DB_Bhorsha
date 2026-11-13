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
import { PaisaColumn, TimestampColumn } from '../columns.js';
import { CaseStatus, CaseType } from './enums.js';
import { Ride } from './ride.entity.js';
import { User } from './user.entity.js';

/**
 * trust module. "cases" in the API: an overcharge, a safety issue or a co-rider report.
 * DELETE /cases/:id sets WITHDRAWN. A decision (UPHELD or DISMISSED) needs resolution,
 * resolvedAt and assignedTo (ck_support_cases_decision).
 */
@Entity('support_cases')
export class SupportCase {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  @Column({ type: 'enum', enum: CaseType, enumName: 'case_type' })
  type!: CaseType;

  @Column({ type: 'enum', enum: CaseStatus, enumName: 'case_status', default: CaseStatus.OPEN })
  status!: CaseStatus;

  @Column({ type: 'integer' })
  reporterId!: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'reporter_id' })
  reporter!: Relation<User>;

  /** The person reported. A strike can only name this user (fk_strikes_case_subject). */
  @Column({ type: 'integer', nullable: true })
  subjectId!: number | null;

  @ManyToOne(() => User, { nullable: true })
  @JoinColumn({ name: 'subject_id' })
  subject!: Relation<User> | null;

  @Column({ type: 'integer', nullable: true })
  rideId!: number | null;

  @ManyToOne(() => Ride, { nullable: true })
  @JoinColumn({ name: 'ride_id' })
  ride!: Relation<Ride> | null;

  /** Support officer working the case. */
  @Column({ type: 'integer', nullable: true })
  assignedTo!: number | null;

  @ManyToOne(() => User, { nullable: true })
  @JoinColumn({ name: 'assigned_to' })
  assignee!: Relation<User> | null;

  @Column({ type: 'text' })
  description!: string;

  /** OVERCHARGE only: what the driver demanded. */
  @PaisaColumn({ nullable: true })
  amountClaimedPaisa!: number | null;

  /** Written decision reason. */
  @Column({ type: 'text', nullable: true })
  resolution!: string | null;

  @TimestampColumn({ nullable: true })
  resolvedAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
