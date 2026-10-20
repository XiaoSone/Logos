package app.logos;

import app.logos.auth.TokenService;
import app.logos.user.GuestDataItem;
import app.logos.user.GuestImportService;
import app.logos.user.PersonalService;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.graphql.tester.AutoConfigureHttpGraphQlTester;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataAccessException;
import org.springframework.graphql.test.tester.HttpGraphQlTester;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import static org.assertj.core.api.Assertions.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureHttpGraphQlTester
@ActiveProfiles("dev")
class GuestImportIntegrationTest {
    private static final String MUTATION = "mutation($items:[GuestDataItem!]!){importGuestData(items:$items){imported failed}}";
    private final List<Long> users = new ArrayList<>();
    private final Instant base = Instant.now().minusSeconds(3600).truncatedTo(ChronoUnit.MICROS);
    @Autowired HttpGraphQlTester graphql;
    @Autowired TokenService tokens;
    @Autowired GuestImportService imports;
    @Autowired PersonalService personal;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper mapper;

    private long user() {
        String phone = "test-" + UUID.randomUUID().toString().substring(0, 20);
        long id = jdbc.queryForObject("INSERT INTO app_user(phone) VALUES(?) RETURNING id", Long.class, phone);
        users.add(id);
        return id;
    }

    @AfterEach void cleanUp() {
        for (long id : users) {
            jdbc.update("DELETE FROM app_user WHERE id=?", id);
        }
    }

    private GuestDataItem item(String type, String key, Instant time, Map<String, Object> fields) {
        Map<String, Object> values = new HashMap<>(fields);
        values.put("type", type);
        values.put("clientKey", key);
        values.putIfAbsent("revision", UUID.randomUUID().toString());
        values.putIfAbsent("operation", "UPSERT");
        values.putIfAbsent("createdAt", time.toString());
        values.putIfAbsent("updatedAt", time.toString());
        return mapper.convertValue(values, GuestDataItem.class);
    }

    private int count(String table, long user) {
        // All callers supply test-owned, constant table names.
        return jdbc.queryForObject("SELECT COUNT(*) FROM " + table + " WHERE user_id=?", Integer.class, user);
    }

    private HttpGraphQlTester authenticated(long user) {
        return graphql.mutate().header("Authorization", "Bearer " + tokens.issue(
                String.valueOf(user), "user", "import-test-device", 3600)).build();
    }

    @Test void testAccountSnapshotUsesStableKeysAndIsUserScoped() {
        long first=user(), second=user();
        var note=personal.saveNote(first,null,"云端原有笔记",List.of("43003016"),null,"正文",List.of("带,逗号"));
        personal.saveBookmark(first,"43003016","备注",null);
        personal.reportProgress(first,"JOHN",3,16);
        imports.importData(first,List.of(item("FEED_RECORD","share",base,Map.of(
                "verseRefs",List.of("约3:16-17"),"recordType","SCRIPTURE_SHARED","content","完整分享"))));
        String document="{mySyncSnapshot{userId bookmarks{verse{id}} notes{clientKey content tags} progress{verse} shares{clientKey verseIds content}}}";
        authenticated(first).document(document).execute().path("mySyncSnapshot.notes[0].clientKey")
                .entity(String.class).isEqualTo(note.get("clientKey").toString());
        authenticated(first).document(document).execute().path("mySyncSnapshot.shares[0].verseIds")
                .entityList(String.class).containsExactly("43003016","43003017");
        authenticated(second).document(document).execute().path("mySyncSnapshot.notes").entityList(Object.class).hasSize(0);
        graphql.document(document).execute().errors().satisfy(errors -> assertThat(errors).isNotEmpty());
        authenticated(first).document("{me{id nickname}}").execute().path("me.id").entity(String.class).isEqualTo(String.valueOf(first));
    }

    @Test void testPulledCloudNoteUpdatesByClientKeyWithoutCreatingAnotherNote() {
        long user=user();
        var note=personal.saveNote(user,null,null,List.of(),null,"旧正文",List.of());
        String key=note.get("clientKey").toString();
        imports.importData(user,List.of(item("NOTE",key,Instant.now().plusSeconds(1),Map.of(
                "content","通过本地缓存编辑","verseRefs",List.of("约3:17")))));
        assertThat(personal.notes(user,null)).hasSize(1);
        assertThat(personal.notes(user,null).getFirst()).containsEntry("content","通过本地缓存编辑");
        assertThat(personal.removeNote(user,note.get("id").toString())).isTrue();
        authenticated(user).document("{mySyncSnapshot{notes{clientKey}}}").execute()
                .path("mySyncSnapshot.notes").entityList(Object.class).hasSize(0);
    }

    @Test void testSnapshotIncludesSharesBeyondTheFeedPageSize() {
        long user=user();
        jdbc.update("""
            INSERT INTO feed_record(user_id,type,client_key,verse_id,verse_ids,content)
            SELECT ?,'SCRIPTURE_SHARED',gen_random_uuid()::text,43003016,ARRAY[43003016,43003017]::bigint[],'分享快照'
            FROM generate_series(1,105)
            """,user);
        jdbc.update("INSERT INTO feed_record(user_id,type,client_key,verse_id,content) VALUES(?,'SCRIPTURE_SHARED','legacy-share',43003016,'旧单节分享')",user);
        authenticated(user).document("{mySyncSnapshot{shares{clientKey verseIds}}}").execute()
                .path("mySyncSnapshot.shares").entityList(Object.class).hasSize(106);
        authenticated(user).document("{mySyncSnapshot{shares{clientKey verseIds}}}").execute()
                .path("mySyncSnapshot.shares").entityList(Map.class).satisfies(shares ->
                        assertThat(shares.stream().filter(s -> "legacy-share".equals(s.get("clientKey")))).singleElement()
                                .satisfies(s -> assertThat(s.get("verseIds")).isEqualTo(List.of("43003016"))));
    }

    @Test void testGraphQlBatchPreservesDataAndRetriesWithoutDuplicateFeed() {
        long user = user();
        List<GuestDataItem> items = List.of(
                item("BOOKMARK", "bookmark", base, Map.of("verseRefs", List.of("约3:16"), "color", "#F2D893", "note", "备注")),
                item("NOTE", "note", base, Map.of("verseRefs", List.of("John 3:16-17"), "content", "完整笔记", "tags", List.of("逗,号", "引\"号"))),
                item("PROGRESS", "progress", base, Map.of("bookCode", "JOHN", "chapter", 3, "verse", 16)),
                item("FEED_RECORD", "share", base, Map.of("verseRefs", List.of("JOHN 3:1-2", "约3:16"), "recordType", "SCRIPTURE_SHARED", "content", "分享快照")));
        List<Map<String, Object>> variables = items.stream().map(i -> mapper.convertValue(
                i, new TypeReference<Map<String, Object>>() { })).toList();
        // Exercise GraphQL default-operation binding as well as Java record binding.
        variables.forEach(v -> v.remove("operation"));
        authenticated(user).document(MUTATION).variable("items", variables).execute()
                .path("importGuestData.imported").entity(Integer.class).isEqualTo(4);
        authenticated(user).document(MUTATION).variable("items", variables).execute()
                .path("importGuestData.imported").entity(Integer.class).isEqualTo(0);
        assertThat(personal.bookmarks(user)).hasSize(1);
        assertThat(personal.notes(user, null).getFirst().get("tags")).isEqualTo(List.of("逗,号", "引\"号"));
        assertThat(count("feed_record", user)).isEqualTo(3);
        assertThat(count("guest_import_receipt", user)).isEqualTo(4);
        assertThat(jdbc.queryForObject("SELECT created_at FROM user_note WHERE user_id=?", OffsetDateTime.class, user).toInstant()).isEqualTo(base);
        authenticated(user).document("{myFeedRecords{items{type verseIds}}}").execute()
                .path("myFeedRecords.items").entityList(Map.class).satisfies(rows ->
                        assertThat(rows.stream().filter(r -> r.get("type").equals("SCRIPTURE_SHARED"))).singleElement()
                                .satisfies(r -> assertThat(r.get("verseIds")).isEqualTo(List.of("43003001", "43003002", "43003016"))));
    }

    @Test void testNaturalKeysLwwNoteEditsAndMonotonicProgress() {
        long user = user();
        imports.importData(user, List.of(
                item("BOOKMARK", "one", base, Map.of("verseRefs", List.of("约3:16"), "color", "#F2D893")),
                item("NOTE", "note", base, Map.of("verseRefs", List.of("约3:16"), "content", "旧正文")),
                item("PROGRESS", "progress", base, Map.of("bookCode", "JOHN", "chapter", 3, "verse", 16))));
        imports.importData(user, List.of(
                item("BOOKMARK", "another-local-id", base.plusSeconds(10), Map.of("verseRefs", List.of("John 3:16"), "note", "更新备注")),
                item("NOTE", "note", base.plusSeconds(10), Map.of("verseRefs", List.of("约3:17"), "content", "新正文", "tags", List.of("新标签"))),
                item("PROGRESS", "progress", base.plusSeconds(10), Map.of("bookCode", "JOHN", "chapter", 3, "verse", 2))));
        imports.importData(user, List.of(
                item("BOOKMARK", "stale", base, Map.of("verseRefs", List.of("约3:16"), "color", "#A9D0DF")),
                item("NOTE", "note", base, Map.of("content", "延迟旧正文")),
                item("PROGRESS", "progress", base.minusSeconds(10), Map.of("bookCode", "JOHN", "chapter", 3, "verse", 20))));
        assertThat(personal.bookmarks(user).getFirst()).containsEntry("note", "更新备注").containsEntry("color", null);
        assertThat(personal.notes(user, null).getFirst()).containsEntry("content", "新正文");
        assertThat(jdbc.queryForList("SELECT verse_id FROM user_note_verse WHERE note_id=(SELECT id FROM user_note WHERE user_id=?)", Long.class, user))
                .containsExactly(43003017L);
        assertThat(personal.progress(user).getFirst().get("verse")).isEqualTo(20);
        assertThat(jdbc.queryForObject("SELECT read_at FROM reading_progress WHERE user_id=?", OffsetDateTime.class, user).toInstant()).isEqualTo(base.plusSeconds(10));
        assertThat(count("user_bookmark", user)).isEqualTo(1);
        assertThat(count("feed_record", user)).isEqualTo(3);
    }

    @Test void testTombstonesRejectOlderUnseenEditsAndReplayButAllowNewerRecreation() {
        long user = user();
        GuestDataItem note = item("NOTE", "note", base, Map.of("content", "旧正文"));
        imports.importData(user, List.of(note));
        imports.importData(user, List.of(item("NOTE", "note", base.plusSeconds(20), Map.of("operation", "DELETE"))));
        assertThat(imports.importData(user, List.of(note)).get("imported")).isEqualTo(0);
        imports.importData(user, List.of(item("NOTE", "note", base.plusSeconds(10), Map.of("content", "未见过的延迟版本"))));
        assertThat(personal.notes(user, null)).isEmpty();
        // Equal-time UPSERT loses to DELETE as well.
        imports.importData(user, List.of(item("NOTE", "note", base.plusSeconds(20), Map.of("content", "同时间版本"))));
        assertThat(personal.notes(user, null)).isEmpty();
        imports.importData(user, List.of(item("NOTE", "note", base.plusSeconds(30), Map.of("content", "用户重新创建"))));
        assertThat(personal.notes(user, null).getFirst().get("content")).isEqualTo("用户重新创建");
        authenticated(user).document("{myFeedRecords{items{type verse{verseRef}}}}").execute()
                .path("myFeedRecords.items[0].verse").valueIsNull();
    }

    @Test void testNormalCloudDeleteAlsoBlocksDelayedGuestRecreation() {
        long user = user();
        imports.importData(user, List.of(
                item("BOOKMARK", "bookmark", base, Map.of("verseRefs", List.of("约3:16"))),
                item("NOTE", "note", base, Map.of("content", "正文"))));
        assertThat(personal.removeBookmark(user, personal.bookmarks(user).getFirst().get("id").toString())).isTrue();
        assertThat(personal.removeNote(user, personal.notes(user, null).getFirst().get("id").toString())).isTrue();
        imports.importData(user, List.of(
                item("BOOKMARK", "late-bookmark", base.plusSeconds(10), Map.of("verseRefs", List.of("约3:16"))),
                item("NOTE", "note", base.plusSeconds(10), Map.of("content", "延迟正文"))));
        assertThat(personal.bookmarks(user)).isEmpty();
        assertThat(personal.notes(user, null)).isEmpty();
    }

    @Test void testValidationRetainsFailedKeysAndEnforcesExpandedReferenceAndByteLimits() {
        long user = user();
        var result = imports.importData(user, List.of(
                item("NOTE", "valid", base, Map.of("content", "100节", "verseRefs", List.of("PS 119:1-100"))),
                item("NOTE", "too-many-verses", base, Map.of("content", "101节", "verseRefs", List.of("PS 119:1-101"))),
                item("NOTE", "invalid-reference", base, Map.of("content", "正文", "verseRefs", List.of("约99:1"))),
                item("NOTE", "too-many-bytes", base, Map.of("content", "中".repeat(17_000))),
                item("NOTE", "bad-time", base, Map.of("content", "正文", "updatedAt", "bad-time")),
                item("BOOKMARK", "bad-color", base, Map.of("verseRefs", List.of("约3:16"), "color", "red")),
                item("FEED_RECORD", "double-feed", base, Map.of("verseRefs", List.of("约3:16"), "recordType", "NOTE_CREATED"))));
        assertThat(result.get("imported")).isEqualTo(1);
        assertThat((List<?>) result.get("failed")).hasSize(6);
        assertThat(count("user_note", user)).isEqualTo(1);
        assertThat(count("guest_import_receipt", user)).isEqualTo(1);
        assertThatThrownBy(() -> imports.importData(user, List.of())).isInstanceOf(IllegalArgumentException.class);
        GuestDataItem valid = item("NOTE", "duplicate", base, Map.of("content", "正文"));
        assertThatThrownBy(() -> imports.importData(user, List.of(valid, valid))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> imports.importData(user, java.util.Collections.nCopies(101, valid))).isInstanceOf(IllegalArgumentException.class);
    }

