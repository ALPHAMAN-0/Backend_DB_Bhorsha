# Bhorsha database — run it on any PC

PostgreSQL 16 with the 13 Bhorsha tables (schema v2.0.0, Architecture v3.1) and demo data already inside.
You don't need any SQL files and you don't build anything. Docker downloads the image from Docker Hub.

## 1. Install Docker
Install Docker Desktop (Windows / macOS) or Docker Engine (Linux) and start it.

## 2. Start the database

**Option A: with this folder** (`docker-compose.yml` + `.env`)

Open a terminal in this folder, then create your `.env` from the example and set any password you like:

```bash
cp .env.example .env            # Windows PowerShell: Copy-Item .env.example .env
docker compose up -d
docker compose ps        # wait until bhorsha-db shows "(healthy)"
```

**Option B: one command, no files**

```bash
docker run -d --name bhorsha-db -e POSTGRES_PASSWORD=change-me -p 5433:5432 -v bhorsha_pgdata:/var/lib/postgresql/data siam001/bhorsha-db:latest
```

On the first start the tables and demo data load automatically (about 10 seconds).

## 3. Connect

| Setting  | Value                         |
|----------|-------------------------------|
| Host     | `localhost`                   |
| Port     | `5433`                        |
| Database | `bhorsha`                     |
| User     | `bhorsha`                     |
| Password | `POSTGRES_PASSWORD` from `.env` |

Connection URL: `postgresql://bhorsha:change-me@localhost:5433/bhorsha`

You can use pgAdmin, DBeaver, TablePlus, VS Code, or your backend's `.env`.

## 4. Check the data (optional)

```bash
docker exec -it bhorsha-db psql -U bhorsha -d bhorsha -c "\dt"
docker exec -it bhorsha-db psql -U bhorsha -d bhorsha -f /scripts/verify.sql   # ends with ALL CHECKS PASSED
```

## Useful commands

| What                                          | Command                       |
|-----------------------------------------------|-------------------------------|
| Stop (keeps your data)                        | `docker compose down`         |
| Reset to fresh demo data                      | `docker compose down -v` then `docker compose up -d` |
| Get a newer image version                     | `docker compose pull` then `docker compose up -d` |

## Problems

- **Port 5433 already in use**: change `DB_PORT` in `.env` (for example `5434`).
- **Changed the password but login fails**: the password is only set the first time. Run `docker compose down -v` and start again.
- **Tables are missing / old data**: an old volume is being reused. Run `docker compose down -v` and start again.
