-- =============================================================================
-- Bhorsha: record the schema baseline as an applied TypeORM migration.
--
-- 01_schema.sql is also the body of the TypeORM migration SchemaBaseline1794441600000
-- (src/database/migrations/1794441600000-SchemaBaseline.ts). Recording it here means
-- `migration:run` against a database created by this image skips the baseline and runs
-- only the migrations written after it.
--
-- Same layout TypeORM creates itself. The name must match migrationsTableName in
-- src/database/typeorm.config.ts.
-- =============================================================================
CREATE TABLE typeorm_migrations (
  id          SERIAL            NOT NULL,
  "timestamp" bigint            NOT NULL,
  name        character varying NOT NULL,
  CONSTRAINT pk_typeorm_migrations PRIMARY KEY (id)
);

INSERT INTO typeorm_migrations ("timestamp", name) VALUES (1794441600000, 'SchemaBaseline1794441600000');
