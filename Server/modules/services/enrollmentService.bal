import ballerinax/postgresql;
import ballerina/sql;
import ballerina/http;
import ballerina/log;


public type Enrollment record {
    int enrollment_id;
    int competition_id;
    int team_id;
    string status;
    string? created_at?;
};


public function createEnrollmentService(postgresql:Client dbClient, http:CorsConfig corsConfig) returns http:Service {
    return @http:ServiceConfig{cors : corsConfig} isolated service object {

    private final postgresql:Client db = dbClient;

    isolated resource function post create(http:RequestContext ctx, @http:Payload json enrollmentData) returns Enrollment|http:InternalServerError|http:BadRequest|error {
        
        // Extract and validate required fields from JSON
        json|error competitionIdJson = enrollmentData.competitionid;
        json|error teamIdJson = enrollmentData.teamid;
        json|error statusJson = enrollmentData.status;

        if competitionIdJson is error || teamIdJson is error || statusJson is error {
            log:printError("Missing required fields in request payload");
            return http:BAD_REQUEST;
        }

        // Cast JSON values to appropriate types
        int|error competitionid = int:fromString(competitionIdJson.toString());
        int|error teamid = int:fromString(teamIdJson.toString());
        string status = statusJson.toString();

        if competitionid is error || teamid is error {
            log:printError("Invalid competitionid or teamid value - must be a number");
            return http:BAD_REQUEST;
        }

        if status.trim() == "" {
            return http:BAD_REQUEST;
        }

        // Insert new Enrollment
        sql:ExecutionResult|error result = self.db->execute(`
            INSERT INTO enrollments (competition_id, team_id, status, created_at) 
            VALUES (${competitionid}, ${teamid}, ${status}, NOW())
        `);

        if result is error {
            log:printError("Failed to create enrollment", 'error = result);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Get the generated ID from the insert result
        int|string? generatedId = result.lastInsertId;
        if generatedId is () {
            log:printError("Failed to get generated team ID");
            return http:INTERNAL_SERVER_ERROR;
        }

        // Fetch the newly created enrollment using the generated ID
        sql:ParameterizedQuery selectQuery = `SELECT * FROM enrollments WHERE enrollment_id = ${generatedId}`;
        stream<Enrollment, sql:Error?> newEnrollmentResult = self.db->query(selectQuery, Enrollment);
        Enrollment[]|error createdEnrollmentArr = from Enrollment e in newEnrollmentResult
                                      select e;

        if createdEnrollmentArr is error {
            log:printError("Failed to fetch created enrollment", createdEnrollmentArr);
            return http:INTERNAL_SERVER_ERROR;
        }
        if createdEnrollmentArr.length() == 0 {
            log:printError("Created enrollment not found");
            return http:INTERNAL_SERVER_ERROR;
        }

        return createdEnrollmentArr[0];
    }
    };
}