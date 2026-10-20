package app.logos.bible;

import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface BibleMapper {
    @Select("SELECT id::text FROM bible_verse WHERE text_zh ILIKE #{pattern} ESCAPE E'\\\\' ORDER BY id LIMIT #{limit} OFFSET #{offset}")
    List<String> search(@Param("pattern") String pattern, @Param("limit") int limit, @Param("offset") int offset);

    @Select("SELECT count(*) FROM bible_verse WHERE text_zh ILIKE #{pattern} ESCAPE E'\\\\'")
    int count(@Param("pattern") String pattern);
}
