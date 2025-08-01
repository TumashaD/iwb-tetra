import ballerina/http;
import ballerina/jwt;
import ballerina/log;

public final AuthInterceptor AUTH_INTERCEPTOR = new;
public final http:CorsConfig CORS_CONFIG = {
    allowCredentials: true,
    allowHeaders: ["Content-Type", "Authorization"],
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowOrigins: ["http://localhost:3000"]
};

// Authentication interceptor
public isolated service class AuthInterceptor {
    *http:RequestInterceptor;

    private string supabaseUrl;
    private string supabaseJwtSecret;

    public isolated function init() {
        self.supabaseUrl = "";
        self.supabaseJwtSecret = "";
    }

    public isolated function configure(string supabaseUrl, string supabaseJwtSecret) {
        lock {
            self.supabaseUrl = supabaseUrl;
            self.supabaseJwtSecret = supabaseJwtSecret;
        }
    }

    isolated resource function 'default [string... path](http:RequestContext ctx, http:Request req) 
            returns http:NextService|http:Unauthorized|http:InternalServerError|error? {
        log:printInfo("AuthInterceptor: Request Intercepted",
        method = req.method.toString(),
        path = path);
        // Skip authentication for health endpoint
        if path.length() > 0 && path[0] == "health" {
            return ctx.next();
        }

        // Skip authentication for CORS preflight OPTIONS requests
        if req.method == "OPTIONS" {
            return ctx.next();
        }

        string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
        
        if authHeader is http:HeaderNotFoundError {
            log:printError("Authorization header not found");
            return http:UNAUTHORIZED;
        }

        if !authHeader.startsWith("Bearer ") {
            log:printError("Invalid authorization header format");
            return http:UNAUTHORIZED;
        }

        string token = authHeader.substring(7);

        jwt:ValidatorConfig validatorConfig;
        lock {
            validatorConfig = {
                issuer: self.supabaseUrl,
                audience: "authenticated",
                clockSkew: 60,
                signatureConfig: {
                    secret: self.supabaseJwtSecret
                }
            };
        }

        jwt:Payload|jwt:Error jwtPayload = jwt:validate(token, validatorConfig);

        if jwtPayload is jwt:Error {
            log:printError("JWT validation failed", jwtPayload);
            return http:UNAUTHORIZED;
        }

        // Store user info in context for use in endpoints
        ctx.set("user", jwtPayload);
        return ctx.next();
    }
}

