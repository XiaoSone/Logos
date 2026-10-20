package app.logos.user;

import app.logos.bible.BibleCatalog;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Isolation;

/** All ownership predicates originate from the verified token, never client arguments. */
@Service
public class PersonalService {
    private final JdbcTemplate jdbc;
    private final BibleCatalog catalog;
    public PersonalService(JdbcTemplate jdbc,BibleCatalog catalog) { this.jdbc=jdbc; this.catalog=catalog; }

    private Map<String,Object> bookmark(ResultSet row,int index) throws SQLException {
        Map<String,Object> result=new LinkedHashMap<>();
        result.put("id",row.getString("id")); result.put("verse",catalog.verseById(row.getString("verse_id")));
        result.put("note",row.getString("note")); result.put("color",row.getString("color"));
        result.put("createdAt",row.getTimestamp("created_at").toInstant().toString());
        result.put("updatedAt",row.getTimestamp("updated_at").toInstant().toString());
        return result;
    }
    public List<Map<String,Object>> bookmarks(long user) {
        return jdbc.query("SELECT id,verse_id,note,color,created_at,updated_at FROM user_bookmark WHERE user_id=? ORDER BY updated_at DESC,id DESC",this::bookmark,user);
    }
    private void verseExists(String id) {
        if (catalog.verseById(id)==null) { throw new IllegalArgumentException("无效经文 ID"); }
    }
    private void lockUser(long user) {
        jdbc.queryForObject("SELECT id FROM app_user WHERE id=? FOR UPDATE",Long.class,user);
    }
    private void recordImportState(long user,String kind,String key,boolean deleted) {
        jdbc.update("""
            INSERT INTO guest_import_state(user_id,kind,entity_key,updated_at,deleted) VALUES(?,?,?,NOW(),?)
            ON CONFLICT(user_id,kind,entity_key) DO UPDATE
            SET updated_at=GREATEST(guest_import_state.updated_at,EXCLUDED.updated_at),deleted=EXCLUDED.deleted
            """,user,kind,key,deleted);
    }
    @Transactional
    public Map<String,Object> saveBookmark(long user,String verseId,String note,String color) {
        lockUser(user);
        verseExists(verseId);
        if (color!=null && !color.matches("#[0-9a-fA-F]{6}")) { throw new IllegalArgumentException("颜色必须为 #RRGGBB"); }
        if (note!=null && note.length()>2000) { throw new IllegalArgumentException("收藏备注过长"); }
        Map<String,Object> result=jdbc.queryForObject("""
            INSERT INTO user_bookmark(user_id,verse_id,note,color) VALUES(?,?,?,?)
            ON CONFLICT(user_id,verse_id) DO UPDATE SET note=EXCLUDED.note,color=EXCLUDED.color,updated_at=NOW()
            RETURNING id,verse_id,note,color,created_at,updated_at
            """,this::bookmark,user,Long.valueOf(verseId),note,color);
        String type=color==null ? "BOOKMARK_ADDED" : "SCRIPTURE_HIGHLIGHT";
        jdbc.update("INSERT INTO feed_record(user_id,type,verse_id,bookmark_id) VALUES(?,?,?,?)",user,type,Long.valueOf(verseId),Long.valueOf(result.get("id").toString()));
        recordImportState(user,"BOOKMARK",verseId,false);
        return result;
    }
    @Transactional
    public boolean removeBookmark(long user,String id) {
        lockUser(user);
        List<String> removed=jdbc.queryForList("DELETE FROM user_bookmark WHERE id=? AND user_id=? RETURNING verse_id::text",String.class,Long.valueOf(id),user);
        if (removed.isEmpty()) { return false; }
        recordImportState(user,"BOOKMARK",removed.getFirst(),true);
        return true;
    }

