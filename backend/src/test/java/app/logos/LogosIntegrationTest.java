package app.logos;

import app.logos.auth.TokenService;
import app.logos.bible.*;
import app.logos.user.PersonalService;
import java.time.LocalDate;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.autoconfigure.graphql.tester.AutoConfigureHttpGraphQlTester;
import org.springframework.graphql.test.tester.HttpGraphQlTester;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import static org.assertj.core.api.Assertions.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureHttpGraphQlTester
@ActiveProfiles("dev")
class LogosIntegrationTest {
    @Autowired HttpGraphQlTester graphql;
    @Autowired TokenService tokens;
    @Autowired BibleCatalog catalog;
    @Autowired VerseRefNormalizer references;
    @Autowired PersonalService personal;
    @Autowired JdbcTemplate jdbc;
    private HttpGraphQlTester guest() {
        return graphql.mutate().header("Authorization","Bearer "+tokens.issue("integration-device","guest","integration-device",3600)).build();
    }
    private long createUser() {
        String phone="1"+String.format("%010d",Math.floorMod(UUID.randomUUID().getLeastSignificantBits(),10_000_000_000L));
        return jdbc.queryForObject("INSERT INTO app_user(phone,nickname) VALUES(?,'integration-test') RETURNING id",Long.class,phone);
    }
    @Test void testCanonAndChapterNavigation() {
        guest().document("{books{bookCode chapterCount}}").execute().path("books").entityList(Object.class).hasSize(66);
        assertThat(catalog.books().stream().mapToInt(b -> b.chapterCount()).sum()).isEqualTo(1189);
        assertThat(catalog.verseById("19046001").textZh().stripLeading())
                .startsWith("神是我们的避难所").doesNotContain("可拉后裔");
        guest().document("{chapter(bookCode:\"GEN\",chapter:50){nextChapter{bookCode chapter}}}").execute()
                .path("chapter.nextChapter.bookCode").entity(String.class).isEqualTo("EXOD");
        guest().document("{chapter(bookCode:\"PS\",chapter:119){verses{verse}}}").execute().path("chapter.verses").entityList(Object.class).hasSize(176);
    }
    @Test void testReferencesNormalizeAndRejectInvalidRanges() {
        for (String reference : List.of("约3:16","John ３：１６","JHN 3:16","logos://verse/JOHN.3.16")) {
            assertThat(references.resolve(reference).getFirst().id()).as(reference).isEqualTo("43003016");
        }
        assertThat(references.resolve("诗23:1-6")).hasSize(6);
        assertThat(references.resolve("约3:17-16")).isEmpty();
        assertThat(references.resolve("约99:1")).isEmpty();
    }
    @Test void testLiteralSearchAndReferencePriority() {
        guest().document("{search(input:{keyword:\"神爱世人\"}){items{verseRef}}}").execute()
                .path("search.items[0].verseRef").entity(String.class).isEqualTo("JOHN 3:16");
        for (String keyword : List.of("%","_","\\")) {
            guest().document("query($q:String!){search(input:{keyword:$q}){total}}").variable("q",keyword).execute()
                    .path("search.total").entity(Integer.class).isEqualTo(0);
        }
        guest().document("{search(input:{keyword:\"约3:16\"}){total}}").execute().path("search.total").entity(Integer.class).isEqualTo(1);
        guest().document("{search(input:{keyword:\"信心\",type:FUZZY}){total}}").execute().errors().satisfy(errors -> assertThat(errors).isNotEmpty());
    }
    @Test void testGuestCannotWritePersonalData() {
        guest().document("mutation{addNote(content:\"should fail\"){id}}").execute().errors().satisfy(errors -> assertThat(errors).isNotEmpty());
        graphql.document("{books{bookCode}}").execute().errors().satisfy(errors -> assertThat(errors).isNotEmpty());
        graphql.mutate().header("Authorization","Bearer broken").build().document("{books{bookCode}}").execute().errors().satisfy(errors -> assertThat(errors).isNotEmpty());
    }
    @Test void testOwnershipProgressAndAutomaticFeed() {
        long first=createUser(),second=createUser();
        try {
            var note=personal.saveNote(first,null,"试验笔记",List.of("43003016"),null,"不可跨用户读取",List.of("灵修"));
            assertThat(personal.notes(second,null)).isEmpty();
            assertThat(personal.removeNote(second,note.get("id").toString())).isFalse();
            assertThat(personal.notes(first,null)).hasSize(1);
            personal.saveBookmark(first,"43003016",null,"#F2D893");
            personal.saveBookmark(first,"43003016","updated",null);
            assertThat(personal.bookmarks(first)).hasSize(1);
            personal.reportProgress(first,"JOHN",3,16);
            personal.reportProgress(first,"JOHN",3,2);
            assertThat(personal.progress(first).getFirst().get("verse")).isEqualTo(16);
            var page=personal.feed(first,1,null);
            assertThat(page.get("hasNextPage")).isEqualTo(true);
            var next=personal.feed(first,100,page.get("endCursor").toString());
            assertThat((List<?>)next.get("items")).hasSize(2);
        } finally { jdbc.update("DELETE FROM app_user WHERE id IN (?,?)",first,second); }
    }
    @Test void testStableDeviceKeysAndDailyDateWindow() {
        String query="{downloadBible(version:\"b1\"){deviceKey}}";
        String one=guest().document(query).execute().path("downloadBible.deviceKey").entity(String.class).get();
        String two=guest().document(query).execute().path("downloadBible.deviceKey").entity(String.class).get();
        assertThat(two).isEqualTo(one);
        assertThat(Base64.getDecoder().decode(one)).hasSize(32);
        guest().document("{dailyVerse{date verse{verseRef}}}").execute().path("dailyVerse.date").entity(String.class)
                .isEqualTo(LocalDate.now(DailyVerseService.ZONE).toString());
        guest().document("{dailyVerse(date:\"2000-01-01\"){date}}").execute().path("dailyVerse").valueIsNull();
    }
    @Test void testTokenTamperingAndQueryLimits() {
        String token=tokens.issue("subject","guest","integration-device",3600);
        assertThat(tokens.verify("Bearer "+token).kind()).isEqualTo("guest");
        assertThatThrownBy(() -> tokens.verify("Bearer "+token.substring(0,token.length()-5)+"AAAAA")).isInstanceOf(IllegalArgumentException.class);
        guest().document("{books{chapters{book{chapters{verses{textZh}}}}}}").execute().errors().satisfy(errors -> assertThat(errors).isNotEmpty());
    }
}
