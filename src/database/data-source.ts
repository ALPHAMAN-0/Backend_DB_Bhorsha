import { DataSource } from 'typeorm';
import { buildDataSourceOptions } from './typeorm.config.js';

/**
 * Used ONLY by the TypeORM CLI. ts-node is not installed, so build first and point the CLI
 * at the compiled file, from the project root:
 *   npm run build && npx typeorm migration:run -d dist/database/data-source.js
 * (nest build compiles src/ into dist/ through tsconfig.build.json.)
 *
 * .env is loaded with Node's built-in loader (Node 20.12+), so no dotenv package is needed.
 */
try {
  process.loadEnvFile();
} catch {
  // No .env file: use the real environment (CI, Docker).
}

export default new DataSource(buildDataSourceOptions((key) => process.env[key]));
