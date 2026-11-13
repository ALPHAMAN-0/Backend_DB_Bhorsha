import { Column, type ColumnOptions, type ValueTransformer } from 'typeorm';

/**
 * bigint paisa -> number. Safe up to Number.MAX_SAFE_INTEGER paisa (about Tk 90 trillion).
 * With parseInt8 on, pg already returns numbers; this also guards against a string sneaking in.
 */
export const paisaTransformer: ValueTransformer = {
  to: (value?: number | null) => value,
  from: (value?: string | number | null) => {
    if (value === null || value === undefined) return value;
    const n = typeof value === 'number' ? value : Number(value);
    if (!Number.isSafeInteger(n)) throw new RangeError(`paisa value out of range: ${String(value)}`);
    return n;
  },
};

/** numeric -> number, for coordinates (pg returns numeric as a string). */
export const numericTransformer: ValueTransformer = {
  to: (value?: number | null) => value,
  from: (value?: string | null) => (value === null || value === undefined ? value : Number(value)),
};

/**
 * Money: bigint paisa (1 Tk = 100 paisa, ADR-008). Do all fare maths in integer paisa and
 * round once (half up) at the end; never use floating-point Taka.
 */
export const PaisaColumn = (options: ColumnOptions = {}) =>
  Column({ type: 'bigint', transformer: paisaTransformer, ...options });

/** numeric(9,6) latitude or longitude (geo_lat / geo_lng domains in SQL). */
export const GeoColumn = (options: ColumnOptions = {}) =>
  Column({ type: 'numeric', precision: 9, scale: 6, transformer: numericTransformer, ...options });

/** timestamptz: every timestamp is stored in UTC. */
export const TimestampColumn = (options: ColumnOptions = {}) => Column({ type: 'timestamptz', ...options });
