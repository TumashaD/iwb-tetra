import vinnova.services;
import ballerina/http;
import ballerina/log;
import vinnova.auth;
import vinnova.db;
import ballerinax/postgresql;

configurable string supabaseUrl = ?;
configurable string supabaseJwtSecret = ?;
configurable int serverPort = ?;
configurable string dbHost = ?;
configurable int dbPort = ?;
configurable string dbUser = ?;
configurable string dbPassword = ?;
configurable string dbName = ?;

listener http:Listener ln = new (serverPort);

public final http:CorsConfig CORS_CONFIG = {
    allowCredentials: true,
    allowHeaders: ["Content-Type", "Authorization"],
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS","PATCH"],
    allowOrigins: ["http://localhost:3000"]
};

public function main() returns error? {
    auth:AuthInterceptor authInterceptor = new(supabaseUrl, supabaseJwtSecret);
    db:DatabaseClient dbClient = new (dbHost, dbPort, dbUser, dbPassword, dbName);
    postgresql:Client db = check dbClient.getClient();

    http:Service competitionService = services:createCompetitionService(db, CORS_CONFIG);
    http:Service userService = services:createUserService(db, CORS_CONFIG, authInterceptor);
    http:Service teamService = services:createTeamService(db, CORS_CONFIG);
    http:Service enrollmentService = services:createEnrollmentService(db, CORS_CONFIG);

    check ln.attach(competitionService, "/competitions");
    check ln.attach(userService, "/users");
    check ln.attach(teamService, "/teams");
    check ln.attach(enrollmentService, "/enrollments");

    check ln.'start();
    log:printInfo("Competition service started on port " + serverPort.toString());
    return;
}