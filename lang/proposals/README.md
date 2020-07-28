# Proposals for new language features

This is a list of in-process proposals for major language features. Each proposal has an associated issue where comments can be made.
  
  * [Timestamp](timestamp/timestamp.md) a new `timestamp` basic type (issue [#287](https://github.com/ballerina-platform/ballerina-spec/issues/287))
  * [Immutable](immutable/immutable.md) improved treatement of immutability (issue [#338](https://github.com/ballerina-platform/ballerina-spec/issues/338))
  * [Non-cloning tables](tablenoclone/tablenoclone.md) an approach to tables which does not require a table to clone its members (issue [#47](https://github.com/ballerina-platform/ballerina-spec/issues/47))
  * [Distinct types](distinct/distinct.md) adds nominal typing for the object and error basic types (issue [#413](https://github.com/ballerina-platform/ballerina-spec/issues/413))
  * [Transactions](transaction/transaction.md) adds language support for transactions (issue [#267](https://github.com/ballerina-platform/ballerina-spec/issues/267))
  * [Isolated](isolated/isolated.md) adds support of _isolated_ functions, which works in conjunction with readonly types to enable concurrency safety (issue [#145](https://github.com/ballerina-platform/ballerina-spec/issues/145))

Inactive proposals:
  * [XML](xml/xml.md) revised design for `xml` basic type; mostly included in 2020R1 release
  * [Query](query/query.md) language-integrated query; partly in 2020R1 release; remainder tracked issue [#340](https://github.com/ballerina-platform/ballerina-spec/issues/340)
  * [Tables](table/table.md) rarlier approach to tables, in which the members of rows were cloned
