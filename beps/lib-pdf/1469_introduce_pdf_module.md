# Introduce PDF Module

- Authors
  - Yasan Punchihewa
- Reviewed by
- Created date
  - 2026-08-16
- Updated date
  - 2026-08-16
- Issue
  - [#1469](https://github.com/ballerina-platform/ballerina-spec/issues/1469)
- State
  - Submitted

## Summary

Ballerina had no way to produce a PDF — the universal delivery format for invoices, statements, reports, and confirmations — or to read data back out of one. This BEP documents the design of **`ballerina/pdf`**, a library module providing HTML-to-PDF conversion and PDF reading operations, implemented in [`module-ballerina-pdf`](https://github.com/ballerina-platform/module-ballerina-pdf) and released on [Ballerina Central](https://central.ballerina.io/ballerina/pdf/latest). The release is deliberately versioned 0.9.x rather than 1.0: the embedded HTML rendering engine — the majority of the module's code — is expected to be repackaged out of the module before the API is frozen at 1.0 (see [Risks and Assumptions](#risks-and-assumptions) and [Future Work](#future-work)); the public API documented here is not expected to change as a result. Conversion is performed entirely in-process: HTML — full documents, fragments, or messy real-world markup — is sanitized into a well-formed DOM (Jsoup), styled and laid out by a purpose-built CSS layout engine, and painted onto Apache PDFBox. The from-scratch renderer is a deliberate choice, not an accident: every mainstream JVM HTML-to-PDF engine is AGPL- or LGPL-licensed — AGPL is categorically incompatible with an Apache-2.0 library, and LGPL's relinking provision cannot be honored under the platform's distribution model, where dependency jars are bundled into the package and statically compiled into GraalVM native images. The public API is a single conversion function, `parseHtml(html, *ConversionOptions)`, plus six page-oriented reading functions for text extraction and page-to-image conversion, each accepting PDF bytes, a file path, or a URL. Conversion involves no external service, browser, or system-installed tool; the module's only network I/O is the explicit `url*` readers fetching exactly the URL they are given.

## Motivation

1. **Document generation is a core integration workload.** The canonical shape is fetch data → render a document → deliver it: an invoice attached to an email, a statement pushed to an SFTP drop, a report returned from an HTTP endpoint. Every ecosystem an integration developer might compare Ballerina against covers this: Python has WeasyPrint and ReportLab, Java has iText and openhtmltopdf, Node drives headless Chromium via Puppeteer. Ballerina — a language purpose-built for integration — had no way to produce a PDF at all.

2. **HTML/CSS is the natural authoring format for documents.** Report templates, statements, and formatted output already exist as HTML in most organizations — produced by designers, templating systems, or upstream services. A converter that accepts HTML means document *design* needs no new skill or toolchain, and the browser serves as the reference renderer for what the output should look like. The module was prompted by exactly this shape: a financial-services integration receiving credit-report HTML from one endpoint that had to deliver the equivalent PDF to another, entirely within the Ballerina application.

3. **The workarounds are poor.** Without this module, an application needing a PDF has three options, none good:
   - **Direct Java interop against a PDF library (PDFBox, iText):** these are typesetting APIs — the application hand-places every text run and rule at x/y coordinates. There is no HTML input, no layout engine, and hundreds of lines of drawing code per document template.
   - **Shelling out to an external converter (wkhtmltopdf, headless Chromium):** an external binary per platform, a large deployment footprint, process management from Ballerina by hand, and poor fit for containerized and GraalVM native-image deployment. wkhtmltopdf is additionally unmaintained upstream.
   - **A cloud conversion service:** the document content leaves the premises. For the workloads that most need PDF generation — financial, medical, HR — this is a hard compliance blocker, and it was an explicit constraint of the originating use case.

4. **Licensing is why this gap existed.** The established JVM HTML-to-PDF engines are all copyleft: iText's pdfHTML is AGPL, Flying Saucer and openhtmltopdf are LGPL, OpenPDF is LGPL/MPL. AGPL is categorically incompatible with an Apache-2.0 library; LGPL fails the platform's distribution model, where dependency jars ship bundled inside the package and are statically linked into GraalVM native images — a form in which the LGPL relinking provision cannot be satisfied. The absence of a permissively licensed JVM HTML renderer is the structural reason no `ballerina/pdf` existed; this module closes it with a custom CSS layout engine over Apache PDFBox (Apache-2.0), Jsoup (MIT), and htmlunit-cssparser (Apache-2.0).

5. **PDF reading completes the round trip.** Integrations receive PDFs as often as they produce them — attachments, incoming statements, scanned reports. Extracting per-page text (for indexing, validation, or LLM handoff) and rendering pages as images (for previews or OCR pipelines) are the two dominant read operations, and both previously required raw POI-style interop against PDFBox.

## Goals

* Convert HTML — full documents, fragments, and malformed real-world markup — to PDF bytes in-process, with output that visually matches the same HTML rendered in a browser within the documented CSS support matrix.
* Keep the API strictly general-purpose: page geometry (presets and custom dimensions), margins, CSS injection, custom font registration, and a page cap. Any specific use case is reached through configuration, never through use-case presets in the module.
* Honor the document's own styling, including CSS `@page` size and margin rules, with a clear precedence: explicit API option → document CSS → defaults.
* Perform all processing locally with no external service, browser, or system-tool dependency, suitable for environments with data-compliance restrictions.
* Produce deterministic output across environments: the renderer uses only explicitly registered fonts (bundled Liberation families plus consumer-supplied TTFs), never host system fonts.
* Ship an Apache-2.0-compatible dependency chain end to end.
* Provide page-oriented PDF reading — per-page text extraction and per-page PNG rendering — from in-memory bytes, local files, or URLs.
* Be safe for concurrent use from services: all functions are `isolated`, and a conversion shares no mutable state with any other.

## Non-Goals

The first release deliberately defers or excludes the following; deferrals are future work rather than permanently rejected (see [Future Work](#future-work)):

- **Full browser parity.** The renderer implements CSS 2.1 core layout (cascade and specificity, a broad selector set, block/inline/table/float layout, margin collapsing, relative and absolute positioning) plus selected CSS3 features (`border-radius`, `box-shadow`, `opacity`, `rgba()`). Flexbox and Grid currently fall back to block layout; generated content (`::before`/`::after`), `page-break-*` control, and `@font-face` are on the roadmap.
- **JavaScript execution.** The input is static HTML; scripts are not evaluated.
- **External resource fetching during rendering.** Images must be embedded as Base64 data URLs and fonts supplied as bytes; the conversion path performs no network I/O (only the explicit `url*` reading functions do).
- **Programmatic PDF authoring.** No drawing primitives, AcroForms, digital signatures, or encryption; HTML is the sole authoring surface.
- **PDF editing** — merging, splitting, watermarking, or in-place modification of existing documents.
- **Templating.** Producing the HTML (string templates, any template engine) happens before the module is invoked.

## Design

This section summarizes the architecture and API surface and the decisions behind them. The full normative specification, including every option's behavior and precedence rules, is maintained in the module repository: [Ballerina PDF Module Specification](https://github.com/ballerina-platform/module-ballerina-pdf/blob/main/docs/spec/spec.md).

### 1. Module overview

The package has two parts: a `ballerina/` module holding the public API and a `native/` Java subproject containing the engine. The engine has two independent halves:

- **The HTML-to-PDF converter** — a nine-stage pipeline: Jsoup lenient parse and sanitization into a W3C DOM → font registration → CSS parsing (`<style>` blocks, injected CSS, `@page`, `@media print`) → page geometry resolution → cascade (specificity- and source-order-correct, with `!important`, inline styles, presentational attributes, and inheritance) → box-tree construction (CSS 2.1 anonymous-block rules) → layout (block, inline, table, and float engines; margin collapsing; positioning) → geometric page breaking with an optional fit-to-`maxPages` uniform scale → painting onto PDFBox content streams (text with per-character glyph fallback, backgrounds, borders and radii, shadows, images, link annotations).
- **The PDF reader** — PDFBox's text stripper and page renderer behind loaders for bytes, files, and URLs. The two halves share only error construction; neither imports the other.

The layout engine is the module's differentiated asset: roughly 60% of the engine code is pure HTML/CSS/layout logic with no PDF dependency at all (see [Future Work](#future-work) on eventually extracting it). Where the renderer needed an algorithm — table column sizing, float placement, margin collapsing — it was implemented from the CSS specifications, using spec-compliant open engines (WeasyPrint in particular) as references for the algorithms, never as code sources.

### 2. Conversion API

```ballerina
public isolated function parseHtml(string html, *ConversionOptions options) returns byte[]|Error;
```

`ConversionOptions` is an included record parameter, so every option is a named argument at the call site; all options have defaults and the bare one-argument call is valid. The options are:

- **`pageSize`** — a preset (`A4`, `LETTER`, `LEGAL`) or custom point dimensions. Precedence: explicit option → CSS `@page size` → A4.
- **`margins`** — four sides in points, same precedence against `@page margin`, defaulting to zero.
- **`additionalCss`** — CSS injected on top of the document's own styles, so a consumer can restyle externally sourced HTML without touching its markup. This is the mechanism by which use-case-specific styling stays out of the module.
- **`customFonts`** — TTF fonts registered per conversion, each entry naming its CSS `font-family` and bold/italic variant flags.
- **`fallbackFontSize`** — the size used only where the document's CSS is silent (default 12pt, the CSS `medium`).
- **`maxPages`** — a page cap; content exceeding it is scaled uniformly to fit exactly, never truncated.

Invalid option values fail the conversion with a typed error rather than producing wrong output.

### 3. Fonts and determinism

The renderer never consults host system fonts: a document renders identically on a developer laptop, a CI runner, and a production container because the font set is exactly what was registered. The module bundles the Liberation Sans and Liberation Serif families (metrically compatible with Arial and Times New Roman, so the dominant web font stacks render correctly with no configuration) plus a symbols font for per-character glyph fallback. Consumer fonts supplement these via `customFonts`. Fonts are subset into the output PDF, keeping file sizes proportional to the glyphs actually used.

### 4. Reading API

```ballerina
public isolated function extractText(byte[] pdf) returns string[]|Error;
public isolated function toImages(byte[] pdf) returns string[]|Error;
```

plus `file*` and `url*` variants of each (`fileExtractText`, `urlExtractText`, `fileToImages`, `urlToImages`). All are page-oriented: one array element per page, in page order — text content for extraction, Base64-encoded PNG for image conversion. The URL loaders enforce http/https, timeouts, and content-type checks, but deliberately perform no private-address blocking: SSRF policy belongs to the consumer, which knows its network topology (no mainstream HTML-to-PDF or PDF library ships such blocking, and it breaks the legitimate internal-server case).

### 5. Errors

All operations return subtypes of a distinct base `Error`: `HtmlParseError` (input could not be parsed into a document), `RenderError` (layout/paint/generation failure, or invalid option values), and `ReadError` (corrupted, invalid, or inaccessible PDF input).

### 6. Concurrency and deployment

Every conversion constructs its own pipeline objects and PDFBox document; there is no shared mutable state, and all public functions are `isolated` — the module is safe under high-concurrency service workloads without pooling or locking. The conversion path avoids AWT so it stays GraalVM-native-image-friendly; the page-to-image reader necessarily uses `java.desktop` (PDFBox's renderer returns `BufferedImage`) and carries the corresponding native-image configuration.

### 7. Usage

```ballerina
import ballerina/io;
import ballerina/pdf;

public function main() returns error? {
    string html = check io:fileReadString("report.html");
    byte[] pdfBytes = check pdf:parseHtml(html,
        pageSize = pdf:LETTER,
        margins = {top: 72, right: 54, bottom: 72, left: 54},
        additionalCss = "body { font-family: sans-serif; }"
    );
    check io:fileWriteBytes("report.pdf", pdfBytes);
}
```

The originating integration shape — fetch HTML, convert, deliver — in full:

```ballerina
http:Client source = check new ("https://reports.internal.example");
string html = check source->/render/'report(id = reportId);
byte[] pdfBytes = check pdf:parseHtml(html);
check sftp->put("/outbound/report.pdf", pdfBytes);
```

## Alternatives

* **Wrap an existing JVM HTML-to-PDF engine (Flying Saucer, openhtmltopdf, OpenPDF, iText pdfHTML).** Rejected on licensing alone: AGPL is categorically incompatible, and LGPL's relinking provision cannot be honored under bundled-jar distribution and GraalVM static native-image linking. This constraint is load-bearing for the entire design — with it, a from-scratch renderer over PDFBox is not one option among several but the only path to shipping.
* **Drive headless Chromium.** Perfect fidelity, rejected on deployment: a several-hundred-megabyte per-platform browser binary, external process management, container and native-image hostility, and an ongoing patch treadmill. The module's contract — pure in-process JVM library — is exactly what this cannot offer.
* **Shell out to wkhtmltopdf.** Rejected: same external-binary problems, and the project is archived upstream with known unpatched CVEs in its embedded WebKit.
* **A cloud conversion connector.** Rejected as the primary answer: document content leaving the premises is a compliance blocker for the workloads that most need this module. (A connector to such services can always exist independently in `ballerinax`; it does not substitute for local conversion.)
* **A thin Ballerina wrapper over PDFBox's drawing API.** Rejected: wrong altitude. Coordinate-level typesetting pushes the entire layout problem onto every consumer; the value of the module is precisely that HTML *is* the layout language.
* **Markdown or a custom DSL as the input format.** Rejected: HTML is what upstream systems and designers already produce, and any simpler format is expressible as HTML trivially, not vice versa.

## Testing

The engine carries 381 JUnit tests across 21 classes: unit suites for the cascade (specificity, inheritance, shorthand expansion), selector matching (combinators, structural pseudo-classes, specificity computation), value parsing, color parsing, font resolution and metrics, box-tree construction (display mapping, anonymous-block wrapping), block/table/float layout, and page breaking — plus end-to-end conversion tests asserting valid PDF output, page counts, and text-extraction round-trips for tables, embedded images, links, positioning, margin collapsing, and every conversion option including `maxPages` scaling. The Ballerina module adds its own test suites over the public API, options, and error paths, and the module runs GraalVM native-image tests in CI per the library process. A known gap is golden-image visual regression testing — geometry is currently asserted at unit level on box coordinates rather than on rendered pixels (see [Future Work](#future-work)).

## Risks and Assumptions

* **Fidelity gap.** A custom renderer will trail browsers indefinitely. Documents relying on unimplemented features (Flexbox, Grid, generated content, `page-break-*` control) render degraded rather than failing. Mitigations: the reference target is CSS 2.1 core — which covers the report/invoice/statement class of documents the module exists for — the support matrix is documented, `additionalCss` provides a per-document escape hatch, and the gap list is an explicit, severity-ranked roadmap.
* **Maintenance surface.** Owning a CSS layout engine is a long-term commitment; it is the majority of the module's code. This is the accepted price of the licensing constraint, and the engine is the module's differentiated, potentially reusable asset rather than dead weight (see Future Work).
* **Memory.** A conversion holds the DOM, computed styles, box tree, and the full output PDF in memory simultaneously; very large documents scale accordingly. The Java layer already writes to a stream, so exposing streaming output later is additive.
* **URL loaders and SSRF.** The `url*` readers fetch what they are told to fetch; network policy is the consumer's responsibility and is documented as such.
* **The renderer lives inside the module repository.** As it grows toward browser-class capability, its size, release cadence, and reuse potential may outgrow a subdirectory of a stdlib module; the seams for extracting it are analyzed and staged in the module repository (see Future Work).

## Dependencies

* Apache PDFBox 3.0.4 (`pdfbox`, `pdfbox-io`, `fontbox`; Apache-2.0) — PDF generation and reading — with `commons-logging` 1.3.4 (Apache-2.0).
* Jsoup 1.18.3 (MIT) — lenient HTML parsing and sanitization into a W3C DOM.
* htmlunit-cssparser 4.5.0 (Apache-2.0) — CSS tokenization (cascade, selectors, and layout are the module's own).
* Bundled Liberation Sans/Serif font families and Noto Sans Symbols 2 (glyph fallback) — SIL OFL-1.1.
* No dependencies on other BEPs.

## Future Work

* **CSS coverage expansion**, in severity order from the module's gap analysis: `page-break-before/after/inside`, `box-sizing: border-box`, `::before`/`::after` with counters, table `rowspan`, `@font-face`, `background-size`/`position`/`repeat`, `text-align: justify`, honored `white-space`, then Flexbox, Grid, gradients, transforms, SVG, and bidirectional text.
* **Extracting the HTML rendering engine into a standalone library.** The engine is already correctly layered — the CSS, box-tree, and layout code has zero PDFBox dependency, and the remainder touches PDFBox only as a font-metrics handle and a paint target — but the seams (a font-metrics abstraction, a painter/output-device interface, an image-resource abstraction) are not yet declared as interfaces. Declaring them would let the engine be versioned and reused independently (for example, an HTML-to-image capability, or richer HTML processing elsewhere in the platform) and would let visual regression infrastructure live with the engine. A staged separation plan — in-repo seam hardening first, separate artifact only when a second consumer or release-cadence pressure justifies it — is maintained as an engineering primer in the module repository. This pending repackaging is why the module is released as 0.9.x: the 1.0 boundary is where the packaging decision is revisited, and the public API is not expected to change as a result.
* **Streaming output** — exposing the engine's existing `OutputStream` path through the Ballerina API for large documents.
* **Bounded reader resource limits** — a maximum download size for the `url*` readers, input page-count caps, and raster dimension caps for `toImages`, targeted before 1.0.
* **Page decoration** — headers, footers, and page numbers via `@page` margin boxes.
* **Golden-image visual regression testing** against browser-rendered references.
* **Unified font resolution** — merging the layout-time family chain and paint-time glyph fallback into a single pass.
* **Explicit `@page size` dimensions** (currently preset names only) and additional page-size presets.

## References

* [`ballerina/pdf` on Ballerina Central](https://central.ballerina.io/ballerina/pdf/latest)
* [Ballerina PDF Module Specification](https://github.com/ballerina-platform/module-ballerina-pdf/blob/main/docs/spec/spec.md)
* [Module repository: `ballerina-platform/module-ballerina-pdf`](https://github.com/ballerina-platform/module-ballerina-pdf)
* [Apache PDFBox](https://pdfbox.apache.org/)
* [Jsoup](https://jsoup.org/)
* [CSS 2.1 Specification (W3C)](https://www.w3.org/TR/CSS21/) — the renderer's normative layout reference
* [WeasyPrint](https://weasyprint.org/) — spec-compliant reference engine consulted for layout algorithms
