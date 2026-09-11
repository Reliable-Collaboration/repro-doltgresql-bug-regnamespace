-- A schema name cast to regnamespace.
SELECT 'public'::regnamespace;

-- A schema's OID cast to regnamespace.
SELECT oid::regnamespace FROM pg_namespace
WHERE nspname = 'public';

-- Controls: a table name cast to regclass, and a type
-- name cast to regtype.
SELECT 'pg_class'::regclass;
SELECT 'integer'::regtype;
