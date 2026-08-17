# 1465: Zip library for Ballerina

- Authors - @niveathika
- Reviewed by - @daneshk
- Created date - 2026/08/14
- Updated date - 2026/08/17
- Issue - https://github.com/ballerina-platform/ballerina-spec/issues/1465
- State - Submitted

## Summary

This proposal introduces `ballerina/zip`, a new standard library for creating and reading ZIP archives. It offers a convenience API that covers the common cases in a single call, and an object API for working entry by entry. The public API is deliberately kept to a portable subset of the ZIP format so that the implementation underneath can be replaced without a breaking change.

## Motivation

Ballerina has no way to create or read a ZIP archive today. A user who needs one has three options: shell out to the `zip` command, write Java interop against a compression library, or avoid the problem.

This gap sits directly in the path of the file integration scenarios Ballerina is used for. Archives arrive over FTP, SFTP, S3, and SharePoint, and are routinely expected as output. `ballerina/file`, `ballerina/ftp`, and the cloud storage connectors all end at the archive boundary, leaving the user to cross it with interop.

## Goals

- Zip a file or directory, and extract an archive, in a single call.
- Read an archive entry by entry, including reading entry content as a stream.
- Create an archive entry by entry, from files, from bytes, or from a stream.
- Copy entries between archives without recompressing them.
- Be safe by default against path traversal, and offer limits on what an archive may cost to extract. What is reasonable to spend is left to the caller, since only the caller knows.
- Keep the public API implementation-agnostic, so the ZIP implementation underneath can change without affecting users.

## Non-Goals

- **Password-protected archives.** Neither reading nor writing. This would mean implementing ZipCrypto and AES rather than using a library feature, and it is not required by the scenarios driving this proposal.
- **Modifying an existing archive in place.** Adding, removing, or renaming an entry in an existing archive is out of scope for the first version. The archive is rebuilt instead, which `copyEntry` makes inexpensive.
- **An archive that is anything but a file path.** Neither an archive arriving as a `stream<byte[], Error?>` nor one held in a `byte[]` is accepted. Entry *content* streams in both directions; the archive itself does not. See Alternatives.
- **Format features outside the portable subset**: split archives, selecting a character set for entry names, tuning the Zip64 extension, and typed access to optional extra fields.
- **Other archive formats.** No tar, gzip, 7z, or rar.

## Design

The full specification is maintained with the library. This section covers the API surface and the decisions a reviewer needs to weigh.

### Two layers

The convenience API covers the common cases:

```ballerina
public isolated function compress(string sourcePath, string targetPath, CompressOptions options = {}) returns Error?;
public isolated function decompress(string sourcePath, string targetPath, DecompressOptions options = {}) returns Error?;
public isolated function listEntries(string path) returns Entry[]|Error;
```

```ballerina
check zip:compress("./reports", "./reports.zip");
check zip:decompress("./reports.zip", "./out");
```

The object API is for entry-level control. Reading and writing have separate types, because a ZIP archive is written in one forward pass and cannot be modified in place:

```ballerina
public class ArchiveReader {
    public isolated function init(string path) returns Error?;
    public isolated function entries() returns Entry[]|Error;
    public isolated function getEntry(string name) returns Entry|Error;
    public isolated function hasEntry(string name) returns boolean|Error;
    public isolated function readEntry(string name,
            typedesc<byte[]|stream<byte[], Error?>> targetType = <>) returns targetType|Error;
    public isolated function extractEntry(string name, string targetPath,
            DecompressOptions options = {}) returns Error?;
    public isolated function extractAll(string targetPath, DecompressOptions options = {}) returns Error?;
    public isolated function close() returns Error?;
}

public class ArchiveWriter {
    public isolated function init(string path, CompressOptions options = {}) returns Error?;
    public isolated function addFile(string sourcePath, string? entryName = ()) returns Error?;
    public isolated function addDirectory(string sourcePath, string? entryName = ()) returns Error?;
    public isolated function addEntry(string entryName,
            byte[]|stream<byte[], error?> content) returns Error?;
    public isolated function copyEntry(ArchiveReader sourceArchive, string entryName) returns Error?;
    public isolated function close() returns Error?;
}
```

