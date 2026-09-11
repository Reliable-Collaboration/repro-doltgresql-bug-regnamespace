# DoltgreSQL 1.3.1: casts to regnamespace fail with "unable to resolve type"

On DoltgreSQL 1.3.1, a cast to `regnamespace` fails, whether it casts a schema's name or a schema's OID:

```
psql:/tmp/repro.sql:2: ERROR:  unable to resolve type `regnamespace`
psql:/tmp/repro.sql:6: ERROR:  unable to resolve type `regnamespace`
```

Casts to `regclass` and `regtype` in the same test work. PostgreSQL 18.6 answers `public` for both casts
to `regnamespace`.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-regnamespace.git
cd repro-doltgresql-bug-regnamespace
./repro.sh
```

`repro.sh` starts PostgreSQL 18.6 and DoltgreSQL 1.3.1 in two throwaway containers, waits until both
accept connections, runs [`repro.sql`](repro.sql) on each with the `psql` client inside its container,
prints the two outputs side by side, and removes the containers. It exits 0 when DoltgreSQL's output is
identical to PostgreSQL's, and 1 when it differs.

To try another DoltgreSQL release, name its image:

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory. PostgreSQL first:

```sh
docker run -d --name repro-doltgresql-bug-regnamespace-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker cp repro.sql repro-doltgresql-bug-regnamespace-postgres:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-regnamespace-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-regnamespace-postgres
```

Then DoltgreSQL:

```sh
docker run -d --name repro-doltgresql-bug-regnamespace-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-regnamespace-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-regnamespace-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-regnamespace-doltgresql
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few
seconds and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
-- A schema name cast to regnamespace.
SELECT 'public'::regnamespace;

-- A schema's OID cast to regnamespace.
SELECT oid::regnamespace FROM pg_namespace
WHERE nspname = 'public';

-- Controls: a table name cast to regclass, and a type
-- name cast to regtype.
SELECT 'pg_class'::regclass;
SELECT 'integer'::regtype;
```

## Expected behavior

Both casts to `regnamespace` answer `public`, and the controls answer `pg_class` and `integer`. This is
what PostgreSQL 18.6 does:

```
-- A schema name cast to regnamespace.
SELECT 'public'::regnamespace;
 regnamespace 
--------------
 public
(1 row)

-- A schema's OID cast to regnamespace.
SELECT oid::regnamespace FROM pg_namespace
WHERE nspname = 'public';
  oid   
--------
 public
(1 row)

-- Controls: a table name cast to regclass, and a type
-- name cast to regtype.
SELECT 'pg_class'::regclass;
 regclass 
----------
 pg_class
(1 row)

SELECT 'integer'::regtype;
 regtype 
---------
 integer
(1 row)
```

## Actual behavior

Both casts to `regnamespace` fail, and the controls answer the same as on PostgreSQL. This is what
DoltgreSQL 1.3.1 does:

```
-- A schema name cast to regnamespace.
SELECT 'public'::regnamespace;
psql:/tmp/repro.sql:2: ERROR:  unable to resolve type `regnamespace`
-- A schema's OID cast to regnamespace.
SELECT oid::regnamespace FROM pg_namespace
WHERE nspname = 'public';
psql:/tmp/repro.sql:6: ERROR:  unable to resolve type `regnamespace`
-- Controls: a table name cast to regclass, and a type
-- name cast to regtype.
SELECT 'pg_class'::regclass;
 regclass 
----------
 pg_class
(1 row)

SELECT 'integer'::regtype;
 regtype 
---------
 integer
(1 row)
```

## Side by side

The full output of `./repro.sh`. A line wider than its column is cut off at the column's edge, as both
errors are here; the whole errors are under Actual behavior.

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- A schema name cast to regnamespace.                        -- A schema name cast to regnamespace.
SELECT 'public'::regnamespace;                                SELECT 'public'::regnamespace;
 regnamespace                                               | psql:/tmp/repro.sql:2: ERROR:  unable to resolve type `regn
