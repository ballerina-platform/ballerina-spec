# Add service-level acknowledgement control for WhatsApp Business webhook notifications

- Authors
  - Vellummyilum Vinoth
- Reviewed by
- Created date
  - 2026-08-20
- Issue
  - [#1487](https://github.com/ballerina-platform/ballerina-spec/issues/1487)
- State
  - Submitted

## Summary

Let a `whatsapp.business:WhatsAppService` control whether the `Listener` acknowledges (`200 OK`) an
inbound webhook notification immediately, or defers acknowledgement to the service itself, via a
per-service `@business:ServiceConfig { autoAck: false }` annotation and a new `Caller` client
(`caller->complete()`). The same design was implemented identically in `ballerinax/telegram`
(`@telegram:ServiceConfig { autoAck }`), so this BEP documents it as a single shared design used by
both connectors, with WhatsApp Business as the primary subject.

## Goals

- Let a service defer webhook acknowledgement until its own processing (e.g. an AI agent
  invocation, or a durable write) has actually succeeded, instead of the listener always eagerly
  responding `200 OK` before the handler runs.
- Configure acknowledgement mode **per service**, not per listener — a `Listener` merely reads the
  setting from the attached service; it has no acknowledgement-mode config of its own.
- Keep the naming, shape, and semantics identical across `whatsapp.business` and `telegram` (and
  consistent with `module-ballerinax-rabbitmq`'s established `@ServiceConfig { autoAck }`
  convention), so the pattern reads the same across WSO2's webhook-style connectors.

## Non-Goals

- Introducing retry/redelivery tracking of our own — each provider's own webhook retry behavior
  (retry on a non-`2xx`/slow response, then eventually give up) is relied on as-is.
- Changing how many services may be attached to a single `Listener`, or how `attach()`/`detach()`
  work otherwise.

## Motivation

Original ask ([ballerina-library#9041](https://github.com/ballerina-platform/ballerina-library/issues/9041)):
`whatsapp.business:Listener` always auto-acknowledges (`200 OK`) every inbound webhook notification
before a handler runs, giving consumers no way to defer acknowledgement until their own processing
had actually succeeded, with no way to opt out per listener. The identical limitation existed in
`ballerinax/telegram` ([ballerina-library#9037](https://github.com/ballerina-platform/ballerina-library/issues/9037)).

The design went through two iterations before landing on the shape below, in both connectors:

1. First cut: `ListenerConfig.manualAcks` — a `boolean`, default `false`, configured once on the
   `Listener` itself.
2. Renamed and inverted to `autoAck` (default `true`) and moved from a `Listener`-level config field
   to a per-service `@ServiceConfig` annotation — matching `module-ballerinax-rabbitmq`'s
   established naming, polarity, and per-service placement for the same concept
   (`@rabbitmq:ServiceConfig { autoAck }`), since `Listener.attach()` already builds one dedicated
   `HttpService` per attached service, so each attached service's acknowledgement mode can be
   configured independently rather than being one global listener-wide setting.

## Design

### Acknowledgement control (shared design, both connectors)

A `<Connector>ServiceConfig` record and `ServiceConfig` annotation, declared alongside the service
type (`ballerina/service_types.bal`):

```ballerina
# Configuration for a `WhatsAppService`'s acknowledgement behavior.
public type WhatsAppServiceConfig record {|
    # Whether the listener acknowledges (`200 OK`) a notification automatically as soon as it's
    # received, before any handler runs. Defaults to `true` (automatic acknowledgement).
    boolean autoAck = true;
|};

# Configures a `WhatsAppService`'s acknowledgement behavior. Optional — a service with no
# `@ServiceConfig` behaves as though `autoAck: true` were set.
public annotation WhatsAppServiceConfig ServiceConfig on service, class;
```

`Listener.attach()` reads the annotation off the attached service at attach time, using Ballerina's
runtime annotation-access expression (`typedesc.@AnnotTag`), and passes it into that service's own
dedicated `HttpService` instance:

```ballerina
public function attach(WhatsAppService whatsappService, string[]|string? name = ()) returns Error? {
    WhatsAppServiceConfig serviceConfig = (typeof whatsappService).@ServiceConfig ?: {};
    HttpService httpService = new (whatsappService, self.verifyToken, self.appSecret,
            serviceConfig.autoAck);
    ...
}
```

Runtime behavior in `HttpService`'s webhook resource (`ballerina/dispatcher_service.bal`):

```ballerina
Caller ackCaller = new (caller);
if self.autoAck {
    check ackCaller->complete();
}
self.dispatch(payload, ackCaller);
```

- `autoAck: true` (the default, or no annotation): the listener calls `ackCaller->complete()`
  itself — the same method a handler would call — immediately, before dispatching to the handler.
- `autoAck: false`: the listener does not acknowledge itself. The optional second `Caller`
  parameter is the only way a handler can acknowledge — a handler that declares it and calls
  `caller->complete()` once ready sends the `200 OK` itself. A handler that omits the parameter, or
  declares it but never calls `complete()`, never acknowledges, and the underlying `http:Service`
  sends its own default `500` — a non-`2xx`, so the provider's own retry-then-give-up behavior
  takes over. This connector adds no separate timeout/retry mechanism of its own.

`Caller` (`ballerina/caller.bal`):

```ballerina
public isolated client class Caller {
    isolated remote function complete() returns Error?;
}
```

`complete()` is idempotent by design: the whole check-respond-mark sequence runs inside a single
`lock`, so concurrent calls on the same `Caller` are fully serialized — at most one `respond()`
attempt is in flight at a time, and no separate guard flag is needed for that. `completed` is set
`true` only *after* `respond()` succeeds; a call that fails (`respond()` returns an error) leaves
`completed` as `false`; the error is returned to the caller as `ClientError`, and a later
`complete()` call is **not** treated as already-done — it attempts to acknowledge again, rather
than silently no-op-ing on a failed prior attempt. Calling `complete()` when the notification was
already *successfully* acknowledged — automatically (`autoAck: true`), or by an earlier successful
call to `complete()` — is the one case that's a safe no-op; it does **not** raise an error (see
Alternatives below for why).

### Usage example — WhatsApp Business

```ballerina
listener business:Listener whatsappListener = new (
        8090, verifyToken = "my-verify-token", appSecret = "my-app-secret");

@business:ServiceConfig {
    autoAck: false
}
service business:WhatsAppService on whatsappListener {
    remote function onMessages(business:MessagesNotification notification, business:Caller caller)
            returns error? {
        check persistNotification(notification);
        check caller->complete();
    }
}
```

### Applied identically to `ballerinax/telegram`

The same `TelegramServiceConfig`/`@ServiceConfig { autoAck }` shape and `Caller.complete()`
behavior were implemented in `ballerinax/telegram`, under
[ballerina-library#9037](https://github.com/ballerina-platform/ballerina-library/issues/9037):

```ballerina
listener telegram:Listener telegramListener = new (8090, accessToken = "my-bot-access-token");

@telegram:ServiceConfig {
    autoAck: false
}
service telegram:TelegramService on telegramListener {
    remote function onMessage(telegram:Message message, telegram:Caller caller) returns error? {
        check persistMessage(message);
        check caller->complete();
    }
}
```

## Alternatives

- **Keep `autoAck` as a `Listener`-level (`ListenerConfig`) field**, instead of a service
  annotation: simpler, and closer to the original ask in both connectors' issues, but doesn't let
  different services attached to the same `Listener` have independent acknowledgement behavior, and
  would be inconsistent with `module-ballerinax-rabbitmq`'s per-service `@ServiceConfig` convention
  for the identical concept. Rejected in favor of the per-service annotation.
- **Have `caller->complete()` raise an `Error` when called redundantly**, matching
  `rabbitmq:Caller`'s `basicAck`/`basicNack` (which error both on a double-ack and on acking while
  `autoAck: true`): rejected. RabbitMQ's error guards against a real correctness hazard — acking the
  wrong delivery tag against a live, stateful broker channel. A webhook acknowledgement has no
  equivalent: it is a single boolean "has the HTTP response been sent" state, so a redundant
  `complete()` call can never target "the wrong message." Erroring would only punish the documented,
  tested pattern of a handler declaring `Caller` defensively and always calling `complete()`,
  regardless of the attached service's `autoAck` setting.

## Testing

Both connectors cover the same three scenarios today:

- A service annotated `@ServiceConfig {autoAck: false}` whose handler calls `caller->complete()`
  receives its own `200 OK` (`testManualAckRespondsWhenHandlerCompletes`).
- A service annotated `@ServiceConfig {autoAck: false}` whose handler never calls `complete()`
  falls through to the underlying HTTP service's default `500`
  (`testManualAckNeverRespondsWhenHandlerDoesNotComplete`).
- A service with the default (`autoAck: true`, no annotation) still gets an immediate `200 OK`, and
  a handler that declares `Caller` and calls `complete()` anyway does not error
  (`testManualAckCompleteIsNoOpWhenAlreadyAutoAcked`).

Recommended additional coverage, not yet implemented in either connector:

- **Failed-then-succeeded `complete()`**: a `Caller` whose first `complete()` call fails (e.g. the
  underlying `http:Caller->respond()` errors) remains retryable — a second `complete()` call is not
  treated as a no-op and can still succeed. Verifies the claim in Design that only a *successful*
  acknowledgement marks `completed`.
- **Duplicate delivery under `autoAck: false`**: simulate the provider redelivering the same
  notification/update after a slow-but-eventually-successful `complete()`, and confirm the example
  handler pattern in this BEP needs the consumer's own idempotency/dedup — this connector does not
  provide it (see Risks and Assumptions).

## Risks and Assumptions

- Assumes `Listener.attach()` is the only path by which a service becomes active, so reading
  `@ServiceConfig` there is sufficient — true today, in both connectors.
- This work is unreleased in both connectors (neither #9037 nor #9041 has shipped in a numbered
  version), so no backward-compatibility or deprecation path is required.
- **At-least-once delivery, not exactly-once**: with `autoAck: false`, a handler's own durable work
  (e.g. `persistNotification`/`persistMessage`) can commit successfully, and the acknowledgement
  response can still be slow, dropped, or never observed by the provider — the provider then
  redelivers the same notification/update, per its own retry behavior (see Non-Goals). This
  connector does not deduplicate or track delivery state itself, in either connector. Consumers
  relying on `autoAck: false` for durable processing must make that processing idempotent, or
  deduplicate using a **scoped** event key — not just any field that looks like an ID:
  - Telegram: `update_id` uniquely identifies an update; safe to use alone.
  - WhatsApp Business messages: `InboundMessage.messageId` (`wamid`) uniquely identifies a message;
    safe to use alone. The entry-level `timestamp` on `Messages`/`MessageStatuses` is **not** a
    valid key on its own — it's shared across every message/status in the same batch.
  - WhatsApp Business status updates: `MessageStatusUpdate.messageId` alone is **not** sufficient —
    the same message produces multiple status updates (`sent`, `delivered`, `read`, ...) sharing
    one `messageId`. Dedupe on `(messageId, status)` instead.
  - Other WhatsApp Business event types with no built-in unique identifier (e.g. `AccountUpdate`,
    `BusinessCapabilityUpdate`) need a key composed from their own discriminating fields (e.g.
    `wabaId` + `event` + `timestamp`), defined per event type.

  This risk exists identically under `autoAck: true`, since the provider may also redeliver if the
  (automatic) `200 OK` itself is lost in transit — it is not specific to manual acknowledgement,
  just easier to trigger by taking longer before responding.

## Dependencies

- None beyond the existing `ballerina/http` dependency already used by both connectors' `Listener`.

## Future Work

- Consider documenting `@ServiceConfig { autoAck }` as a shared cross-connector convention for
  webhook-style Ballerina connectors generally, given it is now used identically by
  `whatsapp.business`, `telegram`, and (in spirit, via its own `@ServiceConfig`) `rabbitmq`.

## References

- Origin issues: [ballerina-library#9041](https://github.com/ballerina-platform/ballerina-library/issues/9041) (WhatsApp Business),
  [ballerina-library#9037](https://github.com/ballerina-platform/ballerina-library/issues/9037) (Telegram)
- Reference convention: `module-ballerinax-rabbitmq`'s `@rabbitmq:ServiceConfig { autoAck }`
  (`ballerina/listener.bal`, native `util/MessageUtils.java`)

[]: # (end)
[]: # Please add any comments to issue [#1487](https://github.com/ballerina-platform/ballerina-spec/issues/1487)