    private Map<String,Object> note(ResultSet row,int index) throws SQLException {
        String id=row.getString("id");
        Map<String,Object> result=new LinkedHashMap<>();
        result.put("id",id); result.put("title",row.getString("title")); result.put("content",row.getString("content"));
        result.put("clientKey",row.getString("client_key"));
        result.put("chapterRange",row.getString("chapter_range"));
        result.put("tags",Arrays.asList((String[])row.getArray("tags").getArray()));
        result.put("createdAt",row.getTimestamp("created_at").toInstant().toString());
        result.put("updatedAt",row.getTimestamp("updated_at").toInstant().toString());
        result.put("verses",jdbc.queryForList("SELECT verse_id::text FROM user_note_verse WHERE note_id=? ORDER BY verse_id",String.class,Long.valueOf(id))
                .stream().map(catalog::verseById).toList());
        return result;
    }
    public List<Map<String,Object>> notes(long user,String search) {
        String pattern="%"+app.logos.bible.SearchService.escapeLike(search==null ? "" : search)+"%";
        return jdbc.query("""
            SELECT id,client_key,title,content,chapter_range,tags,created_at,updated_at FROM user_note
            WHERE user_id=? AND (content ILIKE ? ESCAPE E'\\\\' OR COALESCE(title,'') ILIKE ? ESCAPE E'\\\\') ORDER BY updated_at DESC,id DESC
            """,this::note,user,pattern,pattern);
    }
    @Transactional
    public Map<String,Object> saveNote(long user,String id,String title,List<String> verseIds,String chapterRange,String content,List<String> tags) {
        lockUser(user);
        if (content==null || content.isBlank() || content.length()>50000 || (title!=null && title.length()>200)) {
            throw new IllegalArgumentException("笔记需要 1–50000 字正文，标题不超过 200 字");
        }
        List<String> refs=verseIds==null ? List.of() : verseIds.stream().distinct().toList();
        if (refs.size()>100) { throw new IllegalArgumentException("一篇笔记最多关联 100 节"); }
        refs.forEach(this::verseExists);
        List<String> safeTags=tags==null ? List.of() : tags;
        if (safeTags.size()>20 || safeTags.stream().anyMatch(t -> t.length()>30)) { throw new IllegalArgumentException("标签过多或过长"); }
        String savedId=id;
        if (savedId==null) {
            savedId=jdbc.queryForObject("INSERT INTO user_note(user_id,client_key,title,chapter_range,content,tags) VALUES(?,?,?,?,?,?::text[]) RETURNING id::text",
                    String.class,user,UUID.randomUUID().toString(),title,chapterRange,content,safeTags.toArray(String[]::new));
        } else if (jdbc.update("UPDATE user_note SET title=?,chapter_range=?,content=?,tags=?::text[],updated_at=NOW() WHERE id=? AND user_id=?",
                title,chapterRange,content,safeTags.toArray(String[]::new),Long.valueOf(savedId),user)!=1) {
            throw new IllegalArgumentException("笔记不存在");
        }
        jdbc.update("DELETE FROM user_note_verse WHERE note_id=?",Long.valueOf(savedId));
        for (String verseId : refs) { jdbc.update("INSERT INTO user_note_verse(note_id,verse_id) VALUES(?,?)",Long.valueOf(savedId),Long.valueOf(verseId)); }
        if (id==null) { jdbc.update("INSERT INTO feed_record(user_id,type,note_id,verse_id) VALUES(?,?,?,?)",user,"NOTE_CREATED",
                Long.valueOf(savedId),refs.isEmpty() ? null : Long.valueOf(refs.getFirst())); }
        String clientKey=jdbc.queryForObject("SELECT client_key FROM user_note WHERE id=? AND user_id=?",String.class,Long.valueOf(savedId),user);
        if (clientKey!=null) { recordImportState(user,"NOTE",clientKey,false); }
        return jdbc.queryForObject("SELECT id,client_key,title,content,chapter_range,tags,created_at,updated_at FROM user_note WHERE id=? AND user_id=?",this::note,Long.valueOf(savedId),user);
    }
    @Transactional
    public boolean removeNote(long user,String id) {
        lockUser(user);
        List<String> removed=jdbc.queryForList("DELETE FROM user_note WHERE id=? AND user_id=? RETURNING client_key",String.class,Long.valueOf(id),user);
        if (removed.isEmpty()) { return false; }
        if (removed.getFirst()!=null) { recordImportState(user,"NOTE",removed.getFirst(),true); }
        return true;
    }
    public List<Map<String,Object>> progress(long user) {
        return jdbc.query("SELECT id,book_id,chapter,verse,read_at FROM reading_progress WHERE user_id=? ORDER BY read_at DESC",(row,index) -> Map.of(
                "id",row.getString("id"),"book",catalog.books().get(row.getInt("book_id")-1),"chapter",row.getInt("chapter"),
                "verse",row.getInt("verse"),"readAt",row.getTimestamp("read_at").toInstant().toString()),user);
    }
    public Map<String,Object> reportProgress(long user,String bookCode,int chapter,int verse) {
        var book=catalog.book(bookCode);
        if (book==null || catalog.verses(catalog.chapter(bookCode,chapter)).stream().noneMatch(v -> v.verse()==verse)) {
            throw new IllegalArgumentException("无效阅读位置");
        }
        jdbc.update("""
            INSERT INTO reading_progress(user_id,book_id,chapter,verse) VALUES(?,?,?,?)
            ON CONFLICT(user_id,book_id,chapter) DO UPDATE SET verse=GREATEST(reading_progress.verse,EXCLUDED.verse),read_at=NOW()
            """,user,Long.valueOf(book.id()),chapter,verse);
        return progress(user).stream().filter(p -> ((Number)p.get("chapter")).intValue()==chapter
                && ((app.logos.bible.BibleModels.Book)p.get("book")).id().equals(book.id())).findFirst().orElseThrow();
    }
    public boolean selectVerse(long user,String verseId) {
        verseExists(verseId);
        jdbc.update("INSERT INTO feed_record(user_id,type,verse_id) VALUES(?,?,?)",user,"VERSE_SELECTED",Long.valueOf(verseId));
        return true;
    }
    public Map<String,Object> feed(long user,int limit,String before) {
        if (limit<1 || limit>100) { throw new IllegalArgumentException("记录分页大小为 1–100"); }
        Instant time=Instant.parse("9999-01-01T00:00:00Z"); long id=Long.MAX_VALUE;
        if (before!=null) {
            String[] parts=new String(Base64.getUrlDecoder().decode(before),java.nio.charset.StandardCharsets.UTF_8).split("\\|");
            if (parts.length!=2) { throw new IllegalArgumentException("无效游标"); }
            time=Instant.parse(parts[0]); id=Long.parseLong(parts[1]);
        }
        List<Map<String,Object>> rows=jdbc.query("""
            SELECT id,client_key,type,verse_id,verse_ids,note_id,bookmark_id,content,created_at FROM feed_record
            WHERE user_id=? AND (created_at,id)<(?,?) ORDER BY created_at DESC,id DESC LIMIT ?
            """,(row,index) -> {
                Map<String,Object> item=new LinkedHashMap<>();
                item.put("id",row.getString("id")); item.put("type",row.getString("type"));
                item.put("clientKey",row.getString("client_key"));
                item.put("verse",catalog.verseById(row.getString("verse_id"))); item.put("content",row.getString("content"));
                Long[] ids=(Long[])row.getArray("verse_ids").getArray();
                item.put("verseIds",ids.length==0 && row.getString("verse_id")!=null
                        ? List.of(row.getString("verse_id")) : Arrays.stream(ids).map(String::valueOf).toList());
                item.put("createdAt",row.getTimestamp("created_at").toInstant().toString());
                if (row.getString("note_id")!=null) { item.put("note",jdbc.queryForObject("SELECT id,client_key,title,content,chapter_range,tags,created_at,updated_at FROM user_note WHERE id=? AND user_id=?",this::note,row.getLong("note_id"),user)); }
                if (row.getString("bookmark_id")!=null) { item.put("bookmark",jdbc.queryForObject("SELECT id,verse_id,note,color,created_at,updated_at FROM user_bookmark WHERE id=? AND user_id=?",this::bookmark,row.getLong("bookmark_id"),user)); }
                return item;
            },user,java.sql.Timestamp.from(time),id,limit+1);
        boolean more=rows.size()>limit;
        List<Map<String,Object>> items=rows.stream().limit(limit).toList();
        Map<String,Object> result=new LinkedHashMap<>();
        result.put("items",items); result.put("hasNextPage",more);
        if (!items.isEmpty()) {
            var last=items.getLast();
            result.put("endCursor",Base64.getUrlEncoder().withoutPadding().encodeToString((last.get("createdAt")+"|"+last.get("id")).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        }
        return result;
    }

    /** One consistent read: a failed pull never requires applying a partial account cache. */
    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Map<String,Object> snapshot(long user) {
        List<Map<String,Object>> shares=jdbc.query("""
            SELECT id,client_key,verse_id,verse_ids,content,created_at FROM feed_record
            WHERE user_id=? AND type='SCRIPTURE_SHARED' ORDER BY created_at DESC,id DESC
            """,(row,index) -> {
                Map<String,Object> share=new LinkedHashMap<>();
                share.put("id",row.getString("id"));
                share.put("clientKey",row.getString("client_key"));
                share.put("type","SCRIPTURE_SHARED");
                share.put("verse",catalog.verseById(row.getString("verse_id")));
                Long[] verseIds=(Long[])row.getArray("verse_ids").getArray();
                share.put("verseIds",verseIds.length==0 && row.getString("verse_id")!=null
                        ? List.of(row.getString("verse_id")) : Arrays.stream(verseIds).map(String::valueOf).toList());
                share.put("content",row.getString("content"));
                share.put("createdAt",row.getTimestamp("created_at").toInstant().toString());
                return share;
            },user);
        return Map.of("userId",String.valueOf(user),"bookmarks",bookmarks(user),
                "notes",notes(user,null),"progress",progress(user),"shares",shares);
    }
}
