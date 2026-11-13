#!/bin/sh
# Build-time gate for the bhorsha-db image.
# Loads db/init/*.sql into a throwaway cluster and runs verify.sql + constraint-tests.sql.
# Any failure fails `docker build`, so a broken schema or seed can never be pushed.
set -eu

INIT_DIR="${INIT_DIR:-/verify/init}"
SCRIPTS_DIR="${SCRIPTS_DIR:-/verify/scripts}"
WORK_DIR="${WORK_DIR:-/tmp/bhorsha-verify}"
DATA_DIR="$WORK_DIR/data"
SOCKET_DIR="$WORK_DIR"
DB=bhorsha
DB_USER=bhorsha

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

initdb -D "$DATA_DIR" -U "$DB_USER" --auth=trust --encoding=UTF8 >/dev/null
pg_ctl -D "$DATA_DIR" -l "$WORK_DIR/postgres.log" -w \
       -o "-c listen_addresses='' -k $SOCKET_DIR" start >/dev/null
trap 'pg_ctl -D "$DATA_DIR" -m fast stop >/dev/null 2>&1 || true' EXIT

run_psql() {
  psql -h "$SOCKET_DIR" -U "$DB_USER" -d "$DB" -v ON_ERROR_STOP=1 --no-psqlrc -q "$@"
}

createdb -h "$SOCKET_DIR" -U "$DB_USER" "$DB"

for f in "$INIT_DIR"/*.sql; do
  echo "verify: loading $(basename "$f")"
  run_psql -f "$f"
done

echo "verify: running verify.sql"
run_psql -f "$SCRIPTS_DIR/verify.sql" > "$WORK_DIR/verify.txt" 2>&1 || { cat "$WORK_DIR/verify.txt"; exit 1; }
grep -q 'ALL CHECKS PASSED' "$WORK_DIR/verify.txt" || { cat "$WORK_DIR/verify.txt"; exit 1; }
echo "verify: ALL CHECKS PASSED"

echo "verify: running constraint-tests.sql"
run_psql -f "$SCRIPTS_DIR/constraint-tests.sql" > "$WORK_DIR/constraint-tests.txt"
grep 'FAIL' "$WORK_DIR/constraint-tests.txt" && { echo "verify: constraint tests failed"; exit 1; }
grep -q ' passed, 0 failed' "$WORK_DIR/constraint-tests.txt" || { cat "$WORK_DIR/constraint-tests.txt"; exit 1; }
tail -n 2 "$WORK_DIR/constraint-tests.txt"

echo "verify: OK"
