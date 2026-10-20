package app.logos.user;

import app.logos.bible.BibleCatalog;
import app.logos.bible.BibleModels.Verse;
import app.logos.bible.VerseRefNormalizer;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** A batch commits together. Invalid items remain retryable; SQL failures roll back the batch. */
@Service
public class GuestImportService {
    private static final int BATCH_LIMIT = 100;
    private static final int REFERENCE_LIMIT = 100;
    private static final int CONTENT_LIMIT_BYTES = 50_000;
    private static final Duration CLOCK_SKEW = Duration.ofHours(24);
    private final JdbcTemplate jdbc;
    private final BibleCatalog catalog;
    private final VerseRefNormalizer references;
    private final ObjectMapper mapper;

    public GuestImportService(JdbcTemplate jdbc, BibleCatalog catalog, VerseRefNormalizer references, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.catalog = catalog;
        this.references = references;
        this.mapper = mapper;
    }

    private record Validated(GuestDataItem item, UUID revision, String hash, String key,
                             List<Verse> verses, Instant created, Instant updated, boolean deleted) { }

    @Transactional
    public Map<String, Object> importData(long user, List<GuestDataItem> items) {
        if (items == null || items.isEmpty() || items.size() > BATCH_LIMIT) {
            throw new IllegalArgumentException("每批导入 1–100 条数据");
        }
        // Serialize imports for this user, including first-time natural keys and tombstones.
        jdbc.queryForObject("SELECT id FROM app_user WHERE id=? FOR UPDATE", Long.class, user);
        Set<String> keys = new LinkedHashSet<>(items.size());
        for (GuestDataItem item : items) {
            if (item == null || item.clientKey() == null || !keys.add(item.clientKey())) {
                throw new IllegalArgumentException("批次 clientKey 必须非空且唯一");
            }
        }
        List<String> failed = new ArrayList<>();
        int imported = 0;
        Instant now = Instant.now().truncatedTo(ChronoUnit.MICROS);
        for (GuestDataItem item : items) {
            Validated value;
            try {
                value = validate(item, now);
                List<String> receipts = jdbc.queryForList(
                        "SELECT payload_hash FROM guest_import_receipt WHERE user_id=? AND revision=?",
                        String.class, user, value.revision());
                if (!receipts.isEmpty()) {
                    if (!receipts.getFirst().equals(value.hash())) {
                        failed.add(item.clientKey());
                    }
                    continue;
                }
            } catch (IllegalArgumentException exception) {
                // Validation has not written anything. Never log personal payloads here.
                failed.add(item.clientKey());
                continue;
            }
            if ("PROGRESS".equals(item.type()) || isNewer(user, value)) {
                boolean changed = apply(user, value);
                if (!"PROGRESS".equals(item.type())) {
                    saveState(user, value);
                }
                if (changed) {
                    imported++;
                }
            }
            jdbc.update("INSERT INTO guest_import_receipt(user_id,revision,payload_hash) VALUES(?,?,?)",
                    user, value.revision(), value.hash());
        }
        return Map.of("imported", imported, "failed", failed);
    }

    private Validated validate(GuestDataItem item, Instant now) {
        if (item.clientKey().isBlank() || item.clientKey().length() > 36) {
            throw new IllegalArgumentException("无效 clientKey");
        }
        UUID revision;
        Instant created;
        Instant updated;
        try {
            revision = UUID.fromString(item.revision());
            created = Instant.parse(item.createdAt());
            updated = Instant.parse(item.updatedAt());
        } catch (RuntimeException exception) {
            throw new IllegalArgumentException("无效版本或时间戳", exception);
        }
        if (Duration.between(created, now).abs().compareTo(CLOCK_SKEW) > 0) {
            created = now;
        }
        // Historical edit times are needed for offline LWW; bound future clock poisoning.
        if (updated.isAfter(now.plus(CLOCK_SKEW))) {
            updated = now;
        }
        updated = updated.truncatedTo(ChronoUnit.MICROS);
        if (updated.isBefore(Instant.parse("0001-01-01T00:00:00Z"))) {
            throw new IllegalArgumentException("更新时间超出范围");
        }
        boolean deleted = "DELETE".equals(item.operation());
        if (!deleted && !"UPSERT".equals(item.operation())) {
            throw new IllegalArgumentException("无效操作");
        }
        checkLength(item.content(), CONTENT_LIMIT_BYTES);
        checkLength(item.title(), 200);
        checkLength(item.note(), 2000);
        checkLength(item.chapterRange(), 30);
        List<Verse> verses = resolve(item.verseRefs());
        if (item.type() == null) {
            throw new IllegalArgumentException("无效导入类型");
        }
        String key = switch (item.type()) {
            case "BOOKMARK" -> {
                if (verses.size() != 1 || (item.color() != null && !item.color().matches("#[0-9a-fA-F]{6}"))) {
                    throw new IllegalArgumentException("无效收藏引用或颜色");
                }
                yield verses.getFirst().id();
            }
            case "NOTE" -> {
                if (!deleted && (item.content() == null || item.content().isBlank())) {
                    throw new IllegalArgumentException("笔记正文不能为空");
                }
                if (item.tags() != null && (item.tags().size() > 20
                        || item.tags().stream().anyMatch(t -> t == null || t.length() > 30))) {
                    throw new IllegalArgumentException("无效标签");
                }
                yield item.clientKey();
            }
            case "PROGRESS" -> progressKey(item, deleted);
            case "FEED_RECORD" -> {
                if (deleted || !"SCRIPTURE_SHARED".equals(item.recordType()) || verses.isEmpty()) {
                    throw new IllegalArgumentException("仅支持分享记录导入");
                }
                yield item.clientKey();
            }
            default -> throw new IllegalArgumentException("无效导入类型");
        };
        return new Validated(item, revision, hash(item), key, verses, created, updated, deleted);
    }

