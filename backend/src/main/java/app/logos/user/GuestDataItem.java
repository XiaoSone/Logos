package app.logos.user;

import java.util.List;

/** Client identity is local to a verified user; it never selects an account. */
public record GuestDataItem(
        String clientKey, String revision, String type, String operation,
        List<String> verseRefs, String title, String content, String chapterRange,
        String color, String note, String bookCode, Integer chapter, Integer verse,
        String recordType, List<String> tags, String createdAt, String updatedAt) {
}
