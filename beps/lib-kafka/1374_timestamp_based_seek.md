# Timestamp-based seeking support and retrieve metadata when sending message in ballerinax/kafka

- Authors
  - Thisaru Guruge
- Reviewed by
  - Danesh Kuruppu
  - Ayesh Almeida
- Created date 
  - 2025-07-08 
- Updated date
  - 2025-07-08
- Issue
  - [1374](https://github.com/ballerina-platform/ballerina-spec/issues/1374)
- State
  - Submitted

## Summary

The current Ballerina Kafka connector lacks some features which helps the users to improve their performance, efficiency, and ease of use. This aim of this proposal is to introduce new APIs to improve the performance and the user experience.

## Motivation

In real-world scenarios, having the ability to retrieve the metadata when sending a message to a Kafka broker, or seeking a consumer for a desired timestamp, are a few must-have features. This provides better troubleshooting capabilities, recoverability, performance improvement, and better user experience.

## Goals

* Provide the Kafka consumer an easy way to seek to a given timestamp
* Provide an API to retrieve metadata when sending Kafka records 

## Design

The following APIs are proposed to solve the aforementioned problems.

### Producer Send API
The current producer API has the following definition:

```ballerina
isolated remote function send(AnydataProducerRecord producerRecord) returns Error?
```

This returns an error if the sending is failed, but does not return any metadata when the record is successfully sent. This metadata is useful for troubleshooting and observability purposes.

#### The RecordMetadata Type

A new record type will be introduced to represent metadata that is retrieved while sending a message. This type directly corresponds to the `RecordMetadata` class in Apache Kafka Java SDK.

```ballerina
# Represents metadata of a Kafka record.
public type RecordMetadata record {|
    # The offset of the record in the topic partition
    int? offset = ();
    # The timestamp of the record in the topic partition
    int? timestamp = ();
    # The size of the serialized, uncompressed key in bytes. If key is null, the returned size is -1.
    int serializedKeySize;
    # The size of the serialized, uncompressed value in bytes. If value is null, the returned size is -1.
    int serializedValueSize;
    # The topic the record is appended to
    string topic;
    # The partition the record is sent to
    int partition;
|};
```

There are two approaches to return the metadata when sending a message.

#### Approach 1: Introduce a New API

A new API will be introduced to send messages with metadata.

```ballerina
isolated remote function sendWithMetadata(AnydataProducerRecord producerRecord) returns RecordMetadata|Error
```

This approach ensures the existing functionality of the send API does not break (backward compatible), while providing the new and existing users to send messages while retrieving metadata.

#### Approach 2: Update the Existing API

This approach suggests updating the existing API to retrieve metadata.

```ballerina
isolated remote function send(AnydataProducerRecord producerRecord) returns RecordMetadata|Error
```

But this approach will break the existing functionality. This will not break any existing user code built using older versions (if the `Dependencies.toml` file is intact). But it will break the existing code if the users try to migrate to a newer version.

Therefore, the **first approach above is preferred** since it allows the existing users to migrate without breaking their functionality while providing the option to migrate if they want to.

### Offsets for Times

In the Apache Kafka Java SDK, a separate API is provided for finding offsets for a given timestamp. This will return the map of topic partitions for the provided timestamp value, which can be used to seek the consumer for a given timestamp. A new API will be implemented in the `kafka:Consumer` object to reflect this functionality.

```ballerina
isolated remote function offsetsForTimes(TopicPartitionTimestamp[] topicPartitionTimestamps, decimal? duration = ()) returns TopicPartitionOffset[]|Error
```

The `TopicPartitionTimestamp` type is defined as a tuple type as described below:

```ballerina
# Represents a topic partition and a timestamp.
public type TopicPartitionTimestamp [TopicPartition, int];
```

The `TopicPartitionOffset` is defined as a tuple as described below:

```ballerina
# Represents a topic partition and an offset with a timestamp.
public type TopicPartitionOffset [TopicPartition, OffsetAndTimestamp];
```

The `OffsetAndTimestamp` type is defined as follows:

```ballerina
# Represents an offset and a timestamp for a topic partition.
public type OffsetAndTimestamp record {|
    # The offset of the record in the topic partition
    int offset;
    # The timestamp of the record in the topic partition
    int timestamp;
    # The leader epoch of the record in the topic partition
    int? leaderEpoch = ();
|};
```

#### Seek By Timestamp

To seek using a timestamp, users can use the existing `consumer->seek()` API. To seek by a particular timestamp, they can first use the above `offsetsForTimes` API to retrieve the offset for a given timestamp, and then pass it to the seek method.

Here’s an example code for seek by timestamp:

```ballerina
isolated function seekByTimestamp(kafka:Consumer consumer, string topic, int timestamp) returns error? {
    TopicPartition[] topicPartitions = check consumer->getTopicPartitions(topic);
    TopicPartitionTimestamp[] topicPartitionTimestamps = [];
    foreach TopicPartition topicPartition in topicPartitions {
        topicPartitionTimestamps.push([topicPartition, timestamp]);
    }
    TopicPartitionOffset[] topicPartitionOffsets = check consumer->offsetsForTimes(topicPartitionTimestamps);
    foreach TopicPartitionOffset topicPartitionOffset in topicPartitionOffsets {
        check consumer->seek({
            partition: topicPartitionOffset[0],
            offset: topicPartitionOffset[1].offset
        });
    }
}
```

> **Note:** This method should be implemented in the user code since the selecting the required topic partitions and filtering them out is completely depends on the use case.

### Additional Changes

Apart from the above-mentioned APIs, there are a few more improvements to be done in the Ballerina Kafka connector.

The main improvement is to support multiple services for the same listener. This is not supported right now as the Kafka topic-related configurations are defined in the Ballerina Kafka Listener. To improve this experience, we need to move the Kafka topic related configurations to the Ballerina Kafka service. This will be a breaking change which will result in a major release. Even in that case, any existing users who want to migrate to the newest version will have to re-write their code in order for it to be working. Therefore, we are not considering this change as of now.
