# Multi-Model Support for Ballerina Persist

- Authors - @TharmiganK
- Reviewed by - @daneshk
- Created date - 2025-12-16
- Updated date - 2026-01-06
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

- Enable multiple independent data models within a single Ballerina persist project
- Support subdirectory-based organization for better model separation and domain boundaries
- Allow each model to connect to different data store types or instances
- Extend persist CLI commands to support model-specific operations
- Ensure compiler plugin engagement for all model files
- Maintain full backward compatibility with existing single-model projects

## Non-Goals

- Cross-model relationships or foreign key references between models
- Enforcing specific naming conventions for model files (beyond reserved names)
- Processing multiple models simultaneously in a single command invocation
- Supporting models in arbitrary nested subdirectory structures

## Design

### Model File Structure

The persist tool supports a hybrid approach for organizing multiple models:

#### Root Level Model (Backward Compatibility)

- `persist/model.bal` - The default model file for backward compatibility
- Only one `.bal` file is allowed at the root level of the `persist/` directory
- Used when no model name is specified in commands

#### Subdirectory Models (New Multi-Model Support)

- `persist/{modelName}/model.bal` - Model files organized in subdirectories
- Each subdirectory represents a distinct domain or data model
- Model name corresponds to the subdirectory name (e.g., `users`, `inventory`, `analytics`)
- Each model file contains a complete, independent data model with its entity definitions
- Model files cannot reference entities defined in other model files
- Model name cannot be `migrations` (reserved for backward compatibility)

### Default Behavior

- When a model name is not specified in persist commands, the system looks for the default model file `persist/model.bal`
- If `persist/model.bal` does not exist and no model is specified, commands will return an error
- Projects with only `persist/model.bal` continue to work without any changes
- For projects using subdirectory models, commands require explicit model specification via `--model` argument

### Directory Structure Examples

#### Backward Compatible (Root Model Only)

```tree
project/
├── persist/
│   ├── model.bal
│   └── migrations/
│       └── 20250203120000_initial/
│           ├── model.bal
│           └── script.sql
├── generated/
└── Ballerina.toml
```

#### Multi-Model with Subdirectories

```tree
project/
├── persist/
│   ├── model.bal              # Optional: default model
│   ├── migrations/             # Migrations for default model
│   │   └── 20250203120000_initial/
│   ├── users/
│   │   ├── model.bal
│   │   └── migrations/
│   │       └── 20250203120000_initial/
│   │           ├── model.bal
│   │           └── script.sql
│   └── inventory/
│       ├── model.bal
│       └── migrations/
│           └── 20250203120000_initial/
│               ├── model.bal
│               └── script.sql
├── generated/
│   ├── users/
│   └── inventory/
└── Ballerina.toml
```

### CLI Command Extensions

All persist commands are extended to support optional model specification:

**`bal persist init`**

- New optional argument: `--model <model-name>`
- Behavior without `--model`: Creates `persist/model.bal` (backward compatible)
- Behavior with `--model`: Creates `persist/{model-name}/model.bal` and associated directory structure
- Model name validation: Cannot be `migrations`

**`bal persist generate`**

- New optional argument: `--model <model-name>`
- Behavior without `--model`: Uses `persist/model.bal` if it exists, otherwise returns an error
- Behavior with `--model`: Generates client code for `persist/{model-name}/model.bal`
- Error handling: Returns error if specified model directory/file does not exist

**`bal persist add`**

- Existing support through `Ballerina.toml` configuration (inherited from default build tool options)
- New optional argument: `--model <model-name>`
- Behavior without `--model`: Adds entities to `persist/model.bal`
- Behavior with `--model`: Adds entities to `persist/{model-name}/model.bal`

**`bal persist pull`**

- New optional argument: `--model <model-name>`
- Behavior without `--model`: Creates or updates `persist/model.bal`
- Behavior with `--model`: Creates or updates `persist/{model-name}/model.bal`

**`bal persist migrate`**

- New optional argument: `--model <model-name>`
- Behavior without `--model`: Uses `persist/model.bal` and creates migrations in `persist/migrations/`
- Behavior with `--model`: Uses `persist/{model-name}/model.bal` and creates migrations in `persist/{model-name}/migrations/`
- Error handling: Returns error if specified model does not exist
- Each model maintains independent migration history

