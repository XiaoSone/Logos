package app.logos.bible;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.util.List;

public final class BibleModels {
    private BibleModels() { }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Book(String id, String bookCode, String bookNameZh, String bookNameEn,
                       String bookNameAbbr, int testament, int bookOrder, int chapterCount,
                       List<String> aliases) { }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Verse(String id, String bookCode, int chapter, int verse, String textZh,
                        String verseRef, String sectionId, List<Footnote> footnotes,
                        int bridgeStart, String verseLabel) { }

    public record Footnote(String id, String content, int offsetStart, int offsetEnd) { }

    public record Section(String id, String bookCode, int chapter, int sectionIndex,
                          String sectionTitle, int verseStart, int verseEnd,
                          int verseCount, boolean isPoetry) { }

    public record CatalogData(String version, List<Book> books, List<Verse> verses,
                              List<Section> sections) { }

    public record Chapter(String id, String bookCode, int chapter) { }
    public record SearchInput(String keyword, String type, Integer page, Integer size) { }
    public record SearchResult(int total, int page, int size, List<Verse> items) { }
    public record DailyVerse(String id, String date, Verse verse, String theme, String meditation) { }
}
