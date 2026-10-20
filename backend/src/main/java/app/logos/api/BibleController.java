package app.logos.api;

import app.logos.auth.KeyService;
import app.logos.auth.TokenService.Principal;
import app.logos.bible.*;
import app.logos.bible.BibleModels.*;
import graphql.schema.DataFetchingEnvironment;
import java.util.List;
import java.util.Map;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SchemaMapping;
import org.springframework.stereotype.Controller;

@Controller
public class BibleController {
    private final BibleCatalog catalog;
    private final VerseRefNormalizer references;
    private final SearchService search;
    private final DailyVerseService daily;
    private final KeyService keys;
    public BibleController(BibleCatalog catalog,VerseRefNormalizer references,SearchService search,
                           DailyVerseService daily,KeyService keys) {
        this.catalog=catalog; this.references=references; this.search=search; this.daily=daily; this.keys=keys;
    }
    public static Principal credential(DataFetchingEnvironment env) {
        String authError=env.getGraphQlContext().get("authError");
        if (authError!=null) { throw new IllegalArgumentException(authError); }
        Principal value=env.getGraphQlContext().get("principal");
        if (value==null) { throw new IllegalArgumentException("请获取游客凭证后访问"); }
        return value;
    }
    @QueryMapping public List<Book> books(DataFetchingEnvironment env) { credential(env); return catalog.books(); }
    @QueryMapping public Book book(@Argument String bookCode,DataFetchingEnvironment env) { credential(env); return catalog.book(bookCode); }
    @QueryMapping public Chapter chapter(@Argument String bookCode,@Argument int chapter,DataFetchingEnvironment env) {
        credential(env); return catalog.chapter(bookCode,chapter);
    }
    @QueryMapping public Verse verse(@Argument String ref,DataFetchingEnvironment env) {
        credential(env); return references.resolve(ref).stream().findFirst().orElse(null);
    }
    @QueryMapping public List<Verse> verses(@Argument List<String> refs,DataFetchingEnvironment env) {
        credential(env);
        if (refs.size()>100) { throw new IllegalArgumentException("一次最多 100 个引用"); }
        return refs.stream().flatMap(ref -> references.resolve(ref).stream()).distinct().toList();
    }
    @QueryMapping public List<Section> sections(@Argument String bookCode,@Argument int chapter,DataFetchingEnvironment env) {
        credential(env); return catalog.sections(bookCode,chapter);
    }
    @QueryMapping public Section section(@Argument String bookCode,@Argument int chapter,@Argument int sectionIndex,DataFetchingEnvironment env) {
        credential(env); return catalog.sections(bookCode,chapter).stream().filter(s -> s.sectionIndex()==sectionIndex).findFirst().orElse(null);
    }
    @QueryMapping public SearchResult search(@Argument SearchInput input,DataFetchingEnvironment env) { credential(env); return search.search(input); }
    @QueryMapping public DailyVerse dailyVerse(@Argument String date,DataFetchingEnvironment env) { credential(env); return daily.daily(date); }
    @QueryMapping public Map<String,Object> getBibleKey(@Argument String version,DataFetchingEnvironment env) { credential(env); return keys.master(version); }
    @QueryMapping public Map<String,Object> downloadBible(@Argument String version,DataFetchingEnvironment env) { return keys.device(credential(env),version); }
    @SchemaMapping public Book book(Chapter chapter) { return catalog.book(chapter.bookCode()); }
    @SchemaMapping public List<Chapter> chapters(Book book) {
        return java.util.stream.IntStream.rangeClosed(1,book.chapterCount()).mapToObj(c -> catalog.chapter(book.bookCode(),c)).toList();
    }
    @SchemaMapping public List<Verse> verses(Chapter chapter,@Argument Integer limit,@Argument Integer offset) {
        if ((limit!=null && (limit<0 || limit>176)) || (offset!=null && offset<0)) { throw new IllegalArgumentException("无效章节分页"); }
        return catalog.verses(chapter).stream().skip(offset==null ? 0 : offset).limit(limit==null ? 176 : limit).toList();
    }
    @SchemaMapping public List<Section> sections(Chapter chapter) { return catalog.sections(chapter.bookCode(),chapter.chapter()); }
    @SchemaMapping public Chapter nextChapter(Chapter chapter) { return catalog.adjacent(chapter,1); }
    @SchemaMapping public Chapter prevChapter(Chapter chapter) { return catalog.adjacent(chapter,-1); }
    @SchemaMapping public Section section(Verse verse) { return catalog.sectionById(verse.sectionId()); }
    @SchemaMapping public List<Verse> verses(Section section) {
        return catalog.verses(catalog.chapter(section.bookCode(),section.chapter())).stream()
                .filter(v -> v.verse()>=section.verseStart() && v.verse()<=section.verseEnd()).toList();
    }
    @SchemaMapping public Section prevSection(Section section) { return adjacentSection(section,-1); }
    @SchemaMapping public Section nextSection(Section section) { return adjacentSection(section,1); }
    private Section adjacentSection(Section section,int delta) {
        return catalog.sections(section.bookCode(),section.chapter()).stream()
                .filter(s -> s.sectionIndex()==section.sectionIndex()+delta).findFirst().orElse(null);
    }
}