    private String progressKey(GuestDataItem item, boolean deleted) {
        var book = catalog.book(item.bookCode());
        if (deleted || book == null || item.chapter() == null || item.verse() == null
                || catalog.verses(catalog.chapter(book.bookCode(), item.chapter())).stream()
                .noneMatch(v -> v.verse() == item.verse())) {
            throw new IllegalArgumentException("无效阅读进度");
        }
        return book.bookCode() + "." + item.chapter();
    }

    private void checkLength(String text, int limit) {
        if (text != null && (text.length() > limit
                || (limit == CONTENT_LIMIT_BYTES && text.getBytes(StandardCharsets.UTF_8).length > limit))) {
            throw new IllegalArgumentException("导入字段过长");
        }
    }

    private List<Verse> resolve(List<String> refs) {
        if (refs == null) {
            return List.of();
        }
        if (refs.size() > REFERENCE_LIMIT) {
            throw new IllegalArgumentException("关联经文过多");
        }
        Set<Verse> result = new LinkedHashSet<>();
        for (String ref : refs) {
            List<Verse> resolved = references.resolve(ref);
            if (resolved.isEmpty()) {
                throw new IllegalArgumentException("无效经文引用");
            }
            result.addAll(resolved);
            if (result.size() > REFERENCE_LIMIT) {
                throw new IllegalArgumentException("关联经文过多");
            }
        }
        return List.copyOf(result);
    }

