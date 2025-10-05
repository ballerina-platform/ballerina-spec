# 8292: RSASSA-PSS (PS256) Signature Support for Ballerina Crypto Module

- Authors
  - Randil Tharusha (@randilt)
- Reviewed by
  - @daneshk @ThisaruGuruge 
- Created date
  - 2025-10-03
- Updated date
  - 2025-10-03
- Issue
  - [8292](https://github.com/ballerina-platform/ballerina-library/issues/8292)
- State
  - Submitted

## Summary

This proposal introduces support for the RSASSA-PSS signature scheme with SHA-256 (PS256) to the Ballerina Crypto Module. Currently, only classic RSA signatures using PKCS#1 v1.5 padding are available. RSASSA-PSS provides enhanced security properties including provable security, probabilistic signatures, and is increasingly required by modern cryptographic standards and protocols such as JWT PS256.

Please add any comments to issue [#8292](https://github.com/ballerina-platform/ballerina-library/issues/8292).

## Goals

- Provide support for RSASSA-PSS signature generation with SHA-256
- Provide support for RSASSA-PSS signature verification with SHA-256
- Enable higher-level modules like JWT to utilize PS256 signatures
- Maintain backward compatibility with existing crypto library APIs
- Follow existing architectural patterns and naming conventions

## Motivation

The Ballerina Crypto Module currently supports several RSA signature algorithms using PKCS#1 v1.5 padding:

- RSA-MD5
- RSA-SHA1
- RSA-SHA256
- RSA-SHA384
- RSA-SHA512

However, RSASSA-PSS (Probabilistic Signature Scheme), which is defined in RFC 8017 and provides enhanced security properties, is not supported. This limitation affects developers who need to implement modern security protocols.

### Why RSASSA-PSS is Important

1. **Enhanced Security**: RSASSA-PSS has provable security in the random oracle model, unlike PKCS#1 v1.5
2. **Probabilistic Nature**: Uses random salt generation, making signatures non-deterministic and more secure
3. **Industry Standards**: Required by modern protocols like JWT PS256, OAuth 2.0, and OpenID Connect
4. **Future-Proof**: NIST and other standards bodies recommend RSASSA-PSS over PKCS#1 v1.5
5. **Regulatory Compliance**: Some security frameworks mandate PSS for new implementations

### Current Limitations

Without RSASSA-PSS support, Ballerina developers must:

- Rely on external libraries or workarounds
- Cannot implement JWT PS256 natively
- Are limited to potentially less secure PKCS#1 v1.5 signatures
- Face compatibility issues with systems requiring PS256

## Design

This proposal follows the existing architectural patterns of the Ballerina crypto library to ensure consistency and maintainability.

### API Design

Two new functions will be added to the `crypto` module following the exact naming pattern of existing RSA signature functions:

````ballerina
# Returns the RSASSA-PSS with SHA-256 based signature value for the given data.
# ```ballerina
# string input = "Hello Ballerina";
# byte[] data = input.toBytes();
# crypto:KeyStore keyStore = {
#     path: "/path/to/keyStore.p12",
#     password: "keyStorePassword"
# };
# crypto:PrivateKey privateKey = check crypto:decodeRsaPrivateKeyFromKeyStore(keyStore, "keyAlias", "keyPassword");
# byte[] signature = check crypto:signRsaSsaPss256(data, privateKey);
# ```
#
# + input - The content to be signed  as a byte array
# + privateKey - The private key used for signing
# + return - The generated signature or else a `crypto:Error` if the private key is invalid
public isolated function signRsaSsaPss256(byte[] input, PrivateKey privateKey) returns byte[]|Error;
````

````ballerina
# Verifies the RSASSA-PSS with SHA-256 based signature.
# ```ballerina
# string input = "Hello Ballerina";
# byte[] data = input.toBytes();
# crypto:KeyStore keyStore = {
#     path: "/path/to/keyStore.p12",
#     password: "keyStorePassword"
# };
# crypto:PrivateKey privateKey = check crypto:decodeRsaPrivateKeyFromKeyStore(keyStore, "keyAlias", "keyPassword");
# byte[] signature = check crypto:signRsaSsaPss256(data, privateKey);
# crypto:PublicKey publicKey = check crypto:decodeRsaPublicKeyFromTrustStore(keyStore, "keyAlias");
# boolean validity = check crypto:verifyRsaSsaPss256Signature(data, signature, publicKey);
# ```
#
# + data - The content to be verified  as a byte array
# + signature - The signature value  as a byte array
# + publicKey - The public key used for verification
# + return - Validity of the signature or else a `crypto:Error` if the public key is invalid
public isolated function verifyRsaSsaPss256Signature(byte[] data, byte[] signature, PublicKey publicKey) returns boolean|Error;
````

### Implementation Architecture

The implementation follows the existing three-layer architecture:

1. **Ballerina API Layer** (`sign_verify.bal`):

   - Public functions with comprehensive documentation
   - Java method bindings using `@java:Method` annotation
   - Consistent parameter naming and return types

2. **Java Native Layer** (`Sign.java`):

   - Native methods following existing naming patterns
   - Direct algorithm string usage (no constants)
   - Consistent parameter extraction and validation

3. **Crypto Utilities Layer** (`CryptoUtils.java`):
   - Reuses existing `sign()` and `verify()` utility methods
   - Leverages established error handling patterns

### Technical Implementation Details

- **Algorithm String**: `"SHA256withRSAandMGF1"` (Java's standard RSASSA-PSS identifier)
- **PSS Parameters**: Uses Java's default RSASSA-PSS parameters:
  - Hash Algorithm: SHA-256
  - MGF: MGF1 with SHA-256
  - Salt Length: 32 bytes (same as SHA-256 hash length)
  - Trailer Field: 1 (standard value)
- **Key Compatibility**: Works with existing RSA private/public key infrastructure
- **Error Handling**: Follows existing error patterns and returns `crypto:Error` for invalid keys

### Naming Convention

The function names follow the established pattern:

- `signRsaSsaPss256`: Matches `signRsaSha256`, `signRsaSha512` pattern
- `verifyRsaSsaPss256Signature`: Matches `verifyRsaSha256Signature` pattern
- Uses `SsaPss` to clearly distinguish from traditional RSA signatures
- Includes `256` to specify the SHA-256 hash algorithm

## Risks and Assumptions

### Risks

1. **Java Version Compatibility**: RSASSA-PSS support requires Java 8+

   - **Mitigation**: Ballerina already requires Java 11+, so this is not a concern

2. **Performance Impact**: PSS signatures are computationally more expensive than PKCS#1 v1.5
   - **Mitigation**: Performance difference is minimal for typical use cases, and security benefits outweigh costs

### Assumptions

1. **RSA Key Compatibility**: Existing RSA keys work with RSASSA-PSS

   - **Validation**: Tested with existing test keys successfully

2. **Standard PSS Parameters**: Default Java PSS parameters meet most use cases

   - **Validation**: These parameters align with JWT PS256 and other standards

3. **Backward Compatibility**: New functions don't affect existing functionality
   - **Validation**: Only additive changes, no modifications to existing APIs

## Dependencies

### Internal Dependencies

- **CryptoUtils.java**: Reuses existing `sign()` and `verify()` methods
- **Sign.java**: Extends existing native implementation class
- **Constants.java**: Uses existing constant patterns (though not needed for algorithm string)
- **Error handling**: Leverages existing `crypto:Error` infrastructure

### External Dependencies

- **Java Cryptography Architecture (JCA)**: Uses `Signature.getInstance("SHA256withRSAandMGF1")`
- **Bouncy Castle**: May be used as JCA provider (already included in crypto module)

### Higher-Level Module Impact

This enhancement enables:

- **JWT module**: Can implement PS256 signature algorithm
- **OAuth/OIDC modules**: Can support PSS-based authentication
- **Security frameworks**: Can adopt more secure signature schemes

## Future Work

### Additional PSS Variants

Future enhancements could include:

- PS384 (RSASSA-PSS with SHA-384)
- PS512 (RSASSA-PSS with SHA-512)

### Custom PSS Parameters

If user demand exists, could add functions accepting custom PSS parameters:

- Custom salt lengths
- Different MGF functions
- Alternative hash algorithms
