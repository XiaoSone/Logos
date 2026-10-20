package app.logos.bible;

import app.logos.bible.BibleModels.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.Path;
import java.util.*;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Immutable content catalog; personal data is stored separately in PostgreSQL. */
@Component
public class BibleCatalog {
    private final CatalogData data;
    private final Map<String, Book> aliases;
    private final Map<String, Verse> byId;
    private final Map<String, List<Verse>> chapters;
    private final Map<String, Section> sections;

    public BibleCatalog(ObjectMapper mapper, @Value("${logos.bible-path}") String path) throws IOException {
        data = mapper.readValue(Path.of(path).toFile(), CatalogData.class);
        aliases = new HashMap<>(200);
        for (Book book : data.books()) {
            for (String alias : book.aliases()) {
                aliases.put(normalizeAlias(alias), book);
            }
        }
        byId = data.verses().stream().collect(Collectors.toUnmodifiableMap(Verse::id, Function.identity()));
        chapters = data.verses().stream().collect(Collectors.groupingBy(v -> v.bookCode() + "." + v.chapter()));
        sections = data.sections().stream().collect(Collectors.toUnmodifiableMap(Section::id, Function.identity()));
    }

    private static String normalizeAlias(String value) {
        return value.replaceAll("[\\s　]", "").toUpperCase(Locale.ROOT);
    }

    public Book book(String alias) { return alias == null ? null : aliases.get(normalizeAlias(alias)); }
    public List<Book> books() { return data.books(); }
    public CatalogData data() { return data; }
    public Verse verseById(String id) { return id == null ? null : byId.get(id); }
    public Section sectionById(String id) { return sections.get(id); }

    public Chapter chapter(String alias, int number) {
        Book book = book(alias);
        return book == null || number < 1 || number > book.chapterCount() ? null
                : new Chapter(book.bookCode() + "." + number, book.bookCode(), number);
    }

    public List<Verse> verses(Chapter chapter) {
        return chapter == null ? List.of() : chapters.getOrDefault(chapter.id(), List.of());
    }

    public List<Section> sections(String alias, int chapter) {
        Book book = book(alias);
        return book == null ? List.of() : data.sections().stream()
                .filter(s -> s.bookCode().equals(book.bookCode()) && s.chapter() == chapter).toList();
    }

    public Chapter adjacent(Chapter current, int delta) {
        Book book = book(current.bookCode());
        int next = current.chapter() + delta;
        if (next >= 1 && next <= book.chapterCount()) { return chapter(book.bookCode(), next); }
        int index = book.bookOrder() - 1 + delta;
        if (index < 0 || index >= data.books().size()) { return null; }
        Book adjacent = data.books().get(index);
        return chapter(adjacent.bookCode(), delta > 0 ? 1 : adjacent.chapterCount());
    }
}
