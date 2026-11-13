import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Baseline: Bhorsha schema v2.0.0 (13 tables, Architecture v3.1 section 26).
 *
 * The body is db/init/01_schema.sql, the same file the bhorsha-db Docker image runs on first
 * start, so `migration:run` on an empty database and the image build an identical schema.
 * The image also records this migration in typeorm_migrations (db/init/03_typeorm_baseline.sql),
 * so running migrations against the image skips it.
 *
 * 01_schema.sql is FROZEN from v2.0.0 on: never edit it. Every change is a new migration,
 * registered in MIGRATIONS (typeorm.config.ts). Run the CLI from the project root.
 */
export class SchemaBaseline1794441600000 implements MigrationInterface {
  name = 'SchemaBaseline1794441600000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    const file = resolve(process.cwd(), 'db/init/01_schema.sql');
    let sql: string;
    try {
      sql = readFileSync(file, 'utf8');
    } catch {
      throw new Error(`Schema baseline not found at ${file}. Run the TypeORM CLI from the project root.`);
    }
    await queryRunner.query(sql);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DROP TABLE IF EXISTS audit_logs, appeals, strikes, support_cases, ratings, ride_passengers,
                           join_requests, route_offers, rides, fare_rules, vehicles, driver_profiles, users;
      DROP FUNCTION IF EXISTS set_updated_at(), enforce_status_transition(), forbid_update_delete(),
                              fare_rules_regulation_frozen(), rides_update_guards(), appeals_separation_of_duties();
      DROP DOMAIN IF EXISTS geo_lat, geo_lng;
      DROP TYPE IF EXISTS user_role, driver_verification, driver_status, vehicle_type, ride_status,
                          ride_cancel_reason, passenger_status, route_offer_status, join_initiator,
                          join_request_status, case_type, case_status, strike_status, appeal_status;
    `);
  }
}
