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
import { TimestampColumn } from '../columns.js';
import { AppealStatus } from './enums.js';
import { Strike } from './strike.entity.js';
import { User } from './user.entity.js';

/**
 * trust module. One appeal per strike (uq_appeals_strike). The officer who issued the strike
 * cannot decide it: the API returns 403, and a trigger backstops it (ck_appeals_separation_of_duties).
 * Accepting an appeal sets the strike to OVERTURNED in the same transaction.
 */
@Entity('appeals')
export class Appeal {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  @Column({ type: 'integer' })
  strikeId!: number;

  @OneToOne(() => Strike)
  @JoinColumn({ name: 'strike_id' })
  strike!: Relation<Strike>;

  @Column({ type: 'text' })
  statement!: string;

  @Column({ type: 'enum', enum: AppealStatus, enumName: 'appeal_status', default: AppealStatus.PENDING })
  status!: AppealStatus;

  @Column({ type: 'integer', nullable: true })
  decidedBy!: number | null;

  @ManyToOne(() => User, { nullable: true })
  @JoinColumn({ name: 'decided_by' })
  decider!: Relation<User> | null;

  /** Required once decided. */
  @Column({ type: 'text', nullable: true })
  decisionReason!: string | null;

  @TimestampColumn({ nullable: true })
  decidedAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
