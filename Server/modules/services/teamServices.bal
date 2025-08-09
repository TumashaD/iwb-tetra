import ballerinax/postgresql;
import ballerina/sql;
import ballerina/http;
import ballerina/log;

public type Team record {
    int id;
    string name;
    string created_by;
    int no_participants;
    string? created_at?;
    string? last_modified?;
};


public function createTeamService(postgresql:Client dbClient, http:CorsConfig corsConfig) returns http:Service {
    return @http:ServiceConfig{cors : corsConfig} isolated service object {

    private final postgresql:Client db = dbClient;

    isolated resource function post create(http:RequestContext ctx, @http:Payload json teamData) returns Team|http:InternalServerError|http:BadRequest|error {
        // Extract and validate required fields from JSON
        json|error nameJson = teamData.name;
        json|error createdByJson = teamData.created_by;
        json|error noParticipantsJson = teamData.no_participants;

        if nameJson is error || createdByJson is error || noParticipantsJson is error {
            log:printError("Missing required fields in request payload");
            return http:BAD_REQUEST;
        }

        // Cast JSON values to appropriate types
        string name = nameJson.toString();
        string created_by = createdByJson.toString();
        int|error no_participants = int:fromString(noParticipantsJson.toString());

        if no_participants is error {
            log:printError("Invalid no_participants value - must be a number");
            return http:BAD_REQUEST;
        }

        if name.trim() == "" || created_by.trim() == "" {
            return http:BAD_REQUEST;
        }

        // Insert new Team with the provided auth ID
        sql:ExecutionResult|error result = self.db->execute(`
            INSERT INTO teams (name, created_by, no_participants, created_at, last_modified) 
            VALUES (${name}, ${created_by}::uuid, ${no_participants}, NOW(), NOW())
        `);

        if result is error {
            log:printError("Failed to create team", 'error = result);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Get the generated ID from the insert result
        int|string? generatedId = result.lastInsertId;
        if generatedId is () {
            log:printError("Failed to get generated team ID");
            return http:INTERNAL_SERVER_ERROR;
        }

        // Fetch the newly created team using the generated ID
        sql:ParameterizedQuery selectQuery = `SELECT * FROM teams WHERE id = ${generatedId}`;
        stream<Team, sql:Error?> newTeamResult = self.db->query(selectQuery, Team);
        Team[]|error createdTeamArr = from Team t in newTeamResult
                                      select t;

        if createdTeamArr is error {
            log:printError("Failed to fetch created team", createdTeamArr);
            return http:INTERNAL_SERVER_ERROR;
        }
        if createdTeamArr.length() == 0 {
            log:printError("Created team not found");
            return http:INTERNAL_SERVER_ERROR;
        }

        return createdTeamArr[0];
    }
    };
}