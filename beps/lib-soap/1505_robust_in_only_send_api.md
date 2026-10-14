# Robust In-Only Send API for the SOAP Client

- Authors - @Nuvindu
- Reviewed by -
- Created date - 2026/09/29
- Updated date - 2026/10/14
- Issue - [#1505](https://github.com/ballerina-platform/ballerina-spec/issues/1505)
- State - Submitted

## Summary

Add a `sendRobust()` remote function to the SOAP 1.1 and SOAP 1.2 clients in the `ballerina/soap` module. The function implements the WSDL 2.0 Robust In-Only Message Exchange Pattern: it sends a SOAP envelope without expecting a response body, but checks the HTTP status code and returns SOAP fault information on failure.

## Motivation

The SOAP module today provides two remote functions for sending messages:

- **`sendReceive()`** sends a SOAP envelope and returns the parsed response body. It maps to the WSDL Request-Response Message Exchange Pattern.
- **`sendOnly()`** sends a SOAP envelope and ignores the response entirely — including any SOAP fault. It maps to the WSDL One-Way Message Exchange Pattern.

There is no way to send a one-way message while still detecting server-side failures. The [WSDL 2.0 Robust In-Only MEP](https://www.w3.org/TR/wsdl20-adjuncts/#in-only) fills this gap. Here no response body is expected on success, but if the server returns a non-success HTTP status (such as 500 with a SOAP fault), the client reports the error.

Currently when encountering this type of scenario, users have to either choose between losing fault information (`sendOnly`) or unnecessarily parsing a response body (`sendReceive`).

## Goals

- Send a SOAP envelope without expecting a response body on success.
- Detect non-2xx HTTP responses and return an error that includes the HTTP status code and any SOAP fault XML from the response.
- Support all existing client capabilities: custom HTTP headers, resource path suffixes, SOAP attachments via `mime:Entity[]`, and outbound security policies.
- Match the parameter style of `sendReceive()` and `sendOnly()` so users can switch between the three functions with minimal changes.
- Provide distinct error subtypes (`SoapFaultError`, `NetworkError`) so callers can pattern-match on failure modes.

## Design

### 1. SOAP 1.1 Client

```ballerina
remote isolated function sendRobust(xml|mime:Entity[] body, string action,
                                    map<string|string[]> headers = {}, string path = "") returns Error?
```

The `action` parameter is mandatory because SOAP 1.1 requires the `SOAPAction` HTTP header.

### 2. SOAP 1.2 Client

```ballerina
remote isolated function sendRobust(xml|mime:Entity[] body, string? action = (),
                                    map<string|string[]> headers = {}, string path = "") returns Error?
```

The `action` parameter is optional because SOAP 1.2 carries the action in the `Content-Type` header and it is not always required.

### 3. Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `body` | `xml\|mime:Entity[]` | - | SOAP envelope as XML, or a SOAP message with MIME attachments |
| `action` | `string` (1.1) / `string?` (1.2) | - / `()` | SOAP action URI |
| `headers` | `map<string\|string[]>` | `{}` | Additional HTTP headers to include in the request |
| `path` | `string` | `""` | Resource path appended to the client endpoint URL |

### 4. Behavior

1. Outbound security policies configured on the client are applied to the SOAP envelope.
2. An HTTP POST request is created with the appropriate content type and action placement: `text/xml` with a separate `SOAPAction` HTTP header for SOAP 1.1, or `application/soap+xml` with the action as a `Content-Type` parameter for SOAP 1.2. Any custom headers are also included.
3. The request is sent to the server.
4. If the HTTP client returns an error (connection failure, timeout, etc.), a `NetworkError` is returned with the client error message.
5. If the HTTP response status code is outside the 2xx range:
   - The function attempts to read the response body as XML (which may contain a SOAP fault).
   - If the body contains a SOAP fault, a `SoapFaultError` is returned with the HTTP status code and the fault XML in the error detail.
   - Otherwise, a `NetworkError` is returned with the HTTP status code.
6. If the HTTP response status code is in the 2xx range, `()` is returned. The response body is not read.

### 5. Error types

The module introduces two distinct error subtypes under the existing `Error` type to let callers differentiate between failure modes:

```ballerina
# Defines the common error type for the module.
public type Error distinct error;

# Detail record for SOAP fault errors.
public type SoapFaultErrorDetail record {|
    int httpStatusCode;
    string detail;
|};

# Represents a SOAP fault returned by the server.
public type SoapFaultError distinct (Error & error<SoapFaultErrorDetail>);

# Detail record for network-level errors.
public type NetworkErrorDetail record {|
    int httpStatusCode?;
|};

# Represents a network-level error that occurs during SOAP communication.
public type NetworkError distinct (Error & error<NetworkErrorDetail>);
```

- **`SoapFaultError`** — Returned when the server responds with a non-2xx HTTP status and the response body contains a SOAP fault XML. Its detail record includes `httpStatusCode` (the HTTP status code) and `detail` (the fault XML as a string).
- **`NetworkError`** — Returned for HTTP client errors (connection failures, invalid URLs) or non-2xx responses without an XML payload. Its detail record includes an optional `httpStatusCode` (present when the error originates from an HTTP response, absent for connection-level failures).

Callers can pattern-match on these subtypes:

```ballerina
Error? result = soapClient->sendRobust(envelope, "http://tempuri.org/Add");
if result is SoapFaultError {
    int statusCode = result.detail().httpStatusCode;
    string faultXml = result.detail().detail;
    // Server returned a SOAP fault — inspect detail for fault XML
} else if result is NetworkError {
    int? statusCode = result.detail().httpStatusCode;
    // Connection or HTTP-level failure
} else if result is Error {
    // Other errors (e.g., security policy failures)
}
```

### 6. Comparison with existing functions

| Aspect | `sendReceive()` | `sendOnly()` | `sendRobust()` |
|--------|-----------------|--------------|----------------|
| Expects response body | Yes | No | No |
| Checks HTTP status | No | No | Yes |
| Returns SOAP fault details | As XML | No | As `SoapFaultError` |
| Return type | `xml\|mime:Entity[]\|Error` | `Error?` | `Error?` |
| WSDL MEP | Request-Response | One-Way | Robust In-Only |

### 7. Why `sendRobust()` instead of reusing `sendReceive()`?

- **Return type mismatch**: `sendReceive` returns `T|Error` (actual response data). In robust-in-only, there is no response body to return. Forcing the caller to handle a response they will never use would be misleading.
- **Different response handling**: `sendReceive` always extracts and returns the response body. `sendRobust` checks the HTTP status code — 2xx means success (return nil), non-2xx means it reads any SOAP fault XML and wraps it into a typed error.
- **Type safety**: `Error?` makes the "no response body" contract explicit. Callers cannot accidentally try to process a non-existent response.
- **WSDL compliance**: Maps 1:1 to the WSDL 2.0 Robust In-Only MEP (§2.3.2) with the "Message Triggers Fault" propagation rule.

### 8. Usage examples

#### SOAP 1.1: Send a one-way message with fault detection

```ballerina
import ballerina/soap.soap11;

public function main() returns error? {
    soap11:Client soapClient = check new ("http://www.example.com/soap-service");

    xml envelope = xml `<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                            soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
                            <soap:Body>
                              <quer:Add xmlns:quer="http://tempuri.org/">
                                <quer:intA>2</quer:intA>
                                <quer:intB>3</quer:intB>
                              </quer:Add>
                            </soap:Body>
                        </soap:Envelope>`;
    check soapClient->sendRobust(envelope, "http://tempuri.org/Add");
}
```

#### SOAP 1.2: Send a one-way message with fault detection

```ballerina
import ballerina/soap.soap12;

public function main() returns error? {
    soap12:Client soapClient = check new ("http://www.example.com/soap-service");

    xml envelope = xml `<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
                            soap:encodingStyle="http://www.w3.org/2003/05/soap-encoding">
                            <soap:Body>
                              <quer:Add xmlns:quer="http://tempuri.org/">
                                <quer:intA>2</quer:intA>
                                <quer:intB>3</quer:intB>
                              </quer:Add>
                            </soap:Body>
                        </soap:Envelope>`;
    check soapClient->sendRobust(envelope);
}
```

#### Handling a SOAP fault

```ballerina
import ballerina/soap.soap11;
import ballerina/io;

public function main() returns error? {
    soap11:Client soapClient = check new ("http://www.example.com/soap-service");

    xml envelope = xml `<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
                            <soap:Body>
                              <m:GetPrice xmlns:m="https://www.example.com/prices">
                                <m:Item>Apples</m:Item>
                              </m:GetPrice>
                            </soap:Body>
                        </soap:Envelope>`;
    soap11:Error? result = soapClient->sendRobust(envelope, "https://www.example.com/prices/GetPrice");
    if result is soap11:SoapFaultError {
        io:println("SOAP fault (HTTP ", result.detail().httpStatusCode, "): ", result.detail().detail);
    } else if result is soap11:NetworkError {
        io:println("Network error: ", result.message());
    } else if result is soap11:Error {
        io:println("SOAP call failed: ", result.message());
    }
}
```

## Alternatives

- **Use `sendReceive()` and discard the response.** This works but forces the client to read and parse a response body that is not expected, adding unnecessary overhead. It also misrepresents the intent of the operation.
- **Use `sendOnly()` and add error checking.** Not possible because `sendOnly()` does not inspect the HTTP response at all.
- **Add an optional parameter to `sendOnly()` to enable fault detection.** Rejected because it changes the semantics of an existing function and the two behaviors (ignore response vs. check status) are distinct enough to warrant separate functions.
- **Name the function `send()` instead of `sendRobust()`.** Rejected because `sendRobust` clearly communicates the WSDL Robust In-Only MEP semantics and is consistent with the naming convention of the other functions (`sendReceive`, `sendOnly`).

## Testing

1. Successful `sendRobust()` call with a 2xx response, for both SOAP 1.1 and SOAP 1.2 clients.
2. `sendRobust()` with a non-2xx response containing a SOAP fault, verifying the returned `SoapFaultError` includes the HTTP status code and the fault XML.
3. `sendRobust()` with a connection error (unreachable host), verifying a `NetworkError` is returned.
4. `sendRobust()` with a non-2xx response without an XML payload, verifying a `NetworkError` is returned.
5. `sendRobust()` with custom headers and a non-empty path.
6. `sendRobust()` with `mime:Entity[]` body (SOAP attachments).
7. `sendRobust()` with outbound security policies applied to the envelope.

## Risks and Assumptions

- The function does not read the response body on success. If a server returns meaningful data in a 2xx response to a one-way operation, that data is silently discarded. Users who need the response body should use `sendReceive()`.
- SOAP fault extraction from the error response is best-effort. If the response body is not valid XML, the error is still returned but without the fault detail.

## Dependencies

None.

## Future Work

- Inbound security policy support if a use case for processing signed or encrypted fault responses arises.

## References

- [WSDL 2.0 Robust In-Only MEP](https://www.w3.org/TR/wsdl20-adjuncts/#in-only)
