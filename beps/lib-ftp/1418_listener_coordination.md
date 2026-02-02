# 1418: FTP Listener Distributed Coordination Support

- Authors: @niveathika
- Reviewed by:
- Created: 2026-01-26
- Updated: 2026-01-26
- Issue: [#1418](https://github.com/ballerina-platform/ballerina-spec/issues/1418)
- State: Submitted

## Summary

This proposal introduces distributed coordination support for the Ballerina FTP listener, enabling high availability deployments where multiple FTP listener instances coordinate so that only one actively polls while others act as warm standby nodes.

## Motivation

### Problem Statement

In production environments, FTP listeners are often deployed across multiple nodes for high availability. However, without coordination, all nodes would simultaneously poll the FTP server, leading to:

1. **Duplicate processing**: Multiple nodes detecting and processing the same file changes
2. **Race conditions**: Concurrent access to the same files causing conflicts
3. **Resource waste**: Unnecessary load on both FTP servers and application nodes
4. **Inconsistent state**: Different nodes having different views of file system state

### Current Limitations

The current FTP listener implementation does not provide any built-in mechanism for distributed coordination. Users must implement custom solutions using external tools or accept the limitations of single-node deployments.

### Benefits

- **High availability**: Automatic failover when the active node becomes unresponsive
- **No duplicate processing**: Only one node actively polls at any time
- **Simplified deployment**: Built-in coordination eliminates need for external tools
- **Consistent with task module**: Leverages the existing `ballerina/task` coordination infrastructure

### Stakeholders

- Developers building enterprise integration solutions with FTP/SFTP
- Operations teams managing distributed Ballerina deployments
- Organizations requiring high availability for file-based integrations

## Goals

1. Expose the `ballerina/task` module's warm backup coordination feature at the FTP listener level
2. Provide a clean, FTP-specific API that abstracts the underlying task module implementation
3. Enable seamless failover between FTP listener nodes without duplicate file processing
4. Maintain backward compatibility with existing FTP listener configurations

## Non-Goals

1. Implementing a new coordination mechanism (we leverage the existing task module)
2. Supporting coordination databases other than MySQL and PostgreSQL
3. Providing active-active coordination (only warm backup/active-passive is supported)
4. Coordinating across different FTP listener configurations (each group monitors one path)

## Design

### Configuration Model

A new optional `coordination` field is added to `ListenerConfiguration`:

```ballerina
public type ListenerConfiguration record {|
    // ... existing fields ...
    CoordinationConfig coordination?;
|};
```

The `CoordinationConfig` record provides FTP-specific naming while mapping to the task module's `WarmBackupConfig`:

```ballerina
# Represents the configuration required for distributed task coordination.
# When configured, multiple FTP listener instances coordinate so that only one actively polls
# while others act as warm standby nodes.
#
# + databaseConfig - The database configuration for task coordination
# + livenessCheckInterval - The interval (in seconds) to check the liveness of the active node. Default is 30 seconds.
# + memberId - Unique identifier for the current member. Must be distinct for each node in the distributed system.
# + coordinationGroup - The name of the coordination group of FTP listeners that coordinate together.
#                       It is recommended to use a unique name for each group.
# + heartbeatFrequency - The interval (in seconds) for the node to update its heartbeat status. Default is 1 second.
public type CoordinationConfig record {|
    task:DatabaseConfig databaseConfig;
    int livenessCheckInterval = 30;
    string memberId;
    string coordinationGroup;
    int heartbeatFrequency = 1;
|};
```

### Database Configuration

The coordination uses the task module's database configuration types:

```ballerina
# From ballerina/task module
public type DatabaseConfig MysqlConfig|PostgresqlConfig;

public type MysqlConfig record {
    string host = "localhost";
    string? user = ();
    string? password = ();
    int port = 3306;
    string? database = ();
};

public type PostgresqlConfig record {
    string host = "localhost";
    string? user = ();
    string? password = ();
    int port = 5432;
    string? database = ();
};
```

### Implementation

The FTP listener internally uses a `task:Listener` to schedule polling. When coordination is configured, the task listener is initialized with `warmBackupConfig`:

```ballerina
public isolated function init(*ListenerConfiguration listenerConfig) returns Error? {
    self.config = listenerConfig.clone();
    lock {
        task:Listener|error taskListener;
        if listenerConfig.coordination is CoordinationConfiguration {
            CoordinationConfig coordination = <CoordinationConfig>listenerConfig.coordination;
            taskListener = new ({
                trigger: {interval: listenerConfig.pollingInterval},
                warmBackupConfig: {
                    databaseConfig: coordination.databaseConfig,
                    livenessCheckInterval: coordination.livenessCheckInterval,
                    taskId: coordination.memberId,
                    groupId: coordination.coordinationGroup,
                    heartbeatFrequency: coordination.heartbeatFrequency
                }
            });
        } else {
            taskListener = new ({
                trigger: {interval: listenerConfig.pollingInterval}
            });
        }
        // ... rest of initialization
    }
}
```

### Field Name Mapping

FTP-specific field names are mapped to task module names for clarity:

| FTP Configuration | Task Module | Description |
|-------------------|-------------|-------------|
| `memberId` | `taskId` | Unique identifier for this member |
| `coordinationGroup` | `groupId` | Name of the coordination group |

### Usage Example

```ballerina
import ballerina/ftp;

listener ftp:Listener ftpListener = new ({
    host: "ftp.example.com",
    port: 21,
    auth: {
        credentials: {
            username: "user",
            password: "pass"
        }
    },
    path: "/incoming",
    pollingInterval: 30,
    coordination: {
        databaseConfig: {
            host: "mysql.example.com",
            user: "coordinator",
            password: "secret",
            database: "ftp_coordination"
        },
        memberId: "member-1",      // unique per deployment node
        coordinationGroup: "incoming-files-group"
    }
});

service on ftpListener {
    remote function onFileChange(ftp:WatchEvent event, ftp:Caller caller) returns error? {
        // Only one node in the cluster will execute this
        foreach ftp:FileInfo file in event.addedFiles {
            // Process file...
        }
    }
}
```

### How Coordination Works

1. **Leader election**: Members in the same `coordinationGroup` coordinate via the database to elect an active member
2. **Heartbeat**: The active node updates its heartbeat at `heartbeatFrequency` intervals
3. **Liveness monitoring**: Standby nodes check the active node's heartbeat every `livenessCheckInterval` seconds
4. **Failover**: If the active node's heartbeat becomes stale, a standby node takes over as the new active node
5. **Polling**: Only the active node's `poll()` function executes; standby nodes skip polling

### Database Schema

The coordination database schema is managed by the `ballerina/task` module. Users must ensure the coordination database is accessible and properly configured before starting the listeners.

## Alternatives

### Alternative 1: FTP-Specific Coordination Implementation

Implement a custom coordination mechanism specifically for FTP.

**Rejected because**: This would duplicate effort and deviate from the established pattern in the task module. Using the task module ensures consistency across Ballerina modules.

### Alternative 2: Active-Active with Distributed Locking

Implement per-file locking to allow multiple nodes to process different files simultaneously.

**Rejected because**: This significantly increases complexity and may not be compatible with all FTP server configurations. The warm backup approach is simpler and sufficient for most use cases.

## Testing

### Unit Tests

1. Verify `CoordinationConfig` is correctly mapped to `task:WarmBackupConfig`
2. Verify task listener is created with coordination when configured
3. Verify task listener is created without coordination when not configured
4. Verify backward compatibility with existing configurations

### Integration Tests

1. Deploy two FTP listener members with the same `coordinationGroup`
2. Verify only one node actively polls
3. Simulate active node failure and verify failover
4. Verify no duplicate file processing during failover

### Manual Tests

1. Test with MySQL coordination database
2. Test with PostgreSQL coordination database
3. Test failover scenarios with network partitions
4. Test recovery when coordination database is temporarily unavailable

## Risks and Assumptions

### Risks

1. **Database availability**: Coordination depends on database connectivity. If the coordination database is unavailable, nodes may not be able to determine the active node.

2. **Clock synchronization**: Heartbeat-based coordination assumes reasonably synchronized clocks across nodes.

3. **Network partitions**: In split-brain scenarios, multiple nodes might briefly become active. The polling interval and liveness check settings help minimize this window.

### Assumptions

1. Users have access to a MySQL or PostgreSQL database for coordination
2. Network latency between nodes and the coordination database is reasonable

## Dependencies

- `ballerina/task` module (version 2.11.0 or later with warm backup support)
- MySQL or PostgreSQL database for coordination

## Future Work

- Support for additional coordination databases beyond MySQL and PostgreSQL
- Metrics and observability for coordination status (active/standby state, failover events)

---

## References

- [Ballerina Task Module - Warm Backup Configuration](https://central.ballerina.io/ballerina/task/latest)
- [Ballerina FTP Module](https://central.ballerina.io/ballerina/ftp/latest)

---

*Please add your comments to the associated GitHub issue.*
