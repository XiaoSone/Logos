package app.logos.api;

import app.logos.auth.TokenService;
import graphql.schema.DataFetchingEnvironment;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.graphql.data.method.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Controller;
import org.springframework.transaction.annotation.Transactional;

@Controller
public class AuthController {
    private static final long GUEST_TTL=30L*86400;
    private final TokenService tokens;
    private final JdbcTemplate jdbc;
    private final boolean dev;
    private final String devCode;
    private final String devInvite;
    public AuthController(TokenService tokens,JdbcTemplate jdbc,@Value("${logos.dev-login}") boolean dev,
                          @Value("${logos.dev-code:}") String devCode,@Value("${logos.dev-invite:}") String devInvite) {
        this.tokens=tokens; this.jdbc=jdbc; this.dev=dev; this.devCode=devCode; this.devInvite=devInvite;
    }
    private void validateDevice(String id) {
        if (!id.matches("[a-zA-Z0-9_-]{8,100}")) { throw new IllegalArgumentException("无效设备 ID"); }
    }
    @QueryMapping public boolean loginAvailable() { return dev; }
    @MutationMapping public Map<String,Object> issueGuestToken(@Argument String deviceId) {
        validateDevice(deviceId);
        return Map.of("token",tokens.issue(deviceId,"guest",deviceId,GUEST_TTL),"expiresIn",GUEST_TTL);
    }
    @QueryMapping public Map<String,Object> me(DataFetchingEnvironment env) {
        var principal=BibleController.credential(env);
        if (!"user".equals(principal.kind())) { return null; }
        return jdbc.queryForObject("SELECT id::text,phone,nickname FROM app_user WHERE id=? AND status=1",(row,index) -> {
            String nickname=row.getString("nickname");
            return Map.of("id",row.getString("id"),"phone",maskPhone(row.getString("phone")),
                    "nickname",nickname==null ? "Logos 读者" : nickname);
        },principal.requireUser());
    }
    private static String maskPhone(String phone) { return phone.substring(0,3)+"****"+phone.substring(7); }
    @MutationMapping
    @Transactional
    public Map<String,Object> verifySmsCode(@Argument String phone,@Argument String code,@Argument String inviteCode,@Argument String deviceId) {
        if (!dev) { throw new IllegalArgumentException("短信通道尚未配置，请使用游客模式"); }
        validateDevice(deviceId);
        if (!phone.matches("1[3-9][0-9]{9}") || !devCode.equals(code) || !devInvite.equals(inviteCode)) {
            throw new IllegalArgumentException("开发验证码或邀请码错误");
        }
        String id=jdbc.queryForObject("""
            INSERT INTO app_user(phone,nickname,last_login_at) VALUES(?,'Logos 读者',NOW())
            ON CONFLICT(phone) DO UPDATE SET last_login_at=NOW() RETURNING id::text
            """,String.class,phone);
        jdbc.update("""
            INSERT INTO user_device(user_id,device_id,device_type,app_version,last_active_at) VALUES(?,?,'development','0.1.0',NOW())
            ON CONFLICT(user_id,device_id) DO UPDATE SET last_active_at=NOW()
            """,Long.valueOf(id),deviceId);
        return Map.of("accessToken",tokens.issue(id,"user",deviceId,3600),"user",Map.of("id",id,"phone",maskPhone(phone),"nickname","Logos 读者"));
    }
}