### Data Store Configuration

- Each model can be configured to connect to a different data store type or instance
- Configuration is specified per model in the `Ballerina.toml` file:

```toml
# Root model configuration
[[tool.persist]]
id = "default-db"
targetModule = "myapp.db"
options.datastore = "mysql"
filePath = "persist/model.bal"

# Subdirectory model configurations
[[tool.persist]]
id = "users-db"
targetModule = "myapp.users_db"
options.datastore = "mysql"
filePath = "persist/users/model.bal"

[[tool.persist]]
id = "analytics-db"
targetModule = "myapp.analytics_db"
options.datastore = "postgresql"
filePath = "persist/analytics/model.bal"
```

- Supported scenarios include:
  - Root model → MySQL database
  - Users model → MySQL database (same or different instance)
  - Analytics model → PostgreSQL database
  - Cache model → Redis cache

### Code Generation

- Generated client code maintains the generic name `Client` for each model
- Developers can specify different target modules for generated code from different models
- Each model's generated code is isolated and independent
- If no module is specified, generated code follows existing default behavior

### Migration Management

- Each model maintains its own independent migration history
- Migration directory structure:
  - **Root model**: `persist/migrations/{timestamp}_{label}/` (backward compatible)
  - **Subdirectory models**: `persist/{modelName}/migrations/{timestamp}_{label}/`
- Both migration structures can coexist in the same project
- Each migration folder contains:
  - The model file snapshot (`model.bal`)
  - The migration SQL script (`script.sql`)
- Migration detection automatically handles both structures
- Validation prevents datastore changes for models with existing migrations

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

We conducted a comprehensive analysis of three architectural approaches for multi-model support. The chosen solution represents a hybrid approach that combines the best aspects of the evaluated alternatives.

### Alternative 1: Flat Multi-File Structure

**Approach**: Multiple `.bal` files at the root level of `persist/` directory (e.g., `persist/users.bal`, `persist/inventory.bal`, `persist/analytics.bal`).

**Pros**:

- Minimal implementation effort (already partially implemented)
- Full backward compatibility with existing projects
- Simple flat file discovery logic
- All models visible at once for quick reference

**Cons**:

- No visual separation of domain boundaries
- Can become cluttered with many models (10+)
- Hard to organize large teams around specific models
- All models mixed together at root level

**Decision**: Rejected in favor of subdirectory organization to provide better domain separation, avoid clutter in the persist directory, and enable better team collaboration patterns.

### Alternative 2: Per-Module Persist Directories

**Approach**: Each Ballerina module has its own persist directory (e.g., `modules/users/persist/model.bal`, `modules/inventory/persist/model.bal`).

**Pros**:

- Perfect alignment with Ballerina module system
- Excellent scalability for large enterprise projects
- Complete encapsulation per module
- Natural team ownership boundaries
- Generated code stays within module boundaries

**Cons**:

- Tight coupling of models to module structure (not all models may fit neatly into modules)
- Significant implementation effort (major refactoring required)
- Breaking change for all existing projects
- Complex multi-location model discovery
- Steeper learning curve for developers
- Root persist directory becomes a special case

**Decision**: Rejected due to high implementation cost, breaking changes for all existing users, and added complexity that may not be justified for the initial multi-model support. This approach could be considered for future major versions.

### Alternative 3: Process All Models by Default

**Approach**: When no `--model` is specified, automatically process all models in the project.

**Pros**:

- Convenient for bulk operations
- Simpler command syntax for multi-model projects

**Cons**:

- Could lead to unintended side effects
- Longer execution times
- Confusion about which models are being affected
- Potential for accidental modifications to unintended models
- Makes it harder to work on specific models in isolation

**Decision**: Rejected because it could lead to unintended consequences and reduces developer control over which models are affected by operations.

### Alternative 4: Support Cross-Model Relationships

**Approach**: Allow entities in different models to reference each other through foreign keys or relationships.

**Pros**:

- More flexible data modeling
- Could support complex business domains with interconnected entities

**Cons**:

- Significant complexity in dependency management
- Transaction handling across multiple data stores becomes complex
- Potential circular dependencies between models
- Blurs the separation of concerns that multi-model support aims to provide
- Complicates migration management and model independence
- Makes it harder to connect models to different data stores

