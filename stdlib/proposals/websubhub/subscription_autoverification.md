# Auto-verify subscriptions in Ballerina WebSubHub

- Authors
  - Ayesh Almeida
- Reviewed by
  - Shafreen Anfar, Danesh Kuruppu
- Created date
  - 2025-02-13
- Issue
  - [1336](https://github.com/ballerina-platform/ballerina-spec/issues/1336)
- State
  - Submitted

## Summary

This proposal introduces an enhancement to the Ballerina `websubhub` library that enables the developer to disable the WebSub 
subscription verification process for well known or authenticated subscriptions. This proposal introduces a service-level 
configuration to enable automatic subscription verification and an optional parameter for the `onSubscription` and 
`onUnsubscription` methods in `websubhub:Service` to mark specific subscriptions as auto-verified. The identification of 
properly authenticated subscriptions remains the responsibility of the developer implementing the WebSub hub.

## Goals

- Provide the WebSub hub implementer more control over how subscriptions are verified/authenticated.

## Non-Goals

- This proposal will not change the current behavior of the WebSub hub. It will only introduce an alternate mechanism which the developer can use to disable the current subscription verification process if needed.

## Motivation

The subscription intent verification step exists to verify and authenticate the subscription request sent to the hub. However, 
in some scenarios, a developer may have well-known (and authenticated) subscribers who do not require this additional 
verification step. This proposal aims to allow developers more control over the subscription verification process by 
introducing a configuration in the Ballerina `websubhub` library. This will enable developers to skip the standard subscription 
intent verification process based on the requirement.

## Description

This proposal introduces two levels of validation to enable subscription auto-verification in Ballerina WebSubHub:

1. **Service-level configuration** :
    - Add a new configuration parameter in the `@websubhub:ServiceConfig` annotation that allows enabling or disabling automatic subscription verification at the hub level.

2. **Introduce an optional parameter for `onSubscription` and `onUnsubscription` methods of `websubhub:Service`** :
    - Add a new client object that allows dynamically marking a subscription or unsubscription for auto-verification.

### Service-level configuration

An optional boolean configuration parameter will be added to the `@websubhub:ServiceConfig` annotation:

```ballerina
    @websubhub:ServiceConfig { 
        // other fields
        autoVerifySubscription: true
    }
```

### `websubhub:Controller` parameter

Along with the configuration for `websubhub:ServiceConfig` the developer needs to have a way to mark specific subscription/unsubscription as auto-verifiable. For that we need to introduce an optional parameter to the `onSubscription` and `onUnsubscription` remote methods of the `websubhub:Service`.

```ballerina
    public type Controller client object {

        # Marks a specific subscription or unsubscription request as verified, bypassing the standard challenge-response verification process. 
        public function markAsVerified(websubhub:Subscription|websubhub:Unsubscription subscription) returns error?;
    };
```

### Behavior

* If `autoVerifySubscription` is enabled in `websubhub:ServiceConfig` and the developer marks the subscription as auto-verifiable, the hub skips the subscription intent verification step.  
If `autoVerifySubscription` is disabled or the subscription is not explicitly marked as auto-verifiable, the hub follows the standard challenge-response verification process.

#### Reference Implementation

A sample implementation in a WebSubHub service:

```ballerina
    @websubhub:ServiceConfig { 
        autoVerifySubscription: true 
    }
    service /hub on new websubhub:Listener(9090) {
        // implement the other required remote methods

        remote function onSubscription(websubhub:Subscription msg, websubhub:Controller hubController) 
            returns websubhub:SubscriptionAccepted|error {
        
            // perform the authn/authz operation
            check hubController.markAsVerified(msg);
        }

        remote function onUnsubscription(websubhub:Unsubscription msg, websubhub:Controller hubController) 
            returns websubhub:UnsubscriptionAccepted|error {
        
            // perform the authn/authz operation
            check hubController.markAsVerified(msg);
        }
    }

```

## Alternatives

Some vendors like GitHub use an HTTP POST (instead of HTTP GET) request with a Ping payload to verify the subscription intent 
whenever a subscription or webhook is registered. This mechanism could be adopted in the `websubhub` library by enabling it 
through a configuration.

## Risks and Assumptions

* When this configuration is enabled, it is assumed that the developer will integrate some authentication mechanism to authenticate the subscription during the subscription phase.
* This feature might be a potential violation of the defined WebSub standard, and users should be notified about that in the API documentation.

## Dependencies

No additional dependencies are introduced. The feature will be built into the `ballerina/websubhub` module.

## Testing

- Unit tests will be added to verify the correct behavior when `autoVerifySubscription` is enabled and the subscription has been marked to skip the verification.
- Integration tests will confirm that the standard verification process remains intact when the flag is `false`.