The convenience functions are defined in terms of the object API, and both apply the same rules for names, security, and errors. Each convenience function opens what it needs and closes it before returning, including on the error path.

Every method of both classes is `isolated`. Neither class is. `ballerina/io` draws the line in the same place: none of its fifteen channel and stream classes is `isolated`, the readable ones included, while every method on them is.

The three reader functions that take a name are named for what they return: `getEntry` gives metadata, `readEntry` gives content, and `extractEntry` writes content to a file. `hasEntry` was added because the only way to test for an entry was to call the metadata function and match on `EntryNotFoundError`, which is control flow through an error for a question the in-memory index can answer directly.

An `entryName` given to `addDirectory` names the top level of the added tree and takes precedence over `includeSourceDirectory`, which shapes only a call that names nothing. The option is set once for the archive while the name is given per call, and `addFile` already treats a supplied name as overriding the derived one; ignoring the name when the option is off would let a caller pass an argument that silently does nothing. An empty directory is recorded as a directory entry wherever there is a top level to record it under, so a call that names nothing with the option off adds nothing.

### Entry metadata

```ballerina
public type Entry record {|
    string name;
    boolean isDirectory;
    boolean isSymlink;
    int uncompressedSize;
    int compressedSize;
    CompressionMethod method;
    time:Utc modifiedTime;
    int crc32;
    string comment?;
    int unixMode?;
|};
```

`entries()` returns an ordered array rather than a map, because the ZIP format permits two entries with the same name, and archives produced by other tools sometimes contain them. Keying by name would silently discard entries.

Every name-based method — `getEntry`, `hasEntry`, `readEntry`, `extractEntry`, and `copyEntry` — operates on the first entry with that name, so a later duplicate is visible through `entries()` but cannot be reached. Duplicate names indicate a malformed archive, so this version reports them rather than providing a way to address each one; an ordinal or handle is listed under Future Work.

Whole-archive extraction processes entries in stored order, so duplicates resolve by `fileWriteMode`: `FAIL_IF_EXISTS` fails on the second, `REPLACE` leaves the last, and `SKIP` keeps the first.

`fileWriteMode` answers for a file, and only for a file. Whatever the mode says, a directory already there is reused, and a file entry that would land on a directory gives a `FileSystemError`. There is no file there for the mode to answer for, and no mode may take a directory away.

`copyEntry` carries an entry across without decoding it, so content, compression method, timestamp, and checksum are preserved exactly and the writer's `level` does not apply. An entry this library cannot decompress can still be copied. An encrypted entry cannot, and gives an `UnsupportedEntryError`: a raw copy would have to carry the encryption flag across with the bytes, and not every targeted implementation can do that.

Entry names are decoded by the flag each entry carries: UTF-8 when set, CP437 when not, as the format specifies. CP437 maps all 256 byte values, so decoding always succeeds and every name has one definite value.

### Options and modes

```ballerina
public enum CompressionMethod { STORE, DEFLATE, OTHER }
public enum CompressionLevel { NONE, FASTEST, DEFAULT, BEST }
public enum FileWriteMode { FAIL_IF_EXISTS, REPLACE, SKIP }

public type CompressOptions record {|
    CompressionLevel level = DEFAULT;
    boolean includeSourceDirectory = true;
    boolean overwrite = false;
|};

public type DecompressOptions record {|
    FileWriteMode fileWriteMode = FAIL_IF_EXISTS;
    ExtractionLimits limits = {};
|};

public type ExtractionLimits record {|
    int maxEntries?;
    int maxTotalSize?;
    int maxCompressionRatio?;
|};
```

`CompressionMethod` carries `OTHER` so that an entry stored by a method this library does not decompress still has a value for `method`. Such an entry is listed and may be copied, so without it `entries()` could not describe an archive the API accepts. `OTHER` is never written by this library, and it says only that the method is one this library does not decompress, not which method it is; carrying the raw ZIP method number instead would expose a format detail no caller acts on.

Settings are carried in records so that deferred features can be added as optional fields in a minor release without breaking existing code.

### Errors

```ballerina
public type EntryErrorDetail record {
    string entryName;
};

public type Error distinct error;

public type InvalidArchiveError distinct Error;
public type EntryNotFoundError distinct Error;
public type UnsupportedEntryError distinct (Error & error<EntryErrorDetail>);
public type UnsafePathError distinct (Error & error<EntryErrorDetail>);
public type LimitExceededError distinct (Error & error<EntryErrorDetail>);
public type FileSystemError distinct Error;
```

