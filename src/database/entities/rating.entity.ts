import { Column, CreateDateColumn, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn, type Relation } from 'typeorm';
import { Ride } from './ride.entity.js';
import { User } from './user.entity.js';

/**
 * trips module. Stars from one user to another for a ride (driver <-> passenger, passenger <->
 * co-rider). One per direction per ride (uq_ratings_ride_from_to). A user's average is computed
 * on read: SELECT avg(stars), count(*) FROM ratings WHERE to_user_id = $1.
 */
@Entity('ratings')
export class Rating {
  @PrimaryGeneratedColumn('identity', { generatedIdentity: 'ALWAYS' })
  id!: number;

  @Column({ type: 'integer' })
  rideId!: number;

  @ManyToOne(() => Ride)
  @JoinColumn({ name: 'ride_id' })
  ride!: Relation<Ride>;

  @Column({ type: 'integer' })
  fromUserId!: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'from_user_id' })
  fromUser!: Relation<User>;

  @Column({ type: 'integer' })
  toUserId!: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'to_user_id' })
  toUser!: Relation<User>;

  /** 1 to 5. */
  @Column({ type: 'smallint' })
  stars!: number;

  @Column({ type: 'varchar', length: 500, nullable: true })
  comment!: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;
}
