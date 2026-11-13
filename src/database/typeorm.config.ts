import type { DataSourceOptions } from 'typeorm';
import { ENTITIES } from './entities/index.js';
import { SchemaBaseline1794441600000 } from './migrations/1794441600000-SchemaBaseline.js';
import { SnakeNamingStrategy } from './naming-strategy.js';

type EnvReader = (key: string) => string | undefined;

/**
 * Every migration, oldest first. Register each new migration here: an explicit list works
 * the same from src and from dist, unlike a file glob under ESM.
 */
export const MIGRATIONS = [SchemaBaseline1794441600000];

/** Must match db/init/03_typeorm_baseline.sql, which marks the baseline as applied in the image. */
export const MIGRATIONS_TABLE = 'typeorm_migrations';

/**
 * Single source of connection settings for the Nest app (database.module.ts) and the
 * TypeORM CLI (data-source.ts). Reads the same .env as docker compose.
 */
export function buildDataSourceOptions(env: EnvReader): DataSourceOptions {
  const required = (key: string): string => {
    const value = env(key);
    if (!value) throw new Error(`Missing required environment variable: ${key}`);
    return value;
  };

  return {
    type: 'postgres',
    host: env('DB_HOST') ?? 'localhost',
    port: Number(env('DB_PORT') ?? 5433),
    username: required('POSTGRES_USER'),
    password: required('POSTGRES_PASSWORD'),
    database: required('POSTGRES_DB'),
    entities: ENTITIES,
    migrations: MIGRATIONS,
    migrationsTableName: MIGRATIONS_TABLE,
    // camelCase in TypeScript <-> snake_case in Postgres.
    namingStrategy: new SnakeNamingStrategy(),
    // bigint (paisa, audit ids, count(*)) comes back as a JS number instead of a string.
    parseInt8: true,
    // The schema is owned by SQL migrations. NEVER enable synchronize: TypeORM would drop the
    // CHECKs, partial indexes, composite foreign keys and triggers it does not model.
    synchronize: false,
    migrationsRun: false,
    logging: env('DB_LOGGING') === 'true' ? ['query', 'error', 'warn'] : ['error', 'warn'],
    extra: { max: Number(env('DB_POOL_MAX') ?? 10) },
  };
}
