package app.logos.config;

import app.logos.auth.TokenService;
import graphql.GraphQLError;
import graphql.GraphqlErrorBuilder;
import graphql.analysis.MaxQueryComplexityInstrumentation;
import graphql.analysis.MaxQueryDepthInstrumentation;
import graphql.execution.instrumentation.ChainedInstrumentation;
import graphql.schema.DataFetchingEnvironment;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.graphql.execution.DataFetcherExceptionResolverAdapter;
import org.springframework.graphql.execution.ErrorType;
import org.springframework.graphql.server.WebGraphQlInterceptor;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class GraphQlConfiguration {
    @Bean
    WebGraphQlInterceptor identityInterceptor(TokenService tokens) {
        return (request,chain) -> {
            request.configureExecutionInput((input,builder) -> {
                String auth=request.getHeaders().getFirst("Authorization");
                if (auth!=null) {
                    try { var principal=tokens.verify(auth); builder.graphQLContext(context -> context.put("principal",principal)); }
                    catch (IllegalArgumentException exception) { builder.graphQLContext(context -> context.put("authError",exception.getMessage())); }
                }
                return builder.build();
            });
            return chain.next(request);
        };
    }

    @Bean
    ChainedInstrumentation queryLimits() {
        return new ChainedInstrumentation(List.of(new MaxQueryDepthInstrumentation(8),new MaxQueryComplexityInstrumentation(10000,(environment,childComplexity) -> {
            int multiplier=switch (environment.getField().getName()) {
                case "books" -> 66;
                case "chapters" -> 150;
                case "verses" -> 176;
                case "items" -> 100;
                default -> 1;
            };
            return (int)Math.min(Integer.MAX_VALUE,1L+(long)multiplier*childComplexity);
        })));
    }

    @Bean
    DataFetcherExceptionResolverAdapter errors() {
        return new DataFetcherExceptionResolverAdapter() {
            @Override
            protected GraphQLError resolveToSingleError(Throwable exception, DataFetchingEnvironment environment) {
                if (exception instanceof IllegalArgumentException) {
                    return GraphqlErrorBuilder.newError(environment).errorType(ErrorType.BAD_REQUEST).message(exception.getMessage()).build();
                }
                return null;
            }
        };
    }

    @Bean
    WebMvcConfigurer cors(@Value("${logos.allowed-origins}") String origins) {
        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry registry) {
                registry.addMapping("/graphql").allowedOrigins(origins.split(",")).allowedMethods("POST","OPTIONS").allowedHeaders("Content-Type","Authorization");
            }
        };
    }
}
