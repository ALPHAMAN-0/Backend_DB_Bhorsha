import { Controller, Get } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';

interface DbHealthRow {
  database: string;
  latestMigration: string | null;
  users: number;
  rides: number;
  liveRides: number;
}

/**
 * GET /health/db: proves the app reaches the seeded database and shows which schema it runs.
 * Dev aid: mark it @Public() or remove it once the global JwtAuthGuard is in place.
 */
@Controller('health')
export class DbHealthController {
  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  @Get('db')
  async check() {
    const [row] = await this.dataSource.query<DbHealthRow[]>(`
      SELECT current_database()                                                            AS database,
             (SELECT name FROM typeorm_migrations ORDER BY "timestamp" DESC LIMIT 1)       AS "latestMigration",
             (SELECT count(*)::int FROM users)                                             AS users,
             (SELECT count(*)::int FROM rides)                                             AS rides,
             (SELECT count(*)::int FROM rides WHERE status NOT IN ('COMPLETED', 'CANCELLED')) AS "liveRides"
    `);
    return { status: 'ok', ...row };
  }
}