    @Test void testUserIsolationGuestDenialAndRevisionPayloadBinding() {
        long first = user(), second = user();
        GuestDataItem original = item("NOTE", "shared-key", base, Map.of("content", "用户隔离"));
        imports.importData(first, List.of(original));
        imports.importData(second, List.of(original));
        assertThat(personal.notes(first, null)).hasSize(1);
        assertThat(personal.notes(second, null)).hasSize(1);
        var changed = item("NOTE", "shared-key", base, Map.of("content", "版本不可换正文", "revision", original.revision()));
        assertThat(imports.importData(first, List.of(changed)).get("failed")).isEqualTo(List.of("shared-key"));
        assertThat(personal.notes(first, null).getFirst().get("content")).isEqualTo("用户隔离");
        Map<String, Object> variables = mapper.convertValue(original, new TypeReference<Map<String, Object>>() { });
        graphql.document(MUTATION).variable("items", List.of(variables)).execute().errors()
                .satisfy(errors -> assertThat(errors).isNotEmpty());
        graphql.mutate().header("Authorization", "Bearer " + tokens.issue("guest", "guest", "device", 3600)).build()
                .document(MUTATION).variable("items", List.of(variables)).execute().errors()
                .satisfy(errors -> assertThat(errors).isNotEmpty());
        assertThat(count("guest_import_receipt", first)).isEqualTo(1);
    }

    @Test void testConcurrentIdenticalRequestsCreateOneNoteAndOneFeed() {
        long user = user();
        GuestDataItem note = item("NOTE", "note", base, Map.of("content", "并发重试"));
        var one = CompletableFuture.supplyAsync(() -> imports.importData(user, List.of(note)));
        var two = CompletableFuture.supplyAsync(() -> imports.importData(user, List.of(note)));
        assertThat((int) one.join().get("imported") + (int) two.join().get("imported")).isEqualTo(1);
        assertThat(count("user_note", user)).isEqualTo(1);
        assertThat(count("feed_record", user)).isEqualTo(1);
        assertThat(count("guest_import_receipt", user)).isEqualTo(1);
    }

    @Test void testUnexpectedSqlFailureRollsBackAllItemsAndReceipts() {
        long user = user();
        String function = "test_reject_import_" + user;
        String trigger = function + "_trigger";
        jdbc.execute("CREATE FUNCTION " + function + "() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN "
                + "IF NEW.user_id=" + user + " AND (SELECT COUNT(*) FROM guest_import_receipt WHERE user_id=" + user + ")>=1 "
                + "THEN RAISE EXCEPTION 'injected import failure'; END IF; RETURN NEW; END $$");
        jdbc.execute("CREATE TRIGGER " + trigger + " BEFORE INSERT ON guest_import_receipt FOR EACH ROW EXECUTE FUNCTION " + function + "()");
        try {
            assertThatThrownBy(() -> imports.importData(user, List.of(
                    item("NOTE", "one", base, Map.of("content", "第一条")),
                    item("NOTE", "two", base, Map.of("content", "第二条")))))
                    .isInstanceOf(DataAccessException.class);
            assertThat(count("user_note", user)).isZero();
            assertThat(count("feed_record", user)).isZero();
            assertThat(count("guest_import_state", user)).isZero();
            assertThat(count("guest_import_receipt", user)).isZero();
        } finally {
            jdbc.execute("DROP TRIGGER " + trigger + " ON guest_import_receipt");
            jdbc.execute("DROP FUNCTION " + function + "()");
        }
    }

    @Test void testClockClampIsIdempotentAndOldOfflineEditsStayOlderThanCloudData() {
        long user = user();
        GuestDataItem future = item("NOTE", "future", base, Map.of("content", "未来时钟",
                "createdAt", "2099-01-01T00:00:00Z", "updatedAt", "2099-01-01T00:00:00Z"));
        Instant before = Instant.now().minusSeconds(1);
        imports.importData(user, List.of(future));
        assertThat(jdbc.queryForObject("SELECT created_at FROM user_note WHERE user_id=?", OffsetDateTime.class, user).toInstant())
                .isBetween(before, Instant.now().plusSeconds(1));
        assertThat(imports.importData(user, List.of(future)).get("imported")).isEqualTo(0);
        personal.saveBookmark(user, "43003016", "较新的云端备注", null);
        imports.importData(user, List.of(item("BOOKMARK", "old-offline", base.minusSeconds(86400 * 3),
                Map.of("verseRefs", List.of("约3:16"), "note", "三天前离线备注"))));
        assertThat(personal.bookmarks(user).getFirst().get("note")).isEqualTo("较新的云端备注");
    }
}
