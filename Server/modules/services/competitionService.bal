import ballerinax/postgresql;
import ballerina/sql;
import ballerina/http;
import ballerina/log;
import ballerina/time;

public type Competition record {
    int id;
    string title;
    string description;
    string organizer_id;
    string start_date;
    string end_date;
    string category;
    string status;
    string created_at;
    string updated_at;
};

public function createCompetitionService(postgresql:Client dbClient, http:CorsConfig corsConfig) returns http:Service {
    return @http:ServiceConfig{cors : corsConfig} isolated service object {

        private final postgresql:Client db = dbClient;

    isolated resource function get .(http:RequestContext ctx) returns json|http:InternalServerError|error {
            sql:ParameterizedQuery query = `SELECT * FROM competitions`;
            stream<Competition, sql:Error?> competitionsResult = self.db->query(query, Competition);
        Competition[]|error competitions = from Competition competition in competitionsResult
                                              select competition;
        if competitions is error {
            log:printError("Failed to process competitions", competitions);
            return http:INTERNAL_SERVER_ERROR;
        }
        return {
            "competitions": competitions,
            "timestamp": time:utcNow()
        }.toJson();
    }

    isolated resource function post create(http:RequestContext ctx, @http:Payload json competitionData) returns json|http:InternalServerError|http:BadRequest|error {
        
        // Extract and validate required fields from JSON
        json|error titleJson = competitionData.title;
        json|error descriptionJson = competitionData.description;
        json|error organizerIdJson = competitionData.organizer_id;
        json|error startDateJson = competitionData.start_date;
        json|error endDateJson = competitionData.end_date;
        json|error categoryJson = competitionData.category;
        json|error statusJson = competitionData.status;

        if titleJson is error || organizerIdJson is error ||  startDateJson is error || endDateJson is error || categoryJson is error || statusJson is error {
            log:printError("Missing required fields in request payload");
            return http:BAD_REQUEST;
        }

        // Cast JSON values to appropriate types
        string title = titleJson.toString();
        string description = descriptionJson is error ? "" : descriptionJson.toString();
        string organizer_id = organizerIdJson.toString();
        string start_date = startDateJson.toString();
        string end_date = endDateJson.toString();
        string category = categoryJson.toString();
        string status = statusJson.toString();

        // Validate required fields
        if title.trim() == "" || organizer_id.trim() == "" || start_date.trim() == "" || 
           end_date.trim() == "" || category.trim() == "" {
            return http:BAD_REQUEST;
        }
        
        // Insert new competition
        sql:ExecutionResult|error result = self.db->execute(`
            INSERT INTO competitions (title, description, organizer_id, start_date, end_date, category, status, created_at, updated_at) 
            VALUES (${title}, ${description}, ${organizer_id}::uuid, 
                    ${start_date}::date, ${end_date}::date, ${category}, 
                    ${status}, NOW(), NOW())
        `);
        
        if result is error {
            log:printError("Failed to create competition", result);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        // Get the ID of the newly created competition
        int|string? lastInsertId = result.lastInsertId;
        if lastInsertId is () {
            log:printError("Failed to get last insert ID");
            return http:INTERNAL_SERVER_ERROR;
        }
        
        int competitionId;
        if lastInsertId is int {
            competitionId = lastInsertId;
        } else {
            // Try to parse string to int
            int|error parsedId = int:fromString(lastInsertId.toString());
            if parsedId is error {
                log:printError("Failed to parse last insert ID", parsedId);
                return http:INTERNAL_SERVER_ERROR;
            }
            competitionId = parsedId;
        }
        
        // Fetch the newly created competition
        sql:ParameterizedQuery selectQuery = `SELECT * FROM competitions WHERE id = ${competitionId}`;
        stream<Competition, sql:Error?> newCompetitionResult = self.db->query(selectQuery, Competition);
        Competition[]|error newCompetition = from Competition competition in newCompetitionResult
                                               select competition;
        
        if newCompetition is error {
            log:printError("Failed to fetch created competition", newCompetition);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        if newCompetition.length() == 0 {
            log:printError("Created competition not found");
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return {
            "competition": newCompetition[0],
            "message": "Competition created successfully",
            "timestamp": time:utcNow()
        }.toJson();
    }

    isolated resource function patch [int id](http:RequestContext ctx, @http:Payload json updateData) returns json|http:InternalServerError|http:NotFound|http:BadRequest|error {

        // fetch the existing competition
        sql:ParameterizedQuery selectQuery = `SELECT * FROM competitions WHERE id = ${id}`;
        stream<Competition, sql:Error?> competitionResult = self.db->query(selectQuery, Competition);
        Competition[]|error competitionArr = from Competition c in competitionResult select c;
        
        if competitionArr is error {
            log:printError("Failed to fetch existing competition", competitionArr);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        if competitionArr.length() == 0 {
            return http:NOT_FOUND;
        }
        
        Competition existingCompetition = competitionArr[0];

        // Extract fields from JSON, using existing values as defaults
        json|error titleJson = updateData.title;
        json|error descriptionJson = updateData.description;
        json|error startDateJson = updateData.start_date;
        json|error endDateJson = updateData.end_date;
        json|error categoryJson = updateData.category;
        json|error statusJson = updateData.status;

        string title = titleJson !is error ? titleJson.toString() : existingCompetition.title;
        string description = descriptionJson !is error ? descriptionJson.toString() : existingCompetition.description;
        string start_date = startDateJson !is error ? startDateJson.toString() : existingCompetition.start_date;
        string end_date = endDateJson !is error ? endDateJson.toString() : existingCompetition.end_date;
        string category = categoryJson !is error ? categoryJson.toString() : existingCompetition.category;
        string status = statusJson !is error ? statusJson.toString() : existingCompetition.status;

        // Check if at least one field is provided for update (optional)
        if titleJson is error && descriptionJson is error && 
           startDateJson is error && endDateJson is error && 
           categoryJson is error && statusJson is error {
            log:printError("No valid fields provided for update");
            return http:BAD_REQUEST;
        }

        // Update competition with single query 
        sql:ExecutionResult|error result = self.db->execute(`
            UPDATE competitions 
            SET title = ${title}, description = ${description}, start_date = ${start_date}::date, 
                end_date = ${end_date}::date, category = ${category}, status = ${status}, updated_at = NOW()
            WHERE id = ${id}
        `);

        log:printInfo("Updating competition with ID: " + id.toString(), 
            title = title, 
            description = description, 
            start_date = start_date,
            end_date = end_date,
            category = category,
            status = status);

        if result is error {
            log:printError("Failed to update competition", result);
            return http:INTERNAL_SERVER_ERROR;
        }

        if result.affectedRowCount == 0 {
            return http:NOT_FOUND;
        }

        // Fetch and return the updated competition
        sql:ParameterizedQuery updatedQuery = `SELECT * FROM competitions WHERE id = ${id}`;
        stream<Competition, sql:Error?> updatedResult = self.db->query(updatedQuery, Competition);
        Competition[]|error updatedArr = from Competition c in updatedResult select c;

        if updatedArr is error {
            log:printError("Failed to fetch updated competition", updatedArr);
            return http:INTERNAL_SERVER_ERROR;
        }

        return {
            "competition": updatedArr[0],
            "message": "Competition updated successfully",
            "timestamp": time:utcNow()
        }.toJson();
    }    
    
    isolated resource function delete [int id](http:RequestContext ctx) returns json|http:InternalServerError|http:NotFound|error {
        // Check if the competition exists
        sql:ParameterizedQuery checkQuery = `SELECT id FROM competitions WHERE id = ${id}`;
        stream<record {int id;}, sql:Error?> checkResult = self.db->query(checkQuery);
        record {int id;}[]|error existingCompetition = from record {int id;} comp in checkResult select comp;
        
        if existingCompetition is error {
            log:printError("Error checking competition existence", existingCompetition);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        if existingCompetition.length() == 0 {
            return http:NOT_FOUND;
        }
        
        // Delete the competition
        sql:ExecutionResult|error result = self.db->execute(`DELETE FROM competitions WHERE id = ${id}`);
        
        if result is error {
            log:printError("Failed to delete competition", result);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        if result.affectedRowCount == 0 {
            return http:NOT_FOUND;
        }
        
        return {
            "message": "Competition deleted successfully",
            "timestamp": time:utcNow()
        }.toJson();
    }

};
}