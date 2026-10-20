CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE TABLE IF NOT EXISTS bible_book (
 id BIGINT PRIMARY KEY, book_code VARCHAR(10) NOT NULL UNIQUE, book_name_zh VARCHAR(20) NOT NULL,
 book_name_en VARCHAR(30) NOT NULL, book_name_abbr VARCHAR(10) NOT NULL,
 testament SMALLINT NOT NULL CHECK(testament IN (1,2)), book_order SMALLINT NOT NULL UNIQUE,
 chapter_count SMALLINT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS bible_verse (
 id BIGINT PRIMARY KEY, book_id BIGINT NOT NULL REFERENCES bible_book(id), book_code VARCHAR(10) NOT NULL,
 chapter SMALLINT NOT NULL, verse SMALLINT NOT NULL, text_zh TEXT NOT NULL, text_en TEXT,
 verse_ref VARCHAR(30) GENERATED ALWAYS AS (book_code || ' ' || chapter || ':' || verse) STORED,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(book_code,chapter,verse)
);
CREATE INDEX IF NOT EXISTS idx_verse_text_zh_trgm ON bible_verse USING gin(text_zh gin_trgm_ops);
CREATE TABLE IF NOT EXISTS verse_section (
 id VARCHAR(40) PRIMARY KEY, book_code VARCHAR(10) NOT NULL, chapter SMALLINT NOT NULL,
 section_index SMALLINT NOT NULL, section_title TEXT, verse_start SMALLINT NOT NULL,
 verse_end SMALLINT NOT NULL, verse_count SMALLINT NOT NULL, is_poetry BOOLEAN NOT NULL,
 UNIQUE(book_code,chapter,section_index)
);
CREATE TABLE IF NOT EXISTS verse_footnote (
 id VARCHAR(60) PRIMARY KEY, verse_id BIGINT NOT NULL REFERENCES bible_verse(id),
 offset_start INT NOT NULL, offset_end INT NOT NULL, content TEXT NOT NULL, UNIQUE(verse_id,offset_start)
);
CREATE TABLE IF NOT EXISTS app_user (
 id BIGSERIAL PRIMARY KEY, phone VARCHAR(30) NOT NULL UNIQUE, nickname VARCHAR(50),
 status SMALLINT NOT NULL DEFAULT 1, last_login_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS user_device (
 id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
 device_id VARCHAR(100) NOT NULL, device_type VARCHAR(20), app_version VARCHAR(20),
 last_active_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(user_id,device_id)
);
CREATE TABLE IF NOT EXISTS user_bookmark (
 id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
 verse_id BIGINT NOT NULL REFERENCES bible_verse(id), note TEXT, color VARCHAR(10),
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(user_id,verse_id)
);
CREATE TABLE IF NOT EXISTS user_note (
 id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
 title VARCHAR(200), chapter_range VARCHAR(30), content TEXT NOT NULL,
 tags TEXT[] NOT NULL DEFAULT '{}', client_key VARCHAR(36),
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(user_id,client_key)
);
CREATE TABLE IF NOT EXISTS user_note_verse (
 note_id BIGINT NOT NULL REFERENCES user_note(id) ON DELETE CASCADE,
 verse_id BIGINT NOT NULL REFERENCES bible_verse(id), PRIMARY KEY(note_id,verse_id)
);
ALTER TABLE user_note ALTER COLUMN client_key SET DEFAULT gen_random_uuid()::text;
UPDATE user_note SET client_key=gen_random_uuid()::text WHERE client_key IS NULL;
ALTER TABLE user_note ALTER COLUMN client_key SET NOT NULL;
CREATE TABLE IF NOT EXISTS reading_progress (
 id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
 book_id BIGINT NOT NULL REFERENCES bible_book(id), chapter SMALLINT NOT NULL, verse SMALLINT NOT NULL DEFAULT 1,
 read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(user_id,book_id,chapter)
);
CREATE TABLE IF NOT EXISTS feed_record (
 id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
 type VARCHAR(30) NOT NULL, verse_id BIGINT REFERENCES bible_verse(id),
 note_id BIGINT REFERENCES user_note(id) ON DELETE CASCADE,
 bookmark_id BIGINT REFERENCES user_bookmark(id) ON DELETE CASCADE, content TEXT, client_key VARCHAR(36),
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(user_id,client_key)
);
CREATE INDEX IF NOT EXISTS idx_feed_user_cursor ON feed_record(user_id,created_at DESC,id DESC);
ALTER TABLE feed_record ADD COLUMN IF NOT EXISTS verse_ids BIGINT[] NOT NULL DEFAULT '{}';
-- Durable import receipts survive resource deletion, so delayed retries cannot recreate it.
CREATE TABLE IF NOT EXISTS guest_import_receipt (
 user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
 revision UUID NOT NULL, payload_hash CHAR(64) NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY(user_id,revision)
);
CREATE TABLE IF NOT EXISTS guest_import_state (
 user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
 kind VARCHAR(20) NOT NULL, entity_key VARCHAR(100) NOT NULL,
 updated_at TIMESTAMPTZ NOT NULL, deleted BOOLEAN NOT NULL,
 PRIMARY KEY(user_id,kind,entity_key)
);
CREATE TABLE IF NOT EXISTS daily_verse_seed (
 month_day CHAR(5) PRIMARY KEY, verse_id BIGINT NOT NULL REFERENCES bible_verse(id), theme VARCHAR(100), meditation TEXT
);
CREATE TABLE IF NOT EXISTS daily_verse (
 date DATE PRIMARY KEY, verse_id BIGINT NOT NULL REFERENCES bible_verse(id), theme VARCHAR(100), meditation TEXT
);
CREATE TABLE IF NOT EXISTS invite_code (
 id BIGSERIAL PRIMARY KEY, code VARCHAR(50) NOT NULL UNIQUE, max_uses INT NOT NULL,
 used_count INT NOT NULL DEFAULT 0, expires_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS bible_device_key (
 device_id VARCHAR(100) NOT NULL, bible_version VARCHAR(20) NOT NULL, device_key BYTEA NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 PRIMARY KEY(device_id,bible_version)
);
