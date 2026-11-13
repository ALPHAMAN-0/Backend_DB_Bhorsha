# Backend_DB_Bhorsha

[![Docker Hub](https://img.shields.io/docker/v/siam001/bhorsha-db?sort=semver&label=docker%20hub&logo=docker&logoColor=white)](https://hub.docker.com/r/siam001/bhorsha-db)
[![Pulls](https://img.shields.io/docker/pulls/siam001/bhorsha-db?logo=docker&logoColor=white)](https://hub.docker.com/r/siam001/bhorsha-db)
![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-linux%2Famd64%20%7C%20linux%2Farm64-2496ED)
![Tables](https://img.shields.io/badge/schema-v2.0.0%20%C2%B7%2013%20tables-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

The **database of Bhorsha**, a ride-sharing app for Bangladesh (bike, car and CNG, with shared rides).

This repository is the **source** of the Docker image
[`siam001/bhorsha-db`](https://hub.docker.com/r/siam001/bhorsha-db): PostgreSQL 16 with 13 tables, the
business rules enforced inside the database, and demo data. Anyone can start the full database with one
command. You need no SQL files and you don't build anything.

```bash
docker run -d --name bhorsha-db -e POSTGRES_PASSWORD=change-me -p 5433:5432 siam001/bhorsha-db:2.0.0
```

> The SQL files in `db/init/` and `db/scripts/` are byte-for-byte the same files that are inside
> `siam001/bhorsha-db:2.0.0` on Docker Hub (checked by downloading the image layers and comparing them).

---

## Contents

1. [Quick start](#1-quick-start)
2. [The big picture](#2-the-big-picture)
3. [How I pushed the database to Docker Hub](#3-how-i-pushed-the-database-to-docker-hub)
4. [What happens when someone runs the image](#4-what-happens-when-someone-runs-the-image)
5. [Which file does what, and why](#5-which-file-does-what-and-why)
6. [Why this repository is public](#6-why-this-repository-is-public)
7. [Database design](#7-database-design)
8. [Use it from the NestJS backend](#8-use-it-from-the-nestjs-backend)
9. [Publish a new version](#9-publish-a-new-version)
10. [Demo accounts and demo story](#10-demo-accounts-and-demo-story)
11. [Rules for the team](#11-rules-for-the-team)
12. [Daily commands and troubleshooting](#12-daily-commands-and-troubleshooting)
13. [Version history](#13-version-history)

---

## 1. Quick start

You need only **Docker** (Docker Desktop on Windows/macOS, Docker Engine on Linux).

**Option A: one command**

```bash
docker run -d --name bhorsha-db \
  -e POSTGRES_PASSWORD=change-me \
  -p 5433:5432 \
  -v bhorsha_pgdata:/var/lib/postgresql/data \
  siam001/bhorsha-db:2.0.0
```

**Option B: Docker Compose** (use the [`run-on-any-pc/`](run-on-any-pc) folder)

```bash
cd run-on-any-pc
cp .env.example .env        # then set POSTGRES_PASSWORD
docker compose up -d
docker compose ps           # wait until bhorsha-db shows "(healthy)", about 10 seconds
```

**Connect** with pgAdmin, DBeaver, TablePlus, VS Code or your backend:

| Setting  | Value |
|----------|-------|
| Host     | `localhost` |
| Port     | `5433` (not 5432, so it never clashes with a PostgreSQL already installed on your PC) |
| Database | `bhorsha` |
| User     | `bhorsha` |
| Password | the `POSTGRES_PASSWORD` you chose |

URL: `postgresql://bhorsha:change-me@localhost:5433/bhorsha`

**Check that everything loaded:**

```bash
docker exec -it bhorsha-db psql -U bhorsha -d bhorsha -c "\dt"                     # 13 tables + typeorm_migrations
docker exec -it bhorsha-db psql -U bhorsha -d bhorsha -f /scripts/verify.sql           # ends with: ALL CHECKS PASSED
docker exec -it bhorsha-db psql -U bhorsha -d bhorsha -f /scripts/constraint-tests.sql # 47 passed, 0 failed
```

---

## 2. The big picture

There are two places on the internet. **GitHub** (this repository) keeps the *source files*. **Docker Hub**
keeps the *built image*: PostgreSQL with those files baked in. People who only want to *use* the database
never need GitHub. They pull the image from Docker Hub.

```mermaid
flowchart LR
    subgraph DEV["My laptop"]
        SRC["Source files<br/>db/init/*.sql<br/>db/scripts/*.sql<br/>db/Dockerfile"]
        BX["docker buildx build<br/>(runs the test gate)"]
        SRC --> BX
    end

    GH[("GitHub<br/>ALPHAMAN-0/Backend_DB_Bhorsha<br/><i>source code</i>")]
    HUB[("Docker Hub<br/>siam001/bhorsha-db<br/><i>built image</i><br/>tags: 2.0.0 · 2.0 · latest")]

    SRC -->|git push| GH
    BX -->|"push (amd64 + arm64)"| HUB

    subgraph USERS["Anyone, any PC"]
        T1["Teammate<br/>(Windows / Intel)"]
        T2["Teammate<br/>(Mac M1/M2/M3)"]
        V["Viva / demo machine"]
        BE["NestJS backend<br/>docker compose"]
    end

    HUB -->|docker pull| T1
    HUB -->|docker pull| T2
    HUB -->|docker pull| V
    HUB -->|docker compose up| BE
```

---

## 3. How I pushed the database to Docker Hub

### 3.1 The steps I ran

| # | Command | What it does | Why |
|---|---------|--------------|-----|
| 1 | `docker login -u siam001` | Signs in to Docker Hub (Docker Desktop keeps you signed in). Use a Docker Hub **access token** as the password. | You can only push to your own account. A token can be revoked without changing your real password. |
| 2 | `docker buildx create --name bhorsha --driver docker-container` | Creates a BuildKit builder named `bhorsha` (done once). | The default builder can't build **several CPU types at once** and push them as one image. The `docker-container` driver can. |
| 3 | `docker buildx build ./db --builder bhorsha --platform linux/amd64,linux/arm64 --build-arg VERSION=2.0.0 -t siam001/bhorsha-db:2.0.0 -t siam001/bhorsha-db:2.0 -t siam001/bhorsha-db:latest --push` | Builds the image from `db/Dockerfile` for two CPU types, runs the test gate, and uploads it with three tags. | `amd64` = Windows/Intel PCs and most servers, `arm64` = Apple Silicon Macs. One build gives three names for the same image. |
| 4 | `docker buildx imagetools inspect siam001/bhorsha-db:2.0.0` | Shows what is on Docker Hub. | Confirms both platforms (`linux/amd64`, `linux/arm64`) were uploaded. |
| 5 | Docker Hub → `siam001/bhorsha-db` → *Settings* → visibility **Public** | Docker Hub created the repository on the first push. New repositories are public by default, and I kept it public. | Teammates can `docker pull` without an account or `docker login`. |

Run from the repository root. `./db` is the **build context**: only that folder is sent to the builder, and
[`db/.dockerignore`](db/.dockerignore) narrows it further to the SQL files, the test script and the Dockerfile.

### 3.2 The push, step by step

```mermaid
sequenceDiagram
    autonumber
    actor Me as Me (laptop)
    participant CLI as Docker CLI
    participant BK as buildx builder "bhorsha"
    participant HUB as Docker Hub

    Me->>CLI: docker login -u siam001 (access token)
    CLI->>HUB: authenticate
    HUB-->>CLI: Login Succeeded

    Me->>CLI: docker buildx build ./db --platform amd64,arm64 -t ...:2.0.0 -t ...:2.0 -t ...:latest --push
    CLI->>BK: send build context (db/ folder, filtered by .dockerignore)

    Note over BK: Stage 1 "verify" runs ONCE, natively on my laptop
    BK->>BK: start a throwaway PostgreSQL
    BK->>BK: load 01_schema.sql, 02_seed.sql, 03_typeorm_baseline.sql
    BK->>BK: verify.sql → "ALL CHECKS PASSED"
    BK->>BK: constraint-tests.sql → "47 passed, 0 failed"

    alt any SQL error or failed check
        BK-->>Me: build FAILED, nothing is pushed
    else all tests pass
        Note over BK: Stage 2 "final" is built for each platform (COPY only)
        BK->>BK: image for linux/amd64
        BK->>BK: image for linux/arm64
        BK->>HUB: upload layers (only the ones Docker Hub doesn't already have)
        BK->>HUB: upload one manifest per platform + one index
        BK->>HUB: tag the index as 2.0.0, 2.0 and latest
        HUB-->>Me: pushed
    end
```

### 3.3 Inside `db/Dockerfile`: two stages

```mermaid
flowchart TB
    subgraph S1["Stage 1: verify (runs on the build machine's own CPU, never published)"]
        direction TB
        A1["FROM postgres:16-alpine"] --> A2["COPY init/  scripts/  build-verify.sh"]
        A2 --> A3["RUN build-verify.sh<br/>initdb → load all db/init/*.sql<br/>→ verify.sql → constraint-tests.sql"]
        A3 -->|all passed| A4["touch /tmp/verified"]
        A3 -->|any failure| X["❌ build stops"]
    end

    subgraph S2["Stage 2: final image (built for amd64 AND arm64, this is what gets pushed)"]
        direction TB
        B1["FROM postgres:16-alpine"] --> B2["COPY --from=verify /tmp/verified<br/>(Stage 2 can't exist unless Stage 1 passed)"]
        B2 --> B3["COPY init/ → /docker-entrypoint-initdb.d/"]
        B3 --> B4["COPY scripts/ → /scripts/"]
        B4 --> B5["ENV POSTGRES_DB=bhorsha, POSTGRES_USER=bhorsha, TZ=UTC<br/>HEALTHCHECK pg_isready<br/>CMD postgres -c log_min_duration_statement=250"]
    end

    A4 -.->|the marker file links the stages| B2
```

**Why two stages?**

- **A broken database can't be published.** The tests run *during* `docker build`. If a seed row breaks a
  rule, the build fails on my laptop and Docker Hub never sees it.
- **The published image stays clean.** The throwaway test database lives only in Stage 1 and is thrown away.
- **Fast multi-CPU builds.** Only Stage 1 runs code, and it runs on the laptop's own CPU. Stage 2 only copies
  files, so building the `arm64` image on an `amd64` machine (or the other way round) needs no slow emulation.
- **No password inside.** `POSTGRES_PASSWORD` is **not** in the Dockerfile. Each user gives their own when the
  container starts.

### 3.4 Tags on Docker Hub

One push uploads one image and gives it several names (tags). Each tag points to an *index*, which lists one
image per CPU. Docker automatically downloads the right one for your machine.

```mermaid
flowchart LR
    T1["siam001/bhorsha-db:2.0.0"] --> IDX2
    T2["siam001/bhorsha-db:2.0"] --> IDX2
    T3["siam001/bhorsha-db:latest"] --> IDX2
    IDX2{{"image index<br/>schema v2.0.0"}} --> M1["linux/amd64 image"]
    IDX2 --> M2["linux/arm64 image"]

    T0["siam001/bhorsha-db:1.0.0"] --> IDX1{{"image index<br/>schema v1.0.0 (old, 20 tables)"}}
    IDX1 --> M3["linux/amd64 image"]
    IDX1 --> M4["linux/arm64 image"]
```

| Tag | Meaning | Who should use it |
|-----|---------|-------------------|
| `2.0.0` | An exact version. It never changes. | **The backend and the team.** Pin this so everyone runs the same schema. |
| `2.0` | The newest `2.0.x` patch. | People who want bug fixes but no schema changes. |
| `latest` | The newest release, whatever it is. | Quick tries only. It moves when a new version is pushed. |
| `1.0.0` | The older 20-table proposal. | Nobody. It is kept for history. |

The GitHub release [`v2.0.0`](https://github.com/ALPHAMAN-0/Backend_DB_Bhorsha/releases/tag/v2.0.0) marks the
commit whose files are inside the `2.0.0` image.

---

## 4. What happens when someone runs the image

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant D as Docker
    participant HUB as Docker Hub
    participant C as Container (postgres 16 entrypoint)
    participant V as Volume bhorsha_pgdata

    U->>D: docker compose up -d
    D->>HUB: pull siam001/bhorsha-db:2.0.0
    HUB-->>D: the amd64 OR arm64 image (matches the PC)
    D->>C: start with POSTGRES_PASSWORD from .env
    C->>V: is the data folder empty?

    alt FIRST start (empty volume)
        C->>V: initdb: create user "bhorsha" with your password
        C->>C: run /docker-entrypoint-initdb.d/01_schema.sql (13 tables, rules, triggers)
        C->>C: run 02_seed.sql (demo users, rides, cases, times relative to now())
        C->>C: run 03_typeorm_baseline.sql (marks the baseline migration as applied)
        Note over C: during init Postgres listens on a local socket only
        C->>C: restart and listen on TCP 5432
    else LATER starts (volume has data)
        C->>C: skip init, keep your existing data
    end

    loop every 5 s
        D->>C: HEALTHCHECK pg_isready -h 127.0.0.1
    end
    C-->>D: healthy
    U->>C: connect on localhost:5433
```

Two things to remember:

- The SQL in `/docker-entrypoint-initdb.d/` runs **only when the volume is empty**. To get fresh demo data,
  delete the volume: `docker compose down -v`, then `docker compose up -d`.
- The password is fixed at the **first** start. If you change `POSTGRES_PASSWORD` later, either use the old
  one or reset with `down -v`.

---

## 5. Which file does what, and why

```
Backend_DB_Bhorsha/
├── db/                                  ← everything that goes INTO the Docker image
│   ├── Dockerfile                       two-stage build: test gate, then the published image
│   ├── .dockerignore                    sends only the SQL + test script to the builder
│   ├── build-verify.sh                  the test gate (runs inside Stage 1)
│   ├── init/                            → /docker-entrypoint-initdb.d/ (runs on first start)
│   │   ├── 01_schema.sql                13 tables, enums, foreign keys, CHECKs, indexes, triggers
│   │   ├── 02_seed.sql                  demo data that tells the demo story
│   │   └── 03_typeorm_baseline.sql      tells TypeORM the schema is already applied
│   └── scripts/                         → /scripts/ (run them yourself to check the database)
│       ├── verify.sql                   demo views + assertions → "ALL CHECKS PASSED"
│       └── constraint-tests.sql         47 rules, each tested → "47 passed, 0 failed"
├── run-on-any-pc/                       ← for people who only USE the database
│   ├── docker-compose.yml               pulls siam001/bhorsha-db from Docker Hub
│   ├── .env.example                     copy to .env and set a password
│   └── README.md                        3-step guide for teammates
├── docker-compose.yml                   ← for database developers: builds the image locally + pgAdmin
├── docker-compose.hub.yml               pulls the published image (no build)
├── .env.example                         one .env for Docker Compose AND NestJS
├── pgadmin/servers.json                 pre-registers the database in pgAdmin
├── src/                                 ← TypeORM code to copy into the NestJS backend
│   ├── app.module.ts
│   └── database/                        entities (13), naming strategy, migrations, /health/db
├── .github/workflows/
│   └── publish-db-image.yml             CI: test on pull requests, publish to Docker Hub on db-v* tags
├── .gitattributes                       keeps LF line endings so SQL and shell work from Windows too
├── .gitignore                           keeps .env (real passwords) out of Git
└── LICENSE                              MIT
```

### How the files reach the image

```mermaid
flowchart LR
    subgraph REPO["This repository"]
        F1["db/init/01_schema.sql"]
        F2["db/init/02_seed.sql"]
        F3["db/init/03_typeorm_baseline.sql"]
        F4["db/scripts/verify.sql"]
        F5["db/scripts/constraint-tests.sql"]
        F6["db/build-verify.sh"]
        F7["db/Dockerfile"]
    end

    subgraph IMG["Image siam001/bhorsha-db"]
        I1["/docker-entrypoint-initdb.d/<br/>01_schema.sql<br/>02_seed.sql<br/>03_typeorm_baseline.sql"]
        I2["/scripts/<br/>verify.sql<br/>constraint-tests.sql"]
    end

    subgraph OUT["Never in the image (outside the ./db build context)"]
        N1["src/ · compose files · .env.example<br/>README · .github · pgadmin · LICENSE"]
    end

    F1 & F2 & F3 --> I1
    F4 & F5 --> I2
    F6 -.->|"used in Stage 1 only, not copied"| IMG
    F7 -.->|the recipe| IMG
```

### Why each file exists

| File | Why it exists |
|------|---------------|
| `db/init/01_schema.sql` | **The only source of truth for the schema.** Both the Docker image and the TypeORM migration run this same file, so they can never drift apart. Rules live in the database (CHECKs, triggers, unique indexes), so even buggy app code can't sell a seat twice or charge above the legal fare ceiling. |
| `db/init/02_seed.sql` | Gives every fresh database the same demo story (a last-seat race, an invite, a strike and its appeal). Timestamps are relative to `now()`, so the demo never looks old. |
| `db/init/03_typeorm_baseline.sql` | Writes one row in `typeorm_migrations`. Without it, `migration:run` would try to create tables that already exist. |
| `db/scripts/verify.sql` | Checks the structure (13 tables, constraints, triggers, state-machine edges) and the demo numbers (fares, seats, strikes, ratings). It is used by the build gate and by you after starting. |
| `db/scripts/constraint-tests.sql` | Tries 47 *forbidden* things (oversell a seat, edit the fare ceiling, the same officer deciding their own strike's appeal...) and checks the database refuses each one with the right error. |
| `db/build-verify.sh` | Runs the two scripts above inside `docker build`, so a broken database can't be pushed. |
| `db/Dockerfile` | The recipe: PostgreSQL 16 Alpine (small) + our files + a healthcheck that turns green only after the data has loaded. |
| `db/.dockerignore` | Sends only what the image needs to the builder, so no `.env`, notes or other files can end up inside the image. |
| `run-on-any-pc/` | The smallest possible kit for teammates: one compose file + one `.env`. They don't need to understand the rest. |
| `docker-compose.yml` | For people changing the SQL: builds the image locally (same Dockerfile as the published one) and adds pgAdmin. |
| `docker-compose.hub.yml` | Same as `run-on-any-pc`, for use from the repository root. |
| `src/` | TypeORM entities that mirror the SQL 1:1, plus a naming strategy, the baseline migration and a `GET /health/db` endpoint. These files are copied into the NestJS backend. |
| `.github/workflows/publish-db-image.yml` | Automates section 3: tests pull requests and publishes to Docker Hub when a `db-vX.Y.Z` tag is pushed. It stays inactive until the Docker Hub secrets are added (see [section 9](#9-publish-a-new-version)). |
| `.gitattributes` | Windows Git can turn line endings into CRLF, which breaks shell scripts in Linux containers. This keeps them LF. |
| `.gitignore` | Your real `.env` holds a password, so it never goes to GitHub. Only `.env.example` does. |

---

## 6. Why this repository is public

Both the **GitHub repository** and the **Docker Hub image** are public.

**Why public:**

1. **Teammates and the demo machine get the database with no setup.** `docker pull siam001/bhorsha-db` works
   without a Docker Hub account, without `docker login` and without access to any private repository.
   A private image would make every teammate create an account and log in first.
2. **The image can be checked.** Anyone can read exactly which SQL is inside the image, and verify it with
   `/scripts/verify.sql`.
3. **Reviewers can read the design.** Lecturers, reviewers and employers can read the schema, the rules and
   the tests without asking for access.
4. **Free CI.** GitHub Actions minutes are free and unlimited for public repositories.
5. **Nothing secret is inside.** This was checked before making it public (see below).

**What is public and what stays private:**

```mermaid
flowchart LR
    subgraph PUB["🌐 Public"]
        P1["GitHub: this repository<br/>schema, seed, tests, Dockerfile, docs"]
        P2["Docker Hub: siam001/bhorsha-db<br/>the built image"]
        P3["Demo accounts<br/>(fake people, shared demo password)"]
    end

    subgraph PRIV["🔒 Private, never committed or baked in"]
        S1["Your .env with the real POSTGRES_PASSWORD<br/>blocked from Git by .gitignore<br/>given at docker run, never at build"]
        S2["Docker Hub access token<br/>only in docker login or GitHub Secrets<br/>masked in CI logs"]
        S3["Real data<br/>lives only in Docker volumes, never in Git"]
        S4["Backend application code<br/>separate repository"]
    end
```

**Safety checks done before going public:**

| Check | Result |
|-------|--------|
| `.env` files in the repository | None. `.gitignore` blocks `.env` and allows only `.env.example`. |
| Passwords in the Dockerfile or image | None. `POSTGRES_PASSWORD` is supplied at run time. |
| Tokens / API keys (GitHub, Docker Hub, AWS patterns) | None found by a pattern scan. |
| Passwords in the seed | Only the bcrypt hashes of the shared **demo** password `Bhorsha@123`, which is documented on purpose. |
| Real people's data | None. The demo people are made up. |
| Files sent into the image | Only `db/init/*.sql`, `db/scripts/*.sql`, `build-verify.sh` (enforced by `db/.dockerignore`). |

> ⚠️ The demo password is public. Never use this seed (or `Bhorsha@123`) on a server reachable from the
> internet, and always choose your own `POSTGRES_PASSWORD`.

---

## 7. Database design

Implements the course-release data model of the Bhorsha architecture document (v3.1, section 26): rides
that drivers and riders can *share*, built around **route offers**, **invites**, **join requests** and one
**seat transaction**. Money is stored as integer **paisa** (`bigint`, 1 Tk = 100 paisa), never as floats.

### 7.1 Tables and relationships (ER diagram)

```mermaid
erDiagram
    users ||--o| driver_profiles : "is a driver"
    driver_profiles ||--o{ vehicles : owns
    driver_profiles |o--o{ rides : drives
    vehicles |o--o{ rides : "used on"
    driver_profiles ||--o{ route_offers : posts
    vehicles ||--o{ route_offers : "offered with"
    rides |o--o{ route_offers : "created from"
    rides |o--o{ join_requests : "asked to join"
    route_offers |o--o{ join_requests : "asked to join"
    users ||--o{ join_requests : "rider asks"
    rides ||--o{ ride_passengers : carries
    users ||--o{ ride_passengers : "rides as"
    join_requests |o--o| ride_passengers : "becomes a seat"
    rides ||--o{ ratings : "rated in"
    users ||--o{ ratings : "gives / receives"
    users ||--o{ support_cases : "reports / is subject of"
    rides |o--o{ support_cases : about
    support_cases ||--o{ strikes : "leads to"
    users ||--o{ strikes : receives
    strikes ||--o| appeals : "appealed by"
    users |o--o{ fare_rules : "last edited"
    users |o--o{ audit_logs : "did"

    users {
        int id PK
        varchar full_name
        varchar phone UK "+8801XXXXXXXXX"
        varchar email UK "lower-case"
        varchar password_hash "bcrypt"
        user_role role "RIDER DRIVER ADMIN SUPPORT"
        bool is_active
    }
    driver_profiles {
        int user_id PK, FK
        varchar licence_no UK
        driver_verification verification "PENDING VERIFIED REJECTED"
        driver_status status "OFFLINE ONLINE"
        int reviewed_by FK
    }
    vehicles {
        int id PK
        int driver_id FK
        vehicle_type type "BIKE CAR CNG"
        varchar reg_no
        smallint seats "1-3, bike = 1"
    }
    fare_rules {
        int id PK
        vehicle_type vehicle_type UK
        bigint base_paisa
        bigint per_km_paisa
        bigint ceiling_base_paisa "frozen by trigger"
        bigint ceiling_per_km_paisa "frozen by trigger"
        int share_discount_bps
    }
    rides {
        int id PK
        vehicle_type vehicle_type
        bool is_shared
        smallint seats_total
        smallint seats_free "0..seats_total"
        ride_status status "state machine"
        int driver_id FK
        int vehicle_id FK
        int version "optimistic lock"
    }
    route_offers {
        int id PK
        int driver_id FK
        int ride_id FK
        int vehicle_id FK
        smallint seats_offered
        route_offer_status status
        timestamptz expires_at
    }
    join_requests {
        int id PK
        int ride_id FK "ride OR route offer"
        int route_offer_id FK
        int rider_id FK
        int driver_id FK
        join_initiator initiated_by "RIDER or DRIVER (invite)"
        bigint quoted_fare_paisa "<= ceiling"
        jsonb pricing_snapshot
        join_request_status status
    }
    ride_passengers {
        int id PK
        int ride_id FK
        int rider_id FK
        int join_request_id FK, UK
        smallint seats
        bigint locked_fare_paisa "<= ceiling"
        varchar pickup_pin "4 digits"
        passenger_status status
    }
    ratings {
        int id PK
        int ride_id FK
        int from_user_id FK
        int to_user_id FK
        smallint stars "1-5"
    }
    support_cases {
        int id PK
        case_type type
        case_status status
        int reporter_id FK
        int subject_id FK
        int ride_id FK
        int assigned_to FK
    }
    strikes {
        int id PK
        int user_id FK
        int case_id FK
        int issued_by FK
        strike_status status
        timestamptz expires_at
    }
    appeals {
        int id PK
        int strike_id FK, UK
        appeal_status status
        int decided_by FK "never the issuer"
    }
    audit_logs {
        bigint id PK
        int user_id FK
        varchar action
        jsonb old_value
        jsonb new_value
    }
```

Modules that own the tables: **identity** (`users`), **fleet** (`driver_profiles`, `vehicles`), **pricing**
(`fare_rules`), **trips** (`rides`, `ride_passengers`, `ratings`), **sharing** (`route_offers`,
`join_requests`), **trust** (`support_cases`, `strikes`, `appeals`) and **audit** (`audit_logs`).

### 7.2 Ride life cycle (enforced by a trigger)

Any status change that is not an arrow below is refused by the database (`trg_rides_status_transition`).

```mermaid
stateDiagram-v2
    [*] --> REQUESTED
    REQUESTED --> OFFERING
    REQUESTED --> ACCEPTED
    OFFERING --> ACCEPTED
    ACCEPTED --> ARRIVED
    ARRIVED --> IN_PROGRESS : pickup PIN ok
    IN_PROGRESS --> AWAITING_HANDOVER
    AWAITING_HANDOVER --> IN_PROGRESS
    IN_PROGRESS --> COMPLETED
    REQUESTED --> CANCELLED
    OFFERING --> CANCELLED
    ACCEPTED --> CANCELLED
    ARRIVED --> CANCELLED
    IN_PROGRESS --> CANCELLED
    AWAITING_HANDOVER --> CANCELLED
    COMPLETED --> [*]
    CANCELLED --> [*]
```

Passengers (`CONFIRMED → PICKED_UP → DROPPED`, or `CONFIRMED → CANCELLED / NO_SHOW`) and join requests
(`PENDING → ACCEPTED / DECLINED / EXPIRED`) have their own guarded state machines.

### 7.3 Design decisions

| Area | Decision | Why |
|---|---|---|
| Architecture | One PostgreSQL database, tables owned by modules | The seat transaction and money need one ACID transaction |
| Riders and rides | `ride_passengers` links riders and rides many-to-many | Each passenger has their own seats, PIN, stops, fare and state |
| Proposal vs contract | `join_requests` (consent) separate from `ride_passengers` (seat) | A request becomes a seat only through the seat transaction |
| Concurrency | `SELECT … FOR UPDATE` + `version`; partial unique indexes: one active ride per driver, one live seat per rider | Exactly one winner when two people take the last seat |
| Oversell | `CHECK (seats_free BETWEEN 0 AND seats_total)` | The database refuses an oversold seat even if the app is wrong |
| Legal fare guard | Tariff ≤ ceiling, locked fare ≤ ceiling (CHECKs), ceiling frozen by trigger | The fare promise can't be broken by data or by an admin |
| Vehicles | Composite FK `(vehicle_id, driver_id, vehicle_type)` | One check proves the vehicle exists, is the driver's and has the right type |
| Trust | Strike FK to `(case_id, subject_id)`; separation-of-duties trigger | Due process: the officer who issued a strike can't decide its appeal |
| Derived data | Ratings, strike activity and expiries are computed on read | No background jobs, nothing to drift |
| Pricing evidence | `pricing_snapshot` JSONB on every seat and request | Disputes can be replayed after a fare rule changes |
| Audit | Append-only; refuses rows containing secrets | Audit rows can't be edited or deleted, and leaked secrets can't be stored |

---

## 8. Use it from the NestJS backend

The `src/` folder is the TypeORM side of this schema (ESM, NestJS 12, TypeORM 1.x, TypeScript 6).

1. Copy `src/` and `db/` into the backend project root (`src/app.module.ts` replaces the generated one).
   Keep `db/` at the root: the baseline migration reads `db/init/01_schema.sql`.
2. `cp .env.example .env`, then set `POSTGRES_PASSWORD`.
3. Start the database: `docker compose -f docker-compose.hub.yml up -d` (published image) or
   `docker compose up -d --build` (build locally, adds pgAdmin on http://localhost:5050).
4. Run the backend and check the connection:
   ```bash
   pnpm start:dev
   curl http://localhost:3000/health/db
   # {"status":"ok","database":"bhorsha","latestMigration":"SchemaBaseline1794441600000","users":13,"rides":7,"liveRides":3}
   ```
5. Use entities in the module that owns them:
   ```ts
   import { Ride, RidePassenger, Rating } from '../database/entities/index.js';

   @Module({ imports: [TypeOrmModule.forFeature([Ride, RidePassenger, Rating])], providers: [RidesService] })
   export class TripsModule {}
   ```

**Migrations.** The schema has one SQL source and two ways to apply it. The Docker image runs
`01_schema.sql` on first start. `migration:run` on an empty PostgreSQL runs the same file through
`SchemaBaseline1794441600000`. Both give the same schema. Add to `package.json`:

```json
"db:migrate": "nest build && typeorm migration:run -d dist/database/data-source.js",
"db:revert": "nest build && typeorm migration:revert -d dist/database/data-source.js",
"db:status": "nest build && typeorm migration:show -d dist/database/data-source.js"
```

For the next schema change, never edit `01_schema.sql`. Write a new migration as raw SQL in
`src/database/migrations/`, add it to `MIGRATIONS` in `typeorm.config.ts`, update the entity, and give the
next image version the same change as a new `db/init/0N_*.sql`. Don't use `migration:generate`: it would try
to drop the CHECKs, partial indexes and triggers that TypeORM doesn't model.

---

## 9. Publish a new version

### Version numbers

| Change in `db/init/` | Next version | Example |
|---|---|---|
| Fix seed data, no schema change | patch | `2.0.1` |
| Add tables or columns | minor | `2.1.0` |
| Rename or remove anything (breaking) | major | `3.0.0` |

Teammates pin an exact version (`DB_IMAGE=siam001/bhorsha-db:2.1.0`). After changing the version they run
`docker compose down -v` once, because the init SQL only runs on an empty volume.

### Option A: by hand (how 1.0.0 and 2.0.0 were published)

```bash
docker login -u siam001                                              # paste an access token
docker buildx create --name bhorsha --driver docker-container        # once
docker buildx build ./db --builder bhorsha \
  --platform linux/amd64,linux/arm64 \
  --build-arg VERSION=2.1.0 --build-arg REVISION=$(git rev-parse --short HEAD) \
  -t siam001/bhorsha-db:2.1.0 -t siam001/bhorsha-db:2.1 -t siam001/bhorsha-db:latest \
  --push
docker buildx imagetools inspect siam001/bhorsha-db:2.1.0           # check: amd64 + arm64
```

### Option B: automatically with GitHub Actions

The workflow [`publish-db-image.yml`](.github/workflows/publish-db-image.yml) does the same as Option A on a
GitHub server.

```mermaid
flowchart TB
    E1["Pull request that changes db/**"] --> B["Build both platforms<br/>+ run the verify gate"]
    E2["git push origin db-v2.1.0"] --> B
    E3["Manual run (Actions tab)"] --> B
    B -->|tests fail| F["❌ job fails<br/>nothing pushed"]
    B -->|tests pass, pull request| OK["✅ check passes on the PR<br/>nothing pushed"]
    B -->|tests pass, db-v tag| P1["push 2.1.0 · 2.1 · latest<br/>to siam001/bhorsha-db"]
    B -->|tests pass, manual run| P2["push sha-COMMIT<br/>(for testing a branch)"]
```

**One-time setup** (the workflow can't push to Docker Hub until this is done):

```bash
gh variable set DOCKERHUB_USERNAME --body siam001 -R ALPHAMAN-0/Backend_DB_Bhorsha
gh secret set DOCKERHUB_TOKEN -R ALPHAMAN-0/Backend_DB_Bhorsha     # paste a Docker Hub token (Read & Write)
```

Then release with a tag that starts with `db-v`:

```bash
git tag db-v2.1.0
git push origin db-v2.1.0
```

> Release tags named `vX.Y.Z` (like the `v2.0.0` GitHub release) are only labels and don't start the
> workflow. Only `db-vX.Y.Z` tags publish to Docker Hub.

---

## 10. Demo accounts and demo story

Password for **all** demo accounts: `Bhorsha@123`

| id | Name | Email | Role | In the demo |
|---|---|---|---|---|
| 1 | Bhorsha Admin | admin@bhorsha.test | ADMIN | verified the drivers; edited the car tariff |
| 2 | Farhana Islam | support@bhorsha.test | SUPPORT | issued strike 1; may decide appeal 2 |
| 3 | Nusrat Jahan | rider@bhorsha.test | RIDER | waiting on ride 5; invited onto ride 4 |
| 4 | Tanvir Rahman | rider2@bhorsha.test | RIDER | strike 2 under appeal; asked to join ride 4 and Abul's offer |
| 5 | Karim Mia | driver.karim@bhorsha.test | DRIVER (car) | one counting strike; online near ride 5 |
| 6 | Jamal Hossain | driver.jamal@bhorsha.test | DRIVER (car) | driving shared ride 4, one seat left |
| 7 | Rafiq Ahmed | driver.rafiq@bhorsha.test | DRIVER (bike) | accepted ride 7 |
| 8 | Shakil Khan | driver.shakil@bhorsha.test | DRIVER (bike) | PENDING verification (admin queue) |
| 9 | Abul Kalam | driver.abul@bhorsha.test | DRIVER (CNG) | heading home: route offer 2, no ride yet |
| 10 | Mahmud Hasan | support2@bhorsha.test | SUPPORT | issued strike 2 (so he can't decide appeal 2); decided appeal 1 |
| 11 | Sadia Afrin | rider3@bhorsha.test | RIDER | joined ride 2 by invite; waiting for pickup on ride 4 |
| 12 | Rumana Akter | rider4@bhorsha.test | RIDER | aboard ride 4 |
| 13 | Imran Hossain | rider5@bhorsha.test | RIDER | ride 7, pickup PIN 9150 |

| Demo | What to try |
|---|---|
| Ride 1 (completed solo car, 10 km) | Fare Tk 260 vs ceiling Tk 357; overcharge case → strike (Farhana) → appeal rejected (Mahmud) |
| Ride 2 (completed shared car) | Sadia joined through Jamal's invite; co-rider case → strike on a **rider** → appeal pending |
| Ride 3 (completed solo bike) | OPEN safety case in the support queue |
| Ride 4 (shared car, IN_PROGRESS) | **Last seat:** accept join request 4 (Tanvir) or invite 5 (Nusrat). The first wins, the second gets 409 |
| Ride 5 (REQUESTED shared car) | `GET /rides/open` as Karim (within 3 km) and accept it |
| Ride 7 (ACCEPTED solo bike) | As Rafiq: arrive → pickup with PIN 9150 → drop off |
| Route offer 2 | As Abul: accept join request 6; the seat transaction creates the ride |
| Appeal 2 | Mahmud deciding it gets 403 (the database refuses it too); Farhana or the admin can |

Request windows in the seed last 2 hours so they can be answered from Swagger. All timestamps are relative
to `now()`, so `docker compose down -v` always gives fresh data.

---

## 11. Rules for the team

The database enforces these rules. The app must work with them, not against them.

1. **`synchronize` stays `false`**, and migrations are hand-written SQL.
2. **Never insert explicit ids.** Keys are `GENERATED ALWAYS AS IDENTITY`. An explicit id fails (`428C9`).
3. **Money is integer paisa.** Compute fares in paisa and round once, half up.
4. **Every state change is a conditional update:**
   `WHERE id = :id AND status = :expected AND version = :version`. If `affected` is 0, return 409.
5. **Seat transaction order** (accepting a join request or an invite): lock the route offer → lock the rides in
   id order → check seats → cancel the rider's own waiting seat and ride → insert the passenger →
   `seats_free - n` → accept the request `WHERE status = 'PENDING'` → COMMIT.
6. **Seats change with passengers.** On a shared ride, every pickup cancel, no-show and drop-off updates
   `rides.seats_free` in the same transaction.
7. **Error mapping:** `23505`, `23503`, `23514` → 409; `ck_appeals_separation_of_duties` → 403;
   `40P01`, `40001`, `55P03` → 409 (retry).
8. **Secrets stay out of the audit log.** `password_hash` and `pickup_pin` are never selected by default.
9. **Emails are stored lower-case, phones as `+8801XXXXXXXXX`.**

```ts
// Accept a ride: exactly one driver wins, the other gets 409
const result = await this.dataSource.createQueryBuilder().update(Ride)
  .set({ status: RideStatus.ACCEPTED, driverId, vehicleId, acceptedAt: () => 'now()' })
  .where('id = :id AND status = :expected AND version = :version', { id, expected: RideStatus.REQUESTED, version })
  .execute();
if (result.affected === 0) throw new ConflictException('Ride is no longer available');
```

---

## 12. Daily commands and troubleshooting

| Task | Command |
|---|---|
| Stop (keep data) | `docker compose stop` |
| Start again | `docker compose start` |
| Get a newer image | `docker compose pull && docker compose up -d` |
| **Reset to clean demo data** | `docker compose down -v && docker compose up -d` |
| SQL shell | `docker compose exec db psql -U bhorsha -d bhorsha` |
| Backup | `docker compose exec db pg_dump -U bhorsha bhorsha > backup.sql` |

| Problem | Fix |
|---|---|
| `port is already allocated` | Change `DB_PORT` in `.env` (for example `5434`), then `docker compose up -d` |
| `POSTGRES_PASSWORD` error on `up` | Create `.env` from `.env.example` |
| `password authentication failed` | The volume keeps the first password. Use it, or `docker compose down -v` |
| Old tables (`wallets`, `rides.rider_id`) | The volume is from v1.0.0: `docker compose down -v` and start again |
| `pull access denied` / `manifest unknown` | Wrong `DB_IMAGE` name or the tag doesn't exist. Check https://hub.docker.com/r/siam001/bhorsha-db/tags |
| `exec format error` | The image was pushed for one CPU only. Publish with `--platform linux/amd64,linux/arm64` |
| Build fails at `verify: loading ...sql` | That SQL file is broken. The error line is in the build output |
| Build fails at `verify.sql` / `constraint-tests` | Seed data breaks a demo number or a rule. Read the `FAIL` line |
| 409 on a request answered in Swagger | The seeded request expired (2 hours after first start): `docker compose down -v` |

---

## 13. Version history

| Version | Date | What changed |
|---|---|---|
| **2.0.0** | 2026-11-12 | Architecture v3.1: 13 tables, shared rides (`ride_passengers`, `route_offers`, `join_requests`), money in paisa, guarded state machines, strikes on riders too, separation of duties, TypeORM baseline migration. **Breaking:** run `docker compose down -v` once. |
| 1.0.0 | 2026-11-11 | First version: the older 20-table proposal, one rider per ride, money as `numeric(10,2)`. |

> The `2.0.0` image on Docker Hub carries the label `licenses=UNLICENSED`, because it was built before this
> repository got its MIT license. The next published version will carry `MIT`.

## License

[MIT](LICENSE) © 2026 SIAM HOSSAIN
