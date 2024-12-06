# AWS Redshift Data API Ballerina Connector
- Authors
  - Chathushka Ayash
- Reviewed by
    - ayeshLK
    - ThisaruGuruge
- Created date
    - 2024-12-04
- Issue
    - [7446](https://github.com/ballerina-platform/ballerina-library/issues/7446)
- State
    - Submitted

## Summary

This project develops a Ballerina connector for AWS Redshift Data API. The connector will simplify SQL query execution and database operations in Redshift, leveraging Ballerina's integration capabilities.


## Goals

- **Ease of Use:** Intuitive interface for database operations.
- **Flexibility:** Support parameterized queries, custom types, and streams.
- **Security:** Authentication using AWS credentials.


## Motivation

AWS SDKs and REST APIs are complex. This connector reduces overhead and simplifies integration with Redshift databases, targeting increased developer productivity.


## Description

### Client API Design

#### Client Definition

````ballerina

public type Client distinct client object {

    # Executes the SQL query. 
    #
    # + sqlQuery - The SQL query such as `DELETE FROM User WHERE city=${cityName}`
    # + databaseConfig - The database configurations such as the clusterId, databaseName, and databaseUser
    # + return - The metadata of the execution or the results of the query or an error
    remote function execute(sql:ParameterizedQuery sqlQuery, DatabaseConfig databaseConfig,
            typedesc<record {}> rowType = <>)
        returns stream<rowType, sql:Error?>|sql:ExecutionResult|sql:Error;

    # Executes multiple SQL queries.
    #
    # + sqlQueries - The SQL queries such as `DELETE FROM User WHERE city=${cityName}`
    # + databaseConfig - The database configurations such as the clusterId, databaseName, and databaseUser
    # + return - The metadata of the execution 
    remote isolated function batchExecute(sql:ParameterizedQuery[] sqlQueries, DatabaseConfig databaseConfig,
            typedesc<record {}[]> rowTypes = <>)
        returns (stream<rowTypes, sql:Error?>|sql:ExecutionResult)[]|sql:Error;

    # Closes the client.
    #
    # + return - Possible error when closing the client
    remote isolated function close() returns error?;
};

````

#### ConnectionConfig
```ballerina

# Represents the Client configurations for AWS Redshift Data API.
# + region - The AWS region with which the connector should communicate
# + auth - The authentication configurations for the redshift data api
# + clientOptions - Additional configurations related to http client
public type ConnectionConfig record {|
    Region region;
    AuthConfig auth;
    HttpClientOptions clientOptions?;
|};

````

#### Region
```ballerina

# An Amazon Web Services region that hosts a set of Amazon services.
public enum Region {
    AF_SOUTH_1 = "af-south-1",
    AP_EAST_1 = "ap-east-1",
    AP_NORTHEAST_1 = "ap-northeast-1",
    AP_NORTHEAST_2 = "ap-northeast-2",
    AP_NORTHEAST_3 = "ap-northeast-3",
    AP_SOUTH_1 = "ap-south-1",
    AP_SOUTH_2 = "ap-south-2",
    AP_SOUTHEAST_1 = "ap-southeast-1",
    AP_SOUTHEAST_2 = "ap-southeast-2",
    AP_SOUTHEAST_3 = "ap-southeast-3",
    AP_SOUTHEAST_4 = "ap-southeast-4",
    AWS_CN_GLOBAL = "aws-cn-global",
    AWS_GLOBAL = "aws-global",
    AWS_ISO_GLOBAL = "aws-iso-global",
    AWS_ISO_B_GLOBAL = "aws-iso-b-global",
    AWS_US_GOV_GLOBAL = "aws-us-gov-global",
    CA_WEST_1 = "ca-west-1",
    CA_CENTRAL_1 = "ca-central-1",
    CN_NORTH_1 = "cn-north-1",
    CN_NORTHWEST_1 = "cn-northwest-1",
    EU_CENTRAL_1 = "eu-central-1",
    EU_CENTRAL_2 = "eu-central-2",
    EU_ISOE_WEST_1 = "eu-isoe-west-1",
    EU_NORTH_1 = "eu-north-1",
    EU_SOUTH_1 = "eu-south-1",
    EU_SOUTH_2 = "eu-south-2",
    EU_WEST_1 = "eu-west-1",
    EU_WEST_2 = "eu-west-2",
    EU_WEST_3 = "eu-west-3",
    IL_CENTRAL_1 = "il-central-1",
    ME_CENTRAL_1 = "me-central-1",
    ME_SOUTH_1 = "me-south-1",
    SA_EAST_1 = "sa-east-1",
    US_EAST_1 = "us-east-1",
    US_EAST_2 = "us-east-2",
    US_GOV_EAST_1 = "us-gov-east-1",
    US_GOV_WEST_1 = "us-gov-west-1",
    US_ISOB_EAST_1 = "us-isob-east-1",
    US_ISO_EAST_1 = "us-iso-east-1",
    US_ISO_WEST_1 = "us-iso-west-1",
    US_WEST_1 = "us-west-1",
    US_WEST_2 = "us-west-2"
}

````

#### AuthConfig
```ballerina


# Auth configurations for the AWS Redshift Data API
# + awsAccessKeyId - The AWS access key ID
# + awsSecretAccessKey - The AWS secret access key
# + sessionToken - The session token if the credentials are temporary
public type AuthConfig record {|
    string awsAccessKeyId;
    string awsSecretAccessKey;
    string sessionToken?;
|};

````

#### HttpClientOptions
```ballerina

# Http client configurations
# + maxConcurrency - The maximum number of concurrent requests that can be made to the database
# + connectionTimeout - The maximum time to wait for a connection to be established in `seconds`
# + readTimeout - The maximum time to wait for a read operation to complete in `seconds`
# + writeTimeout - The maximum time to wait for a write operation to complete in `seconds`
public type HttpClientOptions record {|
    int maxConcurrency = 50;
    int connectionTimeout = 2;
    int readTimeout = 30;
    int writeTimeout = 30;
|};

````

#### DatabaseConfig
```ballerina

# Database configurations
# + clusterId - The cluster identifier
# + databaseName - The name of the database
# + databaseUser - The database user
public type DatabaseConfig record {|
    string clusterId;
    string databaseName;
    string databaseUser;
|};
````

#### Sample Usage
```ballerina
import ballerinax/redshiftdata;


redshiftdata:AuthConfig authConfig = {
    awsAccessKeyId: "<AWS_ACCESS_KEY_ID>",
    awsSecretAccessKey: "<AWS_SECRET_ACCESS_KEY>"
};


redshiftdata:ConnectionConfig connectionConfig = {
    region: US_EAST_2,
    auth: authConfig
};


redshiftdata:DatabaseConfig databaseConfig = {
    clusterId: "<CLUSTER_ID>",
    databaseName: "<DATABASE_NAME>",
    databaseUser: "<DATABASE_USER>"
};


type User record {|
    string name;
    string email;
    string city;
|};


public function main() returns error? {
    Client redshift = check new (connectionConfig);
    sql:ParameterizedQuery query = `SELECT * FROM User`;
    stream<User, error?> result = check redshift->execute(query, databaseConfig);


    check result.forEach(function(User user) {
        io:println(user);
    });


}
````

### Dependencies

- AWS Redshift Data API

