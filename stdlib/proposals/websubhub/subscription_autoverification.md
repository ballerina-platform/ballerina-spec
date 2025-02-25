# Automatic subscriptin intent verification in Ballerina WebSubHub

- Authors
  - Ayesh Almeida
- Reviewed by
  - Shafreen Anfar, Danesh Kuruppu, Maryam Ziyad
- Created date
  - 2025-02-13
- Issue
  - [1336](https://github.com/ballerina-platform/ballerina-spec/issues/1336)
- State
  - Submitted

## Summary

This proposal introduces an enhancement to the Ballerina `websubhub` library that enables the developer to disable the WebSub 
subscription intent verification process for authenticated and authorized subscriptions. This proposal introduces a service-level 
configuration to enable automatic subscription intent verification and an optional parameter for the `onSubscription` and 
`onUnsubscription` methods in `websubhub:Service` to mark specific subscriptions as auto-verified. The identification of 
properly authenticated and authorized subscriptions remains the responsibility of the developer implementing the WebSub hub.

## Goals

- Provide the WebSub hub implementer more control over how to verify subscription intent.

## Non-Goals

- This proposal will not change the current behavior of the WebSub hub. It will only introduce an alternate mechanism which the developer can use to disable the current subscription 
intent verification process if needed.

## Motivation

The subscription intent verification step exists to verify and authenticate the subscription request sent to the hub. However, 
in some scenarios, a developer may have authenticated and authorized subscribers who do not require this additional 
verification step. This proposal aims to allow developers more control over the subscription intent verification process by 
introducing a configuration in the Ballerina `websubhub` library. This will enable developers to skip the standard subscription 
intent verification process based on the requirement.

## Description

This proposal introduces two levels of validation to enable subscription auto-verification in Ballerina WebSubHub:

1. **Service-level configuration** :
    - Add a new configuration parameter in the `@websubhub:ServiceConfig` annotation that allows enabling or disabling automatic subscription intent verification at the hub level.

2. **Introduce an optional parameter for `onSubscription` and `onUnsubscription` methods of `websubhub:Service`** :
    - Add a new client object that allows dynamically marking a subscription or unsubscription for auto-verification.

### Service-level configuration

An annotation field, which will be set to `false` by default, will be added to the `@websubhub:ServiceConfig` annotation:

```ballerina
    @websubhub:ServiceConfig { 
        // other fields
        autoVerifySubscriptionIntent: true
    }
```

### `websubhub:Controller` parameter

In addition to the `websubhub:ServiceConfig` configuration, developers need a mechanism to mark specific subscriptions and unsubscriptions as verified. To address this, we are introducing a new Ballerina object type, `websubhub:Controller`.

```ballerina
    public type Controller client object {

        # Marks a specific subscription or unsubscription request as verified, bypassing the standard challenge-response verification process. 
        public function markAsVerified(websubhub:Subscription|websubhub:Unsubscription subscription) returns websubhub:Error?;
    };
```

> Note: The `websubhub:Controller` will be available only as an optional parameter in the `onSubscription` and `onUnsubscription` remote methods of the `websubhub:Service`.

### Behavior

* If `autoVerifySubscriptionIntent` is enabled in `websubhub:ServiceConfig` and the developer marks the subscription as verified, the hub skips the subscription intent verification step.  
* If `autoVerifySubscriptionIntent` is disabled and the developer marks the subscription as verfied, the `websubhub:Controller` will throw and error saying marking subscription as 
verified but the configuration has not been turned-on. Since `websubhub:Controller` is only available as a parameter in the `onSubscription` and `onUnsubscription` methods, this error will be returned as an error response to the subscriber.
* If `autoVerifySubscriptionIntent` is enabled and the subscription is not explicitly marked as verified, the hub follows the standard challenge-response verification process.
* If `autoVerifySubscriptionIntent` is disabled and the subscription is not explicitly marked as verified, the hub follows the standard challenge-response verification process.

#### Reference Implementation

A sample implementation in a WebSubHub service:

```ballerina
    @websubhub:ServiceConfig { 
        autoVerifySubscriptionIntent: true 
    }
    service /hub on new websubhub:Listener(9090) {
        // Implement the other required remote methods

        remote function onSubscription(websubhub:Subscription msg, websubhub:Controller hubController) 
            returns websubhub:SubscriptionAccepted|error {
        
            // Perform the authn/authz operation
            check hubController.markAsVerified(msg);
        }

        remote function onUnsubscription(websubhub:Unsubscription msg, websubhub:Controller hubController) 
            returns websubhub:UnsubscriptionAccepted|error {
        
            // Perform the authn/authz operation
            check hubController.markAsVerified(msg);
        }
    }

```

## Alternatives

Some vendors like GitHub use an HTTP POST (instead of HTTP GET) request with a Ping payload to verify the subscription intent 
whenever a subscription or webhook is registered. This mechanism could be adopted in the `websubhub` library by enabling it 
through a configuration.

## Risks and Assumptions

- Enabling this configuration assumes that the developer will implement an authentication and authorization mechanism to verify subscription intent during the subscription process.  
- A WebSub `hub` implementation utilizing this feature may potentially violate the WebSub standard; therefore, users should be informed of this in the API documentation.

## Dependencies

No additional dependencies are introduced. The feature will be built into the `ballerina/websubhub` module.

## Testing

- Unit tests will be added to verify the correct behavior when `autoVerifySubscriptionIntent` is enabled and the subscription has been marked to skip the verification.
- Integration tests will confirm that the standard verification process remains intact when the flag is `false`.