Detail records are attached only to the errors that can arise while extracting a whole archive, where the caller has not named an entry and cannot otherwise tell which one failed. The rest carry nothing, because the entry or path involved is one the caller supplied. `FileSystemError` is the exception. It can arise while extracting a whole archive too, and then its message names the entry. It is not given a detail record because it also covers failures with no entry behind them, such as failing to create the target directory, so there is no name it could always carry.

Error messages are defined by the library. Messages from the implementation underneath are never passed through, so they stay stable if that implementation is replaced.

### Security

Two paths are involved when extracting, and only one of them is under the control of whoever built the archive. The directory the caller extracts into is theirs to choose and is unrestricted. The entry names inside the archive are checked.

Before anything is written, each entry's target path is resolved against the target directory, and extraction stops with an `UnsafePathError` if it falls outside. This covers `.` and `..` segments, absolute names, drive letters, empty names, names holding a `\` or a `:`, and a symbolic link along the resolved path pointing outside the target. A `:` is refused wherever it sits: at the front it names a drive, and anywhere else it names an NTFS alternate data stream, so `notes.txt:evil` would write a stream of `notes.txt` rather than a file of that name. The checks run on the decoded name, and an entry whose raw bytes hold a `\` or a zero byte is refused before decoding, so no name slips past by way of the character set. **The check always runs and cannot be disabled.**

The same rule runs in the other direction, so the library never writes a name it would refuse to extract, and a caller who supplies one gets an `UnsafePathError` rather than a silently corrected name. A name ending in `/` records a directory, which holds nothing, so `addFile` and `addEntry` refuse content given under such a name.

Symbolic links are never created during extraction, and an entry marked as a link gives an `UnsupportedEntryError`. This closes a known attack in which one entry is a link named `data` pointing at `/etc` and a second entry named `data/passwd` then writes outside the target. Links are skipped rather than followed when adding a directory, since a link can point anywhere on the disk, and one pointing back up its own tree would make the walk unbounded. A `sourcePath` the caller names is used as given, so a link to a directory adds the directory it points at.

`compress` refuses a target archive inside the source directory, which would be walked while being written and end up holding a partial copy of itself, and refuses a target that is the source itself, since under `overwrite` creating the writer would empty the file being archived.

Unix permissions are recorded but not applied. `addFile` and `addDirectory` store the mode of the source on Unix-like systems; an extracted file gets whatever permissions the platform gives a new file, and `Entry.unixMode` reports what the archive holds, including the setuid, setgid and sticky bits.

Extraction applies limits on entry count, total size, and per-entry compression ratio, measured against bytes actually written rather than the sizes the archive declares, since those can be untrue. For the same reason, opening an archive must not allocate from the entry count declared in its trailer. A write that would take the total past `maxTotalSize` is refused before it happens. An entry's ratio is its uncompressed bytes divided by the compressed bytes actually taken from the archive to produce them, worked out as the entry is read; an entry that no compressed byte has been taken from has no ratio, and neither has a directory entry. `maxEntries` counts every entry, including directories, duplicates, and entries skipped under `SKIP`. A limit is disabled by omission rather than by a zero value, and one that is not positive is a mistake in the call, so it gives a plain `Error`.

**No limit applies unless the caller sets one.** A ratio of two or three is ordinary, but a log file of repeating lines or a zero-padded file reaches into the thousands while being entirely honest, and an archive built to fill a disk looks no different, so any default either refuses real archives or admits real bombs. What the library guarantees on its own is therefore *where* files land, which no caller can switch off; *how much* is written is policy the caller sets. All three are expected to be set together for untrusted input: the ratio catches an archive built to expand, while `maxEntries` and `maxTotalSize` catch one that is merely enormous — ten thousand uncompressed one-gigabyte entries have a ratio of about one and will fill a disk whatever ratio is set. `extractEntry` takes the same options as `extractAll`, though only `maxCompressionRatio` can bear on one named entry.

### Memory and resources