**Decision**: Rejected to maintain clear separation of concerns and model independence. Each model should represent a distinct domain or data source without dependencies on other models.

### Alternative 5: Enforce Naming Conventions

**Approach**: Require model files to follow a specific pattern (e.g., `model-*.bal`, `*-model.bal`).

**Pros**:

- Consistent naming across projects
- Easy to identify model files programmatically

**Cons**:

- Adds unnecessary constraints
- Reduces flexibility for developers to organize models according to domain-specific conventions
- May not align with team or organization naming standards
- Creates artificial restrictions without significant benefit

**Decision**: Rejected to maintain flexibility, allowing developers to name models according to their domain requirements (e.g., `users`, `inventory`, `analytics`).

### Chosen Solution: Hybrid Subdirectory Approach

The selected approach combines the strengths of multiple alternatives:

- **Backward Compatibility**: Maintains support for existing `persist/model.bal` projects
- **Domain Separation**: Uses subdirectories for clear model organization (`persist/{modelName}/model.bal`)
- **Flexibility**: No enforced naming conventions beyond reserved names
- **Controlled Operations**: Explicit model specification required for multi-model projects
- **Independent Models**: No cross-model relationships to maintain separation of concerns

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
   - Create subdirectory models with `bal persist init --model <name>`
   - Verify correct directory structure and model file creation
   - Verify root model creation without `--model` argument

3. **Model-Specific Generation**
   - Generate clients for specific models using `bal persist generate --model <name>`
   - Verify correct client code is generated for each model
   - Verify error handling when model directory/file does not exist
   - Verify backward compatible behavior with root model

4. **Multi-Database Connection**
   - Create models connecting to different database types
   - Verify each model connects to its configured data store
   - Test CRUD operations on entities from different models

5. **Duplicate Entity Names**
   - Create identical entity definitions in different model files
   - Verify no conflicts occur
   - Verify independent operation of each model

6. **Migration Support**
   - Test migration generation for root model (backward compatible structure)
   - Test migration generation for subdirectory models
   - Verify both migration structures can coexist in the same project
   - Test migration with multiple models having different schemas
   - Test that migrations for different models are independent
   - Verify datastore change validation for models with existing migrations

7. **Hybrid Structure Support**
   - Test projects with both root model and subdirectory models
   - Verify commands work correctly with mixed model structures
   - Test migration coexistence and independence

8. **Compiler Plugin Integration**
   - Verify compiler plugin processes all model files (root and subdirectory)
   - Verify build-time validation for each model
   - Test error reporting for invalid model definitions

9. **Command Error Handling**
   - Verify error when no model specified and root model doesn't exist
   - Test reserved model name validation (e.g., `migrations`)
   - Test invalid model name/path scenarios
   - Verify appropriate error messages for missing model directories

### Test Environments

- Unit tests for CLI command parsing and validation
- Integration tests for multi-model project workflows
- End-to-end tests with multiple database types (MySQL, PostgreSQL, Redis, etc.)
- Migration tests for model-specific migration directories and backward compatibility
- Compiler plugin tests for multiple model processing
- Backward compatibility tests with existing single-model projects

## Risks and Assumptions

### Risks

- **Increased Complexity**: Introducing multiple models increases the complexity of the persist tool and may lead to a steeper learning curve for new users
- **Migration Conflicts**: Although each model has independent migration history, developers must be careful not to create conflicting schema changes in the database if multiple models target the same database
- **Documentation Overhead**: Comprehensive documentation will be needed to guide developers on best practices for organizing multiple models and managing migrations

### Assumptions

- Developers understand the independence of models and the absence of cross-model relationships
- Each model will typically represent a distinct domain or data source
- The majority of use cases involve connecting to different data stores rather than organizing a single data store into multiple models
- Generated client code being named `Client` for all models is acceptable, with module separation providing sufficient organization
- Migration histories for different models are independent, even when targeting the same database

## Dependencies

- Ballerina compiler plugin API for multi-file processing
- Persist CLI infrastructure for command argument parsing
- Ballerina.toml configuration schema for per-model data store settings
- Code generation templates that support model-specific output paths
