package app.logos.bible;

import app.logos.bible.BibleModels.*;
import java.text.Normalizer;
import java.util.List;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

@Component
public class VerseRefNormalizer {
    private static final Pattern REFERENCE = Pattern.compile("^(.+?)\\s*(\\d{1,3})\\s*[:：]\\s*(\\d{1,3})(?:\\s*[-–—]\\s*(\\d{1,3}))?$");
    private final BibleCatalog catalog;
    public VerseRefNormalizer(BibleCatalog catalog) { this.catalog = catalog; }

    public List<Verse> resolve(String raw) {
        if (raw == null || raw.length() > 100) { return List.of(); }
        String normalized = Normalizer.normalize(raw.strip(), Normalizer.Form.NFKC);
        if (normalized.startsWith("logos://verse/")) {
            String[] parts = normalized.substring(14).split("\\.");
            if (parts.length != 3) { return List.of(); }
            normalized = parts[0] + " " + parts[1] + ":" + parts[2];
        }
        var match = REFERENCE.matcher(normalized);
        if (!match.matches()) { return List.of(); }
        Book book = catalog.book(match.group(1));
        if (book == null) { return List.of(); }
        int chapter = Integer.parseInt(match.group(2));
        int start = Integer.parseInt(match.group(3));
        int end = match.group(4) == null ? start : Integer.parseInt(match.group(4));
        if (start < 1 || end < start || end > 176) { return List.of(); }
        List<Verse> result = catalog.verses(catalog.chapter(book.bookCode(), chapter)).stream()
                .filter(v -> v.verse() >= start && v.verse() <= end).toList();
        return result.size() == end - start + 1 ? result : List.of();
    }
}
