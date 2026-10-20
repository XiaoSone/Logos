package app.logos.bible;

import app.logos.bible.BibleModels.*;
import java.util.ArrayList;
import java.util.List;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class CatalogImporter implements ApplicationRunner {
    private final BibleCatalog catalog;
    private final JdbcTemplate jdbc;
    public CatalogImporter(BibleCatalog catalog, JdbcTemplate jdbc) { this.catalog = catalog; this.jdbc = jdbc; }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        jdbc.batchUpdate("""
            INSERT INTO bible_book(id,book_code,book_name_zh,book_name_en,book_name_abbr,testament,book_order,chapter_count)
            VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET book_name_zh=EXCLUDED.book_name_zh, chapter_count=EXCLUDED.chapter_count
            """, catalog.books().stream().map(b -> new Object[]{Long.valueOf(b.id()), b.bookCode(), b.bookNameZh(),
                b.bookNameEn(), b.bookNameAbbr(), b.testament(), b.bookOrder(), b.chapterCount()}).toList());
        jdbc.batchUpdate("""
            INSERT INTO bible_verse(id,book_id,book_code,chapter,verse,text_zh) VALUES(?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET text_zh=EXCLUDED.text_zh
            """, catalog.data().verses().stream().map(v -> new Object[]{Long.valueOf(v.id()),
                Long.valueOf(catalog.book(v.bookCode()).id()), v.bookCode(), v.chapter(), v.verse(), v.textZh()}).toList());
        jdbc.batchUpdate("""
            INSERT INTO verse_section(id,book_code,chapter,section_index,section_title,verse_start,verse_end,verse_count,is_poetry)
            VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET section_title=EXCLUDED.section_title,
            verse_start=EXCLUDED.verse_start,verse_end=EXCLUDED.verse_end,verse_count=EXCLUDED.verse_count,is_poetry=EXCLUDED.is_poetry
            """, catalog.data().sections().stream().map(s -> new Object[]{s.id(),s.bookCode(),s.chapter(),s.sectionIndex(),
                s.sectionTitle(),s.verseStart(),s.verseEnd(),s.verseCount(),s.isPoetry()}).toList());
        List<Object[]> notes = new ArrayList<>(1100);
        for (Book book : catalog.books()) {
            long start=book.bookOrder()*1_000_000L;
            jdbc.update("DELETE FROM verse_footnote WHERE verse_id>? AND verse_id<?",start,start+1_000_000);
        }
        for (Verse verse : catalog.data().verses()) {
            int index = 0;
            for (Footnote note : verse.footnotes()) {
                notes.add(new Object[]{verse.id()+".f"+index++,Long.valueOf(verse.id()),note.offsetStart(),note.offsetEnd(),note.content()});
            }
        }
        jdbc.batchUpdate("INSERT INTO verse_footnote(id,verse_id,offset_start,offset_end,content) VALUES(?,?,?,?,?)",notes);
    }
}
