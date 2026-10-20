package app.logos.bible;

import app.logos.bible.BibleModels.*;
import java.time.LocalDate;
import java.time.ZoneId;
import org.springframework.stereotype.Service;

@Service
public class DailyVerseService {
    public static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final String[] SEEDS = {"JOHN 3:16","PS 23:1","PROV 3:5","PHIL 4:6","ROM 8:28",
        "MATT 6:33","ISA 40:31","PS 119:105","JOHN 15:5","JAS 1:5","PHIL 4:13","PS 46:1",
        "MATT 11:28","ROM 12:2","HEB 11:1","1COR 13:4","PS 1:2","JOHN 14:27","EPH 2:8",
        "JOSH 1:9","PS 121:2","GAL 5:22","1PET 5:7","PS 34:8","ROM 15:13","MATT 5:9",
        "PS 19:14","1JOHN 4:19","HEB 13:8","ISA 41:10","REV 21:4"};
    private final VerseRefNormalizer references;
    public DailyVerseService(VerseRefNormalizer references) { this.references=references; }

    public DailyVerse daily(String rawDate) {
        LocalDate today=LocalDate.now(ZONE);
        LocalDate date=rawDate==null ? today : LocalDate.parse(rawDate);
        if (date.isBefore(today.minusDays(7)) || date.isAfter(today.plusDays(7))) { return null; }
        int ordinal = LocalDate.of(2000,date.getMonthValue(),date.getDayOfMonth()).getDayOfYear()-1;
        Verse verse=references.resolve(SEEDS[ordinal % SEEDS.length]).getFirst();
        return new DailyVerse(date.toString(),date.toString(),verse,"在话语中安静", "慢慢读这段经文，留意今天触动你的一个词。");
    }
}