    private String hash(GuestDataItem item) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(mapper.writeValueAsBytes(item)));
        } catch (NoSuchAlgorithmException | JsonProcessingException exception) {
            throw new IllegalStateException("SHA-256 unavailable", exception);
        }
    }

    private boolean isNewer(long user, Validated value) {
        return jdbc.query("""
                SELECT updated_at,deleted FROM guest_import_state
                WHERE user_id=? AND kind=? AND entity_key=?
                """, (row, index) -> {
                    int comparison = value.updated().compareTo(row.getObject("updated_at", OffsetDateTime.class).toInstant());
                    // Deletion wins equal timestamps; an older UPSERT cannot restore a tombstone.
                    return comparison > 0 || (comparison == 0 && value.deleted() && !row.getBoolean("deleted"));
                }, user, value.item().type(), value.key()).stream().findFirst().orElse(true);
    }

    private void saveState(long user, Validated value) {
        jdbc.update("""
                INSERT INTO guest_import_state(user_id,kind,entity_key,updated_at,deleted) VALUES(?,?,?,?,?)
                ON CONFLICT(user_id,kind,entity_key) DO UPDATE
                SET updated_at=EXCLUDED.updated_at,deleted=EXCLUDED.deleted
                """, user, value.item().type(), value.key(), value.updated().atOffset(ZoneOffset.UTC), value.deleted());
    }

    private boolean apply(long user, Validated value) {
        return switch (value.item().type()) {
            case "BOOKMARK" -> bookmark(user, value);
            case "NOTE" -> note(user, value);
            case "PROGRESS" -> progress(user, value);
            case "FEED_RECORD" -> share(user, value);
            default -> throw new IllegalStateException("Unvalidated import type");
        };
    }

    private boolean bookmark(long user, Validated value) {
        var item = value.item();
        if (value.deleted()) {
            return jdbc.update("DELETE FROM user_bookmark WHERE user_id=? AND verse_id=? AND updated_at<=?",
                    user, Long.valueOf(value.key()), value.updated().atOffset(ZoneOffset.UTC)) > 0;
        }
        List<Long> ids = jdbc.queryForList("""
                INSERT INTO user_bookmark(user_id,verse_id,note,color,created_at,updated_at) VALUES(?,?,?,?,?,?)
                ON CONFLICT(user_id,verse_id) DO UPDATE
                SET note=EXCLUDED.note,color=EXCLUDED.color,updated_at=EXCLUDED.updated_at
                WHERE user_bookmark.updated_at < EXCLUDED.updated_at RETURNING id
                """, Long.class, user, Long.valueOf(value.key()), item.note(), item.color(),
                value.created().atOffset(ZoneOffset.UTC), value.updated().atOffset(ZoneOffset.UTC));
        if (ids.isEmpty()) {
            return false;
        }
        jdbc.update("INSERT INTO feed_record(user_id,type,verse_id,bookmark_id,created_at) VALUES(?,?,?,?,?)",
                user, item.color() == null ? "BOOKMARK_ADDED" : "SCRIPTURE_HIGHLIGHT",
                Long.valueOf(value.key()), ids.getFirst(), value.created().atOffset(ZoneOffset.UTC));
        return true;
    }

    private boolean note(long user, Validated value) {
        var item = value.item();
        if (value.deleted()) {
            return jdbc.update("DELETE FROM user_note WHERE user_id=? AND client_key=? AND updated_at<=?",
                    user, value.key(), value.updated().atOffset(ZoneOffset.UTC)) > 0;
        }
        boolean exists = Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT EXISTS(SELECT 1 FROM user_note WHERE user_id=? AND client_key=?)",
                Boolean.class, user, value.key()));
        String[] tags = item.tags() == null ? new String[0] : item.tags().toArray(String[]::new);
        List<Long> ids = jdbc.queryForList("""
                INSERT INTO user_note(user_id,client_key,title,content,chapter_range,tags,created_at,updated_at)
                VALUES(?,?,?,?,?,?::text[],?,?) ON CONFLICT(user_id,client_key) DO UPDATE
                SET title=EXCLUDED.title,content=EXCLUDED.content,chapter_range=EXCLUDED.chapter_range,
                tags=EXCLUDED.tags,updated_at=EXCLUDED.updated_at
                WHERE user_note.updated_at < EXCLUDED.updated_at RETURNING id
                """, Long.class, user, value.key(), item.title(), item.content(), item.chapterRange(), tags,
                value.created().atOffset(ZoneOffset.UTC), value.updated().atOffset(ZoneOffset.UTC));
        if (ids.isEmpty()) {
            return false;
        }
        long id = ids.getFirst();
        jdbc.update("DELETE FROM user_note_verse WHERE note_id=?", id);
        for (Verse verse : value.verses()) {
            jdbc.update("INSERT INTO user_note_verse(note_id,verse_id) VALUES(?,?)", id, Long.valueOf(verse.id()));
        }
        if (!exists) {
            jdbc.update("INSERT INTO feed_record(user_id,type,note_id,verse_id,created_at) VALUES(?,'NOTE_CREATED',?,?,?)",
                    user, id, value.verses().isEmpty() ? null : Long.valueOf(value.verses().getFirst().id()),
                    value.created().atOffset(ZoneOffset.UTC));
        }
        return true;
    }

    private boolean progress(long user, Validated value) {
        var item = value.item();
        return jdbc.update("""
                INSERT INTO reading_progress(user_id,book_id,chapter,verse,read_at) VALUES(?,?,?,?,?)
                ON CONFLICT(user_id,book_id,chapter) DO UPDATE
                SET verse=GREATEST(reading_progress.verse,EXCLUDED.verse),
                read_at=GREATEST(reading_progress.read_at,EXCLUDED.read_at)
                WHERE reading_progress.verse < EXCLUDED.verse OR reading_progress.read_at < EXCLUDED.read_at
                """, user, Long.valueOf(catalog.book(item.bookCode()).id()), item.chapter(), item.verse(),
                value.updated().atOffset(ZoneOffset.UTC)) > 0;
    }

    private boolean share(long user, Validated value) {
        Long[] verseIds = value.verses().stream().map(v -> Long.valueOf(v.id())).toArray(Long[]::new);
        return jdbc.update("""
                INSERT INTO feed_record(user_id,type,client_key,verse_id,verse_ids,content,created_at)
                VALUES(?,'SCRIPTURE_SHARED',?,?,?::bigint[],?,?)
                ON CONFLICT(user_id,client_key) DO NOTHING
                """, user, value.key(), verseIds[0], verseIds, value.item().content(),
                value.created().atOffset(ZoneOffset.UTC)) > 0;
    }
}
