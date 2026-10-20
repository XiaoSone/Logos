package app.logos.api;

import app.logos.user.PersonalService;
import app.logos.user.GuestDataItem;
import app.logos.user.GuestImportService;
import graphql.schema.DataFetchingEnvironment;
import java.util.List;
import java.util.Map;
import org.springframework.graphql.data.method.annotation.*;
import org.springframework.stereotype.Controller;

@Controller
public class PersonalController {
    private final PersonalService service;
    private final GuestImportService imports;
    public PersonalController(PersonalService service, GuestImportService imports) {
        this.service=service;
        this.imports=imports;
    }
    private long user(DataFetchingEnvironment env) { return BibleController.credential(env).requireUser(); }
    @QueryMapping public List<Map<String,Object>> myBookmarks(DataFetchingEnvironment env) { return service.bookmarks(user(env)); }
    @QueryMapping public List<Map<String,Object>> myNotes(@Argument String search,DataFetchingEnvironment env) { return service.notes(user(env),search); }
    @QueryMapping public List<Map<String,Object>> myProgress(DataFetchingEnvironment env) { return service.progress(user(env)); }
    @QueryMapping public Map<String,Object> mySyncSnapshot(DataFetchingEnvironment env) { return service.snapshot(user(env)); }
    @QueryMapping public Map<String,Object> myFeedRecords(@Argument int limit,@Argument String before,DataFetchingEnvironment env) { return service.feed(user(env),limit,before); }
    @MutationMapping public Map<String,Object> addBookmark(@Argument String verseId,@Argument String note,@Argument String color,DataFetchingEnvironment env) { return service.saveBookmark(user(env),verseId,note,color); }
    @MutationMapping public boolean removeBookmark(@Argument String id,DataFetchingEnvironment env) { return service.removeBookmark(user(env),id); }
    @MutationMapping public Map<String,Object> addNote(@Argument String title,@Argument List<String> verseIds,@Argument String chapterRange,@Argument String content,@Argument List<String> tags,DataFetchingEnvironment env) {
        return service.saveNote(user(env),null,title,verseIds,chapterRange,content,tags);
    }
    @MutationMapping public Map<String,Object> updateNote(@Argument String id,@Argument String title,@Argument List<String> verseIds,@Argument String chapterRange,@Argument String content,@Argument List<String> tags,DataFetchingEnvironment env) {
        return service.saveNote(user(env),id,title,verseIds,chapterRange,content,tags);
    }
    @MutationMapping public boolean removeNote(@Argument String id,DataFetchingEnvironment env) { return service.removeNote(user(env),id); }
    @MutationMapping public Map<String,Object> reportProgress(@Argument String bookCode,@Argument int chapter,@Argument int verse,DataFetchingEnvironment env) { return service.reportProgress(user(env),bookCode,chapter,verse); }
    @MutationMapping public boolean reportVerseSelected(@Argument String verseId,DataFetchingEnvironment env) { return service.selectVerse(user(env),verseId); }
    @MutationMapping public Map<String,Object> importGuestData(@Argument List<GuestDataItem> items,DataFetchingEnvironment env) {
        return imports.importData(user(env),items);
    }
}
