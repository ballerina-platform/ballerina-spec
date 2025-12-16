# Multi-Model Support for Ballerina Persist

- Authors - @TharmiganK
- Reviewed by - @daneshk
- Created date - 2025-12-16
- Updated date - 2025-12-16
- Issue - [#1411](https://github.com/ballerina-platform/ballerina-spec/issues/1411)
- State - Submitted

## Summary

This proposal introduces support for multiple independent data models within a single Ballerina persist project. Currently, the persist tool supports only a single model file (`model.bal`) in the `persist/` directory. This enhancement enables developers to define multiple models, each potentially connecting to different data stores, allowing better organization and separation of concerns in applications that interact with multiple databases or data sources.

## Motivation

Modern applications frequently interact with multiple data sources—relational databases, NoSQL stores, caching layers, and third-party APIs. Currently, Ballerina persist restricts developers to a single model file, forcing them to either:

- Create separate Ballerina packages for each data source
- Use alternative data access approaches for additional data stores

This limitation hinders developer productivity and creates maintenance challenges. Supporting multiple models enables:

- **Better organization**: Separate models for distinct domains (e.g., user management, inventory, analytics)
- **Multi-database support**: Connect different models to different data stores in the same application
- **Improved modularity**: Independent lifecycle management for each model
- **Enhanced maintainability**: Clearer separation of concerns and easier code navigation

## Goals

- Enable multiple `.bal` files in the `persist/` directory, with each file representing an independent data model
- Allow each model to connect to different data store types or instances
- Extend persist CLI commands to support model-specific operations
- Ensure compiler plugin engagement for all model files
- Maintain backward compatibility with existing single-model projects

## Non-Goals

- Organizing models in subdirectories within the `persist/` directory
- Enforcing naming conventions for model files
- Processing multiple models simultaneously in a single command invocation

## Design

### Model File Structure

- Any `.bal` file located at the root level of the `persist/` directory is considered a valid model file
- No specific naming convention is enforced — developers can name model files according to their domain (e.g., `users.bal`, `inventory.bal`, `analytics.bal`)
- Each model file contains a complete, independent data model with its entity definitions
- Model files cannot reference entities defined in other model files

### Default Behavior

- When a model name is not specified in persist commands, the default model file is `model.bal`
- Projects with only `model.bal` continue to work without any changes
- For projects with multiple model files, commands require explicit model specification

### CLI Command Extensions

All persist commands are extended to support optional model specification:

**`bal persist init`**

- New optional argument: `--model <model-name>`
- Behavior: Initializes persist configuration and creates the specified model file
- Default: Creates `model.bal` if no model name is provided

**`bal persist generate`**

- New optional argument: `--model <model-name>` or `--model <file-path>`
- Behavior: Generates client code for the specified model
- Error handling: If multiple models exist and no model is specified, display an error message requesting model specification
- Default: Uses `model.bal` if it's the only model file present

**`bal persist add`**

- Existing support through `Ballerina.toml` configuration (inherited from default build tool options)
- New optional argument: `--model <model-name>` or `--model <file-path>`
- Behavior: Adds entities to the specified model file

**`bal persist pull`**

- New optional argument: `--model <model-name>`
- Behavior: Pulls schema from the database and generates the specified model file
- Default: Creates or updates `model.bal` if no model name is provided

### Data Store Configuration

- Each model can be configured to connect to a different data store type or instance
- Configuration is specified per model in the `Ballerina.toml` file or through environment-specific settings
- Supported scenarios include:
  - Model A → MySQL database
  - Model B → PostgreSQL database
  - Model C → Redis cache
  - Model D → Google Sheets

### Code Generation

- Generated client code maintains the generic name `Client` for each model
- Developers can specify different target modules for generated code from different models
- Each model's generated code is isolated and independent
- If no module is specified, generated code follows existing default behavior

### Compiler Plugin Behavior

- The compiler plugin engages for all `.bal` files in the `persist/` directory
- Each model file is processed independently
- Validation is performed per model without cross-model checks
- Duplicate entity names across different models are permitted

### Entity Independence

- Entities in different model files are completely independent
- No cross-model relationships or foreign key references are supported
- Each model maintains its own namespace for entity definitions
- It is acceptable and valid to have identically named entities in different models

## Alternatives

### Alternative 1: Enforce Naming Convention

Require model files to follow a specific pattern (e.g., `model-*.bal`). This was rejected because it adds unnecessary constraints and reduces flexibility for developers to organize their models according to domain-specific conventions.

### Alternative 2: Support Subdirectories

Allow organizing models in subdirectories under `persist/`. This was rejected to maintain simplicity and avoid complexity in model discovery and path resolution.

### Alternative 3: Process All Models by Default

When no model is specified, process all models in the directory. This was rejected because it could lead to unintended side effects, longer execution times, and confusion about which models are being affected by a command.

### Alternative 4: Support Cross-Model Relationships

Allow entities in different models to reference each other. This was rejected due to significant complexity in dependency management, transaction handling, and potential circular dependencies. It would also blur the separation of concerns that multi-model support aims to provide.

### Impact of Not Implementing

Without this feature, developers will continue to face limitations when working with multiple data sources, leading to workarounds such as:

- Creating multiple separate Ballerina packages
- Using non-persist mechanisms for additional data sources
- Reduced code quality and maintainability

## Testing

### Test Scenarios

1. **Single Model Backward Compatibility**
   - Existing projects with `model.bal` should work without any changes
   - All persist commands should function as before when only `model.bal` exists

2. **Multiple Model Creation**
   - Create multiple model files with `bal persist init --model <name>`
   - Verify each model file is created correctly

3. **Model-Specific Generation**
   - Generate clients for specific models using `bal persist generate --model <name>`
   - Verify correct client code is generated for each model
   - Verify error message when multiple models exist but none is specified

4. **Multi-Database Connection**
   - Create models connecting to different database types
   - Verify each model connects to its configured data store
   - Test CRUD operations on entities from different models

5. **Duplicate Entity Names**
   - Create identical entity definitions in different model files
   - Verify no conflicts occur
   - Verify independent operation of each model

6. **Compiler Plugin Integration**
   - Verify compiler plugin processes all model files
   - Verify build-time validation for each model
   - Test error reporting for invalid model definitions

7. **Command Error Handling**
   - Verify appropriate error messages when model specification is missing in multi-model projects
   - Test invalid model name/path scenarios

### Test Environments

- Unit tests for CLI command parsing and validation
- Integration tests for multi-model project workflows
- End-to-end tests with multiple database types (MySQL, PostgreSQL, Redis, etc.)
- Compiler plugin tests for multiple model processing
- Backward compatibility tests with existing single-model projects

## Risks and Assumptions

### Risks

- **Increased Complexity**: Introducing multiple models increases the complexity of the persist tool and may lead to a steeper learning curve for new users
- **Documentation Overhead**: Comprehensive documentation will be needed to guide developers on best practices for organizing multiple models

### Assumptions

- Developers understand the independence of models and the absence of cross-model relationships
- Each model will typically represent a distinct domain or data source
- The majority of use cases involve connecting to different data stores rather than organizing a single data store into multiple models
- Generated client code being named `Client` for all models is acceptable, with module separation providing sufficient organization

## Dependencies

- Ballerina compiler plugin API for multi-file processing
- Persist CLI infrastructure for command argument parsing
- Ballerina.toml configuration schema for per-model data store settings
- Code generation templates that support model-specific output paths