Archive content is held in memory in full only when the caller asks for it: `readEntry` into a `byte[]`, or `addEntry` given one. Use a stream instead and only one chunk is held. The library places no ceiling on that choice, following `ballerina/io`, where `fileReadBytes` reads a whole file of any size. The extraction limits are the only ones the library imposes, and they bound what is written to disk; nothing caps how much memory a caller may ask for.

The index of entries is held in memory in both directions: read in full when an archive is opened, accumulated until `close` writes it. Its size depends on the number of entries and the length of their names, not on their content, and is therefore bounded by the size of the file, since every entry counted has a record physically present in it. The limits bound the work extraction does rather than the cost of opening, by which point the index is already in memory.

Creating a writer does not replace a file already at that path. It fails with a `FileSystemError` and leaves the file as it was, unless `overwrite` is set, and whether the path is free is decided by the operation that creates the file rather than by a check made beforehand, so nothing can appear in between. Under `overwrite` the file is truncated when the writer is created rather than on success, so a failure part way through leaves an invalid archive and the previous contents gone; callers who need the old file preserved write to a temporary path and move it into place.

`ArchiveReader` and `ArchiveWriter` each hold one open file until closed, and each belongs to one strand. Ballerina does not close them automatically, which is why the convenience API exists and is the recommended entry point for callers that do not need entry-level control.

An entry stream holds a read position of its own, and several may be open at once without interfering. One read to the end releases its position; one abandoned part way must be closed by the caller. Closing the `ArchiveReader` closes any that remain, after which reading from them returns an `InvalidArchiveError`.

### Portability

The public API is restricted to what every targeted ZIP implementation can do, so the implementation can be replaced without revising this design. The exclusions listed under Non-Goals follow from this rather than from a lack of time, and adding any one of them later requires confirming that every targeted implementation supports it.

Path safety, extraction limits, directory walking, and error mapping are implemented in Ballerina rather than natively, so that behaviour stays identical across implementations. `readEntry` is the one exception: dependently-typed functions must be `external`, so the choice between binding to `byte[]` and binding to a stream is resolved natively. `io:fileReadCsv` and `xlsx:parseSheet` are in the same position.

## Alternatives

**Java interop, per user.** Leaves each user to rediscover path-traversal and expansion-limit handling. Most will not, and the failure is silent until exploited.

**Wrap zip4j to gain password support.** zip4j is the only widely used Java library that reads and writes encrypted archives, so this would deliver passwords immediately. Rejected because it ties the implementation to one Java library, contradicting the portability goal, and because password support is not required by the driving scenarios. It remains available as future work.

**Expose the full surface of the underlying library.** Apache Commons Compress covers nearly all of the ZIP format, including typed extra fields, split output, and Zip64 modes. Exposing that surface would make the API larger, and each such feature would become a breaking change if the implementation is replaced.

**A single archive type with a mode, as `ballerina/xlsx` does with `Workbook`.** Rejected because that model suits a document that is loaded, changed, and saved. A ZIP archive is written in one forward pass and can be arbitrarily large, so a combined type would present methods that fail at runtime depending on how the object was created.

**Accepting the archive as a stream, or as a `byte[]`.** Ballerina is a cloud-native language and this is a fair thing to ask for: archives arrive in HTTP payloads and leave for object storage. It is rejected because of what a stream promises. A caller who passes one expects the data to be processed a chunk at a time with memory staying flat, and the ZIP format cannot honour that: the index sits at the end of the file, so reading anything means seeking to the end and then back, which a stream cannot do. Accepting one would mean buffering the whole archive before any work could start — the opposite of what was asked for. Reading front to back is possible in some implementations, but an entry's true size is then known only after its content has been written, so the extraction limits could not be applied in time; Go's `archive/zip` offers no stream reader at all. A `byte[]` would work for reading, since memory can be read in any order, but a writer produces an archive rather than consuming one, so only half the API could take it. Meanwhile a straight passthrough from HTTP to object storage needs no ZIP library, and any caller who does read or repack the archive has it fully resident regardless. Stated plainly: this library does not stream an archive, it streams entry content.

**Doing nothing.** Users continue to write interop, or shell out to the `zip` command, which is unavailable on minimal container images and returns no structured errors.

## Testing

