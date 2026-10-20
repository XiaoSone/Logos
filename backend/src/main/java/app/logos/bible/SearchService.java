package app.logos.bible;

import app.logos.bible.BibleModels.*;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class SearchService {
    private final BibleMapper mapper;
    private final BibleCatalog catalog;
    private final VerseRefNormalizer references;
    public SearchService(BibleMapper mapper, BibleCatalog catalog, VerseRefNormalizer references) {
        this.mapper = mapper; this.catalog = catalog; this.references = references;
    }

    public SearchResult search(SearchInput input) {
        String keyword = input.keyword().strip();
        if (keyword.isEmpty() || keyword.length() > 100) { throw new IllegalArgumentException("请输入 1–100 字关键词"); }
        if ("FUZZY".equals(input.type())) { throw new IllegalArgumentException("语义搜索将在 Phase 2 开启"); }
        int page = input.page() == null ? 1 : input.page();
        int size = input.size() == null ? 20 : input.size();
        if (page < 1 || page > 10000 || size < 1 || size > 100) { throw new IllegalArgumentException("无效分页参数"); }
        List<Verse> reference = references.resolve(keyword);
        int offset = (page - 1) * size;
        if (!reference.isEmpty()) {
            return new SearchResult(reference.size(), page, size, reference.stream().skip(offset).limit(size).toList());
        }
        String pattern = "%" + escapeLike(keyword) + "%";
        return new SearchResult(mapper.count(pattern), page, size,
                mapper.search(pattern, size, offset).stream().map(catalog::verseById).toList());
    }

    public static String escapeLike(String text) {
        return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
    }
}