--------------                                              <
 public                                                     <
(1 row)                                                     <
                                                            <
-- A schema's OID cast to regnamespace.                       -- A schema's OID cast to regnamespace.
SELECT oid::regnamespace FROM pg_namespace                    SELECT oid::regnamespace FROM pg_namespace
WHERE nspname = 'public';                                     WHERE nspname = 'public';
  oid                                                       | psql:/tmp/repro.sql:6: ERROR:  unable to resolve type `regn
--------                                                    <
 public                                                     <
(1 row)                                                     <
                                                            <
-- Controls: a table name cast to regclass, and a type        -- Controls: a table name cast to regclass, and a type
-- name cast to regtype.                                      -- name cast to regtype.
SELECT 'pg_class'::regclass;                                  SELECT 'pg_class'::regclass;
 regclass                                                      regclass 
----------                                                    ----------
 pg_class                                                      pg_class
(1 row)                                                       (1 row)

SELECT 'integer'::regtype;                                    SELECT 'integer'::regtype;
 regtype                                                       regtype 
---------                                                     ---------
 integer                                                       integer
(1 row)                                                       (1 row)


Result: DoltgreSQL's output differs from PostgreSQL's on 2 line(s), marked with |.
```

## Other observations

Each was run on the same two images with the `psql` client inside each container:

- Every other form of the cast fails the same way: `CAST('public' AS regnamespace)`, `2200::regnamespace`,
  `'public'::text::regnamespace`, `relnamespace::regnamespace` over `pg_class`, and the filter
  `WHERE relnamespace = 'pg_catalog'::regnamespace`. PostgreSQL answers each.
- `CREATE TABLE r (n regnamespace)` answers `type "regnamespace" does not exist`, and
  `to_regnamespace('public')` answers `function: 'to_regnamespace' not found`. PostgreSQL creates the
  table and answers `public`.
- A quoted type name, `'public'::"regnamespace"`, fails the same way, and so does the cast after
  `SET search_path = pg_catalog, public`.
- The schema-qualified type name is accepted, but as the type `unknown`:
  `pg_typeof('public'::pg_catalog.regnamespace)` answers `unknown`, where PostgreSQL answers
  `regnamespace`. `'public'::pg_catalog.regnamespace` answers `public`, while
  `'public'::pg_catalog.regnamespace::oid` answers `invalid input syntax for type oid: "public"`
  (PostgreSQL: `2200`),
  `2200::pg_catalog.regnamespace` answers ``EXPLICIT CAST: cast from `integer` to `unknown` does not
  exist: 2200`` (PostgreSQL: `public`), and `'no_such_schema'::pg_catalog.regnamespace` answers
  `no_such_schema`, where PostgreSQL answers `schema "no_such_schema" does not exist`.
- `pg_type` lists three reg types on DoltgreSQL, `regclass`, `regproc` and `regtype`, and 11 on
  PostgreSQL. `'now'::regproc` works on both; casts to `regprocedure`, `regrole`, `regoper`,
  `regoperator`, `regconfig`, `regdictionary` and `regcollation` fail on DoltgreSQL with
  ``unable to resolve type `regrole` `` and so on.
- `regclass` matches PostgreSQL by name but not by OID: `1259::regclass` answers `1259`, where PostgreSQL
  answers `pg_class`. DoltgreSQL's `pg_class` row for `pg_class` has OID 985825787, and no row has OID
  1259.
- An unknown type gets the same error: `SELECT 'x'::no_such_type` answers
  ``unable to resolve type `no_such_type` ``, where PostgreSQL answers `type "no_such_type" does not exist`.
- Upstream, issue [#794](https://github.com/dolthub/doltgresql/issues/794), "`regprocedure` type
  support", open, asks for another of the missing reg types.

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its `psql` is 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Linux x86_64 (WSL 2).
