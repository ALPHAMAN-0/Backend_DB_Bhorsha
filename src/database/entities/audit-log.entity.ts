import { Column, CreateDateColumn, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn, type Relation } from 'typeorm';
import { User } from './user.entity.js';

/**
 * audit module. Append-only (a trigger blocks UPDATE and DELETE), written for every POST, PUT,
 * PATCH and DELETE. The AuditInterceptor must skip /auth/* and log only allowlisted fields:
 * the table refuses top-level password, passwordHash and pickupPin keys (ck_audit_logs_no_secrets),
 * because an append-only row could never be cleaned up.
 */
@Entity('audit_logs')
export class AuditLog {
  /** bigint; a JS number because the data source sets parseInt8. Cursor pagination runs on it. */
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS', type: 'bigint' })
  id!: number;

  /** Who acted; null = system or scheduled job. */
  @Column({ type: 'integer', nullable: true, update: false })
  userId!: number | null;

  @ManyToOne(() => User, { nullable: true })
  @JoinColumn({ name: 'user_id' })
  user!: Relation<User> | null;

  /** e.g. RIDE_ACCEPTED, or the route: "PATCH /rides/:id". */
  @Column({ type: 'varchar', length: 100, update: false })
  action!: string;

  /** Table of the changed row, e.g. "rides". */
  @Column({ type: 'varchar', length: 50, update: false })
  entity!: string;

  @Column({ type: 'varchar', length: 64, nullable: true, update: false })
  entityId!: string | null;

  @Column({ type: 'jsonb', nullable: true, update: false })
  oldValue!: Record<string, unknown> | null;

  @Column({ type: 'jsonb', nullable: true, update: false })
  newValue!: Record<string, unknown> | null;

  @Column({ type: 'inet', nullable: true, update: false })
  ipAddress!: string | null;

  /** Request ID from the logging middleware (NFR-09). */
  @Column({ type: 'varchar', length: 64, nullable: true, update: false })
  requestId!: string | null;

  @CreateDateColumn({ type: 'timestamptz', update: false })
  createdAt!: Date;
}
