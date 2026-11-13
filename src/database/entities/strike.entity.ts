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
import { TimestampColumn } from '../columns.js';
import { StrikeStatus } from './enums.js';
import { SupportCase } from './support-case.entity.js';
import { User } from './user.entity.js';

/**
 * trust module. Applies to riders and drivers (FR-TS-5). DELETE /strikes/:id sets REVOKED.
 * It counts toward thresholds only while ACTIVE, expiresAt > now() and no appeal is PENDING.
 * userId, caseId and issuedBy never change after issue.
 */
@Entity('strikes')
export class Strike {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  /** Must be the case's subject (composite FK fk_strikes_case_subject). */
  @Column({ type: 'integer', update: false })
  userId!: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'user_id' })
  user!: Relation<User>;

  /** One standing strike per person per case (uq_strikes_case_user_live). */
  @Column({ type: 'integer', update: false })
  caseId!: number;

  @ManyToOne(() => SupportCase, { createForeignKeyConstraints: false })
  @JoinColumn({ name: 'case_id' })
  supportCase!: Relation<SupportCase>;

  /** Officer who issued it: can never decide its appeal (separation of duties). */
  @Column({ type: 'integer', update: false })
  issuedBy!: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'issued_by' })
  issuer!: Relation<User>;

  @Column({ type: 'text' })
  reason!: string;

  @Column({ type: 'enum', enum: StrikeStatus, enumName: 'strike_status', default: StrikeStatus.ACTIVE })
  status!: StrikeStatus;

  @TimestampColumn({ default: () => 'now()' })
  issuedAt!: Date;

  /** issuedAt + 90 days (section 16). */
  @TimestampColumn()
  expiresAt!: Date;

  /** Set exactly when REVOKED. */
  @TimestampColumn({ nullable: true })
  revokedAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