- Unit tests for every public function, including each error type as a negative case.
- A conformance corpus of prepared archives pinning the behaviour specified for entry names and security: Zip64, names without the UTF-8 flag asserted to decode as CP437, duplicate names asserted to resolve to the first, directory entries with and without a trailing separator, symbolic links, empty files, an archive with a high expansion ratio, entries with `.` and `..` segments, absolute and drive-lettered names, and entries containing `\` or `:`. This corpus is the acceptance criterion for any change of the underlying implementation.
- Tests asserting that extraction limits are enforced against bytes written rather than declared sizes.
- Round-trip tests: create an archive, read it back, and verify names, sizes, checksums, and timestamps.
- Interoperability tests against archives produced by the `zip` command and by other libraries, and verification that archives produced by this library can be opened by those tools.
- GraalVM native-image tests, since the library declares `graalvmCompatible = true`.

## Risks and Assumptions

- **The API is capped at the portable subset.** If a targeted implementation is dropped or added, that subset changes. The assumption is that the cost of a smaller API is lower than the cost of a breaking change later.
- **Nothing bounds what an extraction costs unless the caller asks for it.** A caller who extracts an untrusted archive without setting any limit is exposed to one built to expand. The library cannot close this on their behalf without a number that would refuse honest archives, so it is answered by documentation and an example instead: the untrusted-archive example sets all three limits, and `LimitExceededError` names the entry at fault so a caller can tell a bad limit from an attack.
- **Refusing names containing `\` or `:` refuses some legitimate archives.** Both are valid characters in a Linux filename, and a `:` turns up in ordinary timestamped names. Refusing `\` follows Go. Both refusals are a deliberate trade: an archive then extracts the same way on every platform, rather than being safe only on the one it was tested on.
- **Refusing symbolic link entries refuses some legitimate archives**, notably ones produced by `zip` on Unix systems. Skipping them silently was considered worse, since files would go missing without explanation. The two directions differ deliberately: a link is skipped when adding, and refused when extracting. Skipping on the way in loses nothing the caller asked for, whereas refusing on the way out is what prevents an archive from writing outside the target.
- **An extracted file does not carry the mode the archive recorded**, so an executable comes out non-executable. `ballerina/file` has no way to set a mode, so a caller cannot correct this without their own interop.
- **Names without the UTF-8 flag are decoded as CP437 whatever they really are.** An archive written on a system using some third character set will produce the wrong text. No character set option is offered, so such callers have no recourse. This matches what other tools do, and every byte sequence decodes to something, so every archive has one defined interpretation.
- **Neither class is `isolated`, so two strands cannot share a reader or a writer.** A caller cannot reach one from an `isolated` function through a module-level variable, and cannot hand one to a `start` action from an isolated function. A service that works with archives for many requests opens one per request. The alternatives were worse: a qualifier the compiler would have accepted without being able to check it, on types that are not in fact safe to share, or a lock on every call — including every chunk read — for a kind of sharing this library does not offer.
- **Callers must close `ArchiveReader` and `ArchiveWriter` explicitly.** Ballerina has no scope-based resource release, so a forgotten `close` holds a file open. The convenience API avoids the problem for the common case; the object API cannot.

## Dependencies

The initial implementation depends on Apache Commons Compress as a native dependency. This is an implementation detail: no part of the public API exposes it, and the portability constraints above exist so it can be replaced.

## Future Work

- A batch operation for changing an existing archive, covering add, remove, and rename in a single rebuild.
- Password-protected archives, both reading and writing.
- Archive comments.
- Reading an archive held in memory rather than on disk, together with a way to write one, so that both halves of the API take the same shape.
- Progress reporting and cancellation for long-running operations.
- Applying Unix permissions when extracting.
- Storing symbolic links as links, rather than skipping them.
- An ordinal or handle for addressing a duplicate entry other than the first.

## References

- [Go `archive/zip`](https://pkg.go.dev/archive/zip)
- [Apache Commons Compress, ZIP package](https://commons.apache.org/proper/commons-compress/apidocs/org/apache/commons/compress/archivers/zip/package-summary.html)
- [zip4j](https://github.com/srikanth-lingala/zip4j)
- PKWARE APPNOTE, the ZIP file format specification
- [Zip Slip vulnerability](https://security.snyk.io/research/zip-slip-vulnerability)
