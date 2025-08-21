# Sensitive Data Exclusion in Ballerina Logging

- Authors
  - Tharmigan Krishnananthalingam
- Reviewed by
  - Danesh Kuruppu, Thisaru Guruge
- Created date
  - 2025-08-06
- Updated date
  - 2025-08-06
- Issue
  - [1376](https://github.com/ballerina-platform/ballerina-spec/issues/1376)
- State
  - Submitted

## Summary

This proposal introduces a mechanism to exclude sensitive data from being serialized in log output within the `ballerina/log` package. This enhancement addresses security concerns by preventing accidental exposure of sensitive information such as passwords, API keys, tokens, and other confidential data in application logs.

## Motivation

The current `ballerina/log` package serializes all key values when logging, which can inadvertently expose sensitive information in log files. This poses significant security risks, especially in production environments where logs are often stored, transmitted, and accessed by multiple systems and personnel.

Key problems with the current behavior:

- **Security Risk**: Sensitive data like passwords, API keys, and tokens are logged in plain text
- **Compliance Issues**: GDPR, PCI-DSS, and other regulations require protection of sensitive data
- **Operational Risk**: Log aggregation systems may expose sensitive data to unauthorized personnel

## Goals

- Provide a mechanism to mark types and fields as sensitive and exclude them from log output
- Maintain backward compatibility with existing logging functionality
- Enable flexible masking strategies (complete removal, string replacement, or function-based custom replacement)

## Non-Goals

- Supporting field exclusion in non-logging serialization scenarios

## Design

This proposal introduces an annotation-based approach for sensitive data exclusion in logging. The design supports both record field-level and type-level annotations, providing comprehensive coverage for sensitive data protection.

### Annotation-Based Sensitive Data Exclusion

#### Core Annotation

```ballerina
# Exclude the field from log output
public const EXCLUDE = "EXCLUDE";

# Replacement function type for sensitive data masking
public type ReplacementFunction isolated function (string input) returns string;

# Replacement strategy for sensitive data
# 
# + replacement - The replacement value. This can be a string which will be used to replace the
# entire value, or a function that takes the original value and returns a masked version.
public type Replacement record {|
    string|ReplacementFunction replacement;
|};

# Masking strategy for sensitive data
public type MaskingStrategy EXCLUDE|Replacement;

# Represents sensitive data with a masking strategy
#
# + strategy - The masking strategy to apply (default: EXCLUDE)
public type SensitiveDataConfig record {|
    MaskingStrategy strategy = EXCLUDE;
|};

# Marks a record field or type as sensitive, excluding it from log output
#
# + strategy - The masking strategy to apply (default: EXCLUDE)
public const annotation SensitiveDataConfig SensitiveData on record field, type;
```

> **Note**: The `SensitiveData` annotation can be applied to both record fields and types. Field level annotations take precedence over type-level annotations, allowing for granular control over sensitive data exclusion.

#### Sensitive Data Exclusion Strategies

1. **EXCLUDE**: Completely removes the sensitive data from the log output. This is the default behaviour.
2. **REPLACE**: Replacement can be a string or a function:
   - If a string is provided, it replaces the entire sensitive data with that string.
   - If a function is provided, the original value is passed to the function, and the returned value is used in the masked value.

#### Usage Examples

```ballerina
@log:SensitiveData {
    strategy: {
        replacement: "***********"
    }
}
public type ApiKey string;

@log:SensitiveData
public type Password string;

isolated function maskEmail(string email) returns string {
    int? atIndex = email.indexOf("@");
    if atIndex is int {
        return email.substring(0, 1) + "****" + email.substring(atIndex);
    }
    return email;
}

type UserCredentials record {
    string username;
    Password password;
    ApiKey apiKey;
    @log:SensitiveData {
        strategy: {
            replacement: maskEmail
        }
    }
    string email;
};

public function main() {
    Password userPassword = "mySecretPassword123";
    ApiKey key = "sk_live_abc123xyz789";
    UserCredentials user = {
        username: "john_doe",
        password: "secret123",
        apiKey: "sk_live_abc123xyz",
        email: "john@example.com"
    };

    log:printInfo("User login attempt", password = userPassword, apiKey = key);
    // Output: time=2025-08-06T10:30:00.000Z level=INFO message="User login attempt" apiKey="[REDACTED]"

    log:printInfo("User authentication", user = user);
    // Output: time=2025-08-06T10:30:00.000Z level=INFO message="User authentication"
    //         user = {"username": "john_doe", "apiKey": "[REDACTED]", "email": "j****@gmail.com"}
}
```

#### Configuration to Enable/Disable Sensitive Data Exclusion

By default, sensitive data exclusion is enabled. However, users can configure the logging package to disable this feature if needed. The `ballerina/log` package provide a global configuration option to control sensitive data exclusion behavior.

```toml
[ballerina.log]
sensitiveDataExclusion = false
```

#### Error Handling with Masking Functions

When using masking functions, it's important to handle potential errors gracefully. The `ballerina/log` package provides built-in error handling mechanisms to ensure that masking functions do not disrupt the logging process by panicking errors. Internal logging framework will trap those panics and log them as errors.

## Alternative

### Programmatic Field Exclusion

Building on the contextual logging proposal[1], this approach would provide runtime flexibility through custom masking functions:

```ballerina
public type MaskingFunction function(KeyValues fields) returns KeyValues;

public type LoggerConfig record {
    LogFormat format = "logfmt";
    LogLevel level = "INFO";
    string[] destinations = ["stderr"];
    KeyValues keyValues = {};
    MaskingFunction? masker;
};
```

This would allow users to define custom masking logic at runtime making it more flexible, but it adds complexity and may not be as intuitive as the annotation-based approach.

#### Root logger masking function

Root level logger can have a default masking function which is based on regular expressions. These regular expressions can be configured at runtime, and each log line is checked for all the configured patterns. If any match is found, it is masked with the configured replacement.

Definition:
```ballerina
# Masking sensitive data configuration
public type MaskingPattern record {|
    # Pattern to match the sensitive data
    string pattern;
    # Replacement value
    string replacement = "****";
|};

# Masking patterns to be applied with the root logger
configurable MaskingPattern[] maskingPatterns = [];
```
Sample Configuration:
```toml
[[maskingPatterns]]
pattern = "4[0-9]{6,}$"

[[maskingPatterns]]
pattern = "\"SSN\"\\s*:\\s*\"(.*)\""
replacement = ""
```

> **Note:** Root logger mask function is a simple replacement and if the user wants to have a custom masking function they should use a custom logger or create a logger from the root logger using `fromConfig` method as proposed in the contextual logging proposal[1].

### Reasons to Choose Annotation-Based Approach

- **Simplicity**: Annotations provide a clear and declarative way to mark sensitive data, making it easy to understand and maintain
- **Consistency**: The annotation-based approach aligns with existing Ballerina practices, making it easier for developers to adopt

## Risks and Assumptions

- **Performance Impact**: Annotation processing may introduce some overhead during compilation, but this is generally outweighed by the benefits of having a clear and maintainable codebase
- **Functional Limitations**: The masking functions must be pure and not cause side effects, as they will be called during logging. This is a reasonable assumption for most use cases
- **Developer Errors**: The masking functions must handle errors gracefully to avoid panics during logging. This is mitigated by the built-in error handling in the `ballerina/log` package

## References

1. [Contextual Logging Proposal](https://github.com/ballerina-platform/ballerina-spec/blob/master/beps/lib-log/1322_contextual_logging.md)
