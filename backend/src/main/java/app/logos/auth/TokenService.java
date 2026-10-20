package app.logos.auth;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class TokenService {
    private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder DECODER = Base64.getUrlDecoder();
    private static final String HEADER = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";
    private final byte[] secret;
    private final ObjectMapper mapper;
    public record Principal(String subject, String kind, String deviceId) {
        public long requireUser() {
            if (!"user".equals(kind)) { throw new IllegalArgumentException("请先登录"); }
            return Long.parseLong(subject);
        }
    }

    public TokenService(ObjectMapper mapper, @Value("${logos.jwt-secret}") String secret) {
        if (secret.length() < 32) { throw new IllegalStateException("JWT_SECRET must contain at least 32 characters"); }
        this.secret = secret.getBytes(StandardCharsets.UTF_8); this.mapper = mapper;
    }

    public String issue(String subject, String kind, String deviceId, long seconds) {
        try {
            String payload = ENCODER.encodeToString(mapper.writeValueAsBytes(Map.of("sub",subject,"kind",kind,
                "deviceId",deviceId,"iss","logos","exp",Instant.now().getEpochSecond()+seconds)));
            String input=HEADER+"."+payload;
            return input+"."+ENCODER.encodeToString(sign(input));
        } catch (java.io.IOException exception) { throw new IllegalStateException("Cannot encode token",exception); }
    }

    private byte[] sign(String input) {
        try {
            Mac mac=Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret,"HmacSHA256"));
            return mac.doFinal(input.getBytes(StandardCharsets.US_ASCII));
        } catch (GeneralSecurityException exception) { throw new IllegalStateException("HMAC unavailable",exception); }
    }

    public Principal verify(String authorization) {
        try {
            if (authorization==null || !authorization.startsWith("Bearer ") || authorization.length()>4096) {
                throw new IllegalArgumentException("需要有效凭证");
            }
            String[] parts=authorization.substring(7).split("\\.");
            if (parts.length!=3 || !HEADER.equals(parts[0]) || !MessageDigest.isEqual(sign(parts[0]+"."+parts[1]),DECODER.decode(parts[2]))) {
                throw new IllegalArgumentException("凭证校验失败");
            }
            Map<String,Object> payload=mapper.readValue(DECODER.decode(parts[1]),new TypeReference<>() { });
            if (!"logos".equals(payload.get("iss")) || ((Number)payload.get("exp")).longValue()<=Instant.now().getEpochSecond()) {
                throw new IllegalArgumentException("凭证已过期");
            }
            return new Principal((String)payload.get("sub"),(String)payload.get("kind"),(String)payload.get("deviceId"));
        } catch (java.io.IOException | ClassCastException | NullPointerException exception) {
            throw new IllegalArgumentException("凭证格式错误");
        }
    }
}
