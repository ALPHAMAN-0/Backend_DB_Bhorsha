import { Column, CreateDateColumn, Entity, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';
import { TimestampColumn } from '../columns.js';
import { UserRole } from './enums.js';

/** identity module. Every account: rider, driver, admin or support officer. */
@Entity('users')
export class User {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  @Column({ type: 'varchar', length: 100 })
  fullName!: string;

  /** E.164, e.g. +8801711000003 (ck_users_phone_format). Normalise in the DTO. Unique. */
  @Column({ type: 'varchar', length: 16 })
  phone!: string;

  /** Optional. Stored lower-case (ck_users_email_format): normalise in the DTO. Unique. */
  @Column({ type: 'varchar', length: 254, nullable: true })
  email!: string | null;

  /** bcrypt hash. Never selected by default: login uses .addSelect('user.passwordHash'). */
  @Column({ type: 'varchar', length: 255, select: false })
  passwordHash!: string;

  @Column({ type: 'enum', enum: UserRole, enumName: 'user_role' })
  role!: UserRole;

  /** false = deactivated by an admin (the soft delete behind DELETE /users/:id). */
  @Column({ type: 'boolean', default: true })
  isActive!: boolean;

  /** Suspended while now() < suspendedUntil (3 active strikes = 7 days, section 16). */
  @TimestampColumn({ nullable: true })
  suspendedUntil!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
