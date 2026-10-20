package app.logos.auth;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class KeyService {
    private final String key;
    private final JdbcTemplate jdbc;
    private final SecureRandom random=new SecureRandom();
    public KeyService(JdbcTemplate jdbc,@Value("${logos.bible-key-file}") String path) throws IOException {
        this.jdbc=jdbc; key=Files.readString(Path.of(path)).strip();
        if (Base64.getDecoder().decode(key).length!=32) { throw new IllegalStateException("Bible key must be 256 bits"); }
    }
    private void validateVersion(String version) {
        if (!"b1".equals(version)) { throw new IllegalArgumentException("不支持的经文数据版本"); }
    }
    public Map<String,Object> master(String version) {
        validateVersion(version);
        return Map.of("key",key,"version",version,"expiresIn",3600);
    }
    public Map<String,Object> device(TokenService.Principal principal,String version) {
        validateVersion(version);
        byte[] bytes=new byte[32]; random.nextBytes(bytes);
        byte[] stored=jdbc.queryForObject("""
            INSERT INTO bible_device_key(device_id,bible_version,device_key) VALUES(?,?,?)
            ON CONFLICT(device_id,bible_version) DO UPDATE SET last_used_at=NOW() RETURNING device_key
            """, byte[].class,principal.deviceId(),version,bytes);
        return Map.of("deviceKey",Base64.getEncoder().encodeToString(stored),"version",version,"expiresIn",0);
    }
}
