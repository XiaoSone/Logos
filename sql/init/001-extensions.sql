CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- Business schema is owned by backend/src/main/resources/schema.sql.
-- The dev backend imports the pinned Bible snapshot transactionally at startup.
