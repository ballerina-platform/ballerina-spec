Test-Case: error
Description: Test xml interpolated expression usage in namespace attribute values.
Labels: xml-template-expr, xml, raw-template-expr

public function main() {
    int|float|boolean|string|decimal someValue = true;
    xml content = xml `<b:BOOK xmlns:b="${someValue}"></b:BOOK>`; // @error xml template expressions are not allowed in namespace attribute values
    content = xml `<b:BOOK xmlns:b="prefix${someValue}suffix"></b:BOOK>`; // @error xml template expressions are not allowed in namespace attribute values
}

Test-Case: output
Description: Test the same xml namespace with different namespace prefix inside the interpolated expression
Labels: xml-template-expr, xml

import ballerina/io;
public function main() {
    xml content1 = xml `<x:BOOK xmlns:x="http://www.w3.org/TR/html4/}"></x:BOOK>`;
    xml content2 = xml `<b:BOOKs xmlns:b="http://www.w3.org/TR/html4/}">${content1}</b:BOOKs>`;
    io:println(content2); // @output <b:BOOKs xmlns:b="http://www.w3.org/TR/html4/}"><x:BOOK xmlns:x="http://www.w3.org/TR/html4/}"/></b:BOOKs>
}
// CDATA test

Test-Case: error
Description: Test the static type of the interpolated expressions in an attribute value not to be nil.
Labels: xml-template-expr, xml, raw-template-expr, nil-type

public function main() {
    () nilValue = ();
    int|float|boolean|string|decimal|() someValue1 = true;
    int?|float?|boolean?|string?|decimal? someValue2 = true;
    xml xmlValue = xml `<BOOK b="${()}"></BOOK>`; // @error static type of the expressions in attribute values should not be nil
    xmlValue = xml `<BOOK b="${nilValue}"></BOOK>`; // @error static type of the expressions in attribute values should not be nil
    xmlValue = xml `<BOOK b="${someValue1}"></BOOK>`; // @error static type of the expressions in attribute values should not be nil
    xmlValue = xml `<BOOK b="${someValue2}"></BOOK>`; // @error static type of the expressions in attribute values should not be nil
}

Test-Case: error
Description: Test the static type of the interpolated expressions in content not to be nil.
Labels: xml-template-expr, xml, raw-template-expr

public function main() {
    () nilValue = ();
    int|float|boolean|string|decimal|() someValue1 = true;
    int?|float?|boolean?|string?|decimal? someValue2 = true;
    xml xmlValue = xml `<BOOK>"${()}"</BOOK>`; // @error static type of the expressions in content should not be nil
    xmlValue = xml `<BOOK>"${nilValue}"</BOOK>`; // @error static type of the expressions in content should not be nil
    xmlValue = xml `<BOOK>"${someValue1}"</BOOK>`; // @error static type of the expressions in content should not be nil
    xmlValue = xml `<BOOK>"${someValue2}"</BOOK>`; // @error static type of the expressions in content should not be nil
}

Test-Case: error
Description: Test usage of interpolated expressions of nil type in xml comments
Labels: xml-template-expr, xml, xml:Comment

public function main() {
    int? firstExpr = 1;
    xml<xml:Comment> x3 = xml `<!--Comment${firstExpr}-->`; // @error int? type not allowed in xml comments
    xml<xml:Comment> x3 = xml `<!--Comment${()}-->`; // @error int? type not allowed in xml comments
}

Test-Case: error
Description: Test usage of interpolated expressions of nil type in xml processing instructions
Labels: xml-template-expr, xml, xml:ProcessingInstruction

public function main() {
    int? firstExpr = 1;
    xml<'xml:ProcessingInstruction> x4 = xml `<?xml version="${firstExpr}" encoding="UTF-8" ?>`; // @error int? type not allowed in xml comments
    xml<'xml:ProcessingInstruction> x4 = xml `<?xml version="${()}" encoding="UTF-8" ?>`; // @error int? type not allowed in xml comments
}

Test-Case: error
Description: Test usage of interpolated expressions of nil type in xml text
Labels: xml-template-expr, xml, xml:Text

public function main() {
    int? firstExpr = 1;
    xml<xml:Text> x4 = xml `text${firstExpr}`; // @error int? type not allowed in xml text
    xml<xml:Text> x4 = xml `text${()}`; // @error int? type not allowed in xml text
}

Test-Case: error
Description: Test usage of un-parsable xml content in xml template expression
Fail-Issue:
Labels: xml-template-expr, xml

public function main() {
    xml xmlValue = xml `<BOOK></BOOK`; // @error xml content is not parsable as gt token is missing
    xmlValue = xml `<Book price=65></Book>`; // @error xml content is not parsable as double quotes missing in attribute value
    xmlValue = xml `<-- comment -->`; // @error invalid comment as the exclamation is missing
    xmlValue = xml `<something?>`; // @error mismatching start and end tags as the question mark issing from start tag
    xmlValue = xml ```; // @error backtick is not allowed inside back tick String
}

Test-Case: output
Description: Test if the xml template expr within a const expr is readonly
Fail-Issue:
Labels: xml-template-expr, xml

import ballerina/io;

 const map<anydata> m = {
        xmlVal : xml `<Book/>`
};

public function main() {
    io:println(m["xmlVal"] is readonly); // @output true
}

Test-Case: output
Description: Test empty string in xml text.
Labels: xml-template-expr, xml, xml:Text, value:toBalString

import ballerina/io;

public function main() {
    xml text = xml ``;
    io:println(text.toBalString()); // @output xml``
}

Test-Case: output
Description: Test usage of interpolated expressions in xml comments.
Labels: xml-template-expr, xml, xml:Comment

import ballerina/io;

public function main() {
    int firstExpr = 1;
    xml<xml:Comment> x3 = xml `<!--Comment${firstExpr}-->`;
    io:println(x3); // @output <!--Comment1-->
}

Test-Case: output
Description: Test the order of the interpolated expressions appear in the xml attributes values after the xml is
             contructed.
Labels: xml-template-expr, xml, raw-template-expr

import ballerina/io;

public function main() {
    int firstExpr = 1;
    int secondExpr = 2;
    int thirdExpr = 3;
    xml content = xml `<BOOK price="${firstExpr}${secondExpr}${thirdExpr}"></BOOK>`;
    io:println(content); // @output <BOOK price="123"/>

    content = xml `<BOOK price="1231${firstExpr}6321${secondExpr}.33${thirdExpr}"></BOOK>`;
    io:println(content); // @output <BOOK price="1231163212.333"/>
}

Test-Case: output
Description: Test the order of the interpolated expressions appear in the xml content after the xml is contructed.
Labels: xml-template-expr, xml, xml:Element, raw-template-expr

import ballerina/io;

public function main() {
    int firstExpr = 1;
    int secondExpr = 2;
    int thirdExpr = 3;
    xml content = xml `<BOOK>"${firstExpr}${secondExpr}${thirdExpr}"</BOOK>`;
    io:println(content); // @output <BOOK>"123"</BOOK>

    content = xml `<BOOK>"1231${firstExpr}6321${secondExpr}.33${thirdExpr}"</BOOK>`;
    io:println(content); // @output <BOOK>"1231163212.333"</BOOK>
}

Test-Case: output
Description: Test the order of the interpolated expressions appear in both the xml content and attribute values after
             the xml is contructed.
Labels: xml-template-expr, xml, xml:Element

import ballerina/io;

public function main() {
    int firstExpr = 1;
    int secondExpr = 2;
    int thirdExpr = 3;
    xml content = xml `<BOOK price="${firstExpr}">"${secondExpr}${thirdExpr}"</BOOK>`;
    io:println(content); // @output <BOOK price="1">"23"</BOOK>

    content = xml `<BOOK price="1231${firstExpr}">"1231${firstExpr}6321${secondExpr}.33${thirdExpr}"</BOOK>`;
    io:println(content); // @output <BOOK price="12311">"1231163212.333"</BOOK>
}

Test-Case: output
Description: Test usage of interpolated expressions of int type in xml text.
Labels: xml-template-expr, xml, xml:Text, int

import ballerina/io;

public function main() {
    int firstExpr = 1;
    xml<xml:Text> x = xml `text${firstExpr}`;
    io:println(x); // @output text1

    x = xml `text${1}`;
    io:println(x); // @output text1
}

Test-Case: output
Description: Test usage of interpolated expressions of float type in xml text.
Labels: xml-template-expr, xml, xml:Text, float

import ballerina/io;

public function main() {
    float firstExpr = 1.0;
    xml<xml:Text> x = xml `text${firstExpr}`;
    io:println(x); // @output text1.0

    x = xml `text${1.0}`;
    io:println(x); // @output text1.0
}

Test-Case: output
Description: Test usage of interpolated expressions of decimal type in xml text.
Labels: xml-template-expr, xml, xml:Text, decimal

import ballerina/io;

public function main() {
    decimal firstExpr = 1.0;
    xml<xml:Text> x = xml `text${firstExpr}`;
    io:println(x); // @output text1.0

    x = xml `text${1.0d}`;
    io:println(x); // @output text1.0
}

Test-Case: output
Description: Test usage of interpolated expressions of boolean type in xml text.
Labels: xml-template-expr, xml, xml:Text, boolean

import ballerina/io;

public function main() {
    boolean firstExpr = true;
    xml<xml:Text> x = xml `text-${firstExpr}`;
    io:println(x); // @output text-true

    x = xml `text-${true}`;
    io:println(x); // @output text-true
}

Test-Case: output
Description: Test usage of interpolated expressions of string type in xml text.
Labels: xml-template-expr, xml, xml:Text, string

import ballerina/io;

public function main() {
    string firstExpr = "stringVal";
    xml<xml:Text> x = xml `text-${firstExpr}`;
    io:println(x); // @output text-stringVal

    x = xml `text-${"stringVal"}`;
    io:println(x); // @output text-stringVal

    string:Char char = "C";
    x = xml `text-${char}`;
    io:println(x); // @output text-C
}

Test-Case: output
Description: Test usage of interpolated expressions of type int in xml comments.
Labels: xml-template-expr, xml, xml:Comment, int

import ballerina/io;

public function main() {
    int firstExpr = 1;
    xml<xml:Comment> x3 = xml `<!--Comment${firstExpr}-->`;
    io:println(x3); // @output <!--Comment1-->

    xml<xml:Comment> x3 = xml `<!--Comment${1}-->`;
    io:println(x3); // @output <!--Comment1-->
}

Test-Case: output
Description: Test usage of interpolated expressions of float type in xml comment.
Labels: xml-template-expr, xml, xml:Comment, float

import ballerina/io;

public function main() {
    float firstExpr = 2.0;
    xml<xml:Comment> x = xml `<!--Comment${firstExpr}-->`;
    io:println(x); // @output <!--Comment2.0-->

    x = xml `<!--Comment${2.0}-->`;
    io:println(x); // @output <!--Comment2.0-->
}

Test-Case: output
Description: Test usage of interpolated expressions of decimal type in xml comment.
Labels: xml-template-expr, xml, xml:Comment, decimal

import ballerina/io;

public function main() {
    decimal firstExpr = 2.0;
    xml<xml:Comment> x = xml `<!--Comment${firstExpr}-->`;
    io:println(x); // @output <!--Comment2.0-->

    x = xml `<!--Comment${2.0d}-->`;
    io:println(x); // @output <!--Comment2.0-->
}

Test-Case: output
Description: Test usage of interpolated expressions of boolean type in xml comment.
Labels: xml-template-expr, xml, xml:Comment, boolean

import ballerina/io;

public function main() {
    boolean firstExpr = false;
    xml<xml:Comment> x = xml `<!--Comment${firstExpr}-->`;
    io:println(x); // @output <!--Commentfalse-->

    x = xml `<!--Comment${false}-->`;
    io:println(x); // @output <!--Commentfalse-->
}

Test-Case: output
Description: Test usage of interpolated expressions of string type in xml comment.
Labels: xml-template-expr, xml, xml:Comment, string

import ballerina/io;

public function main() {
    string firstExpr = "stringVal";
    xml<xml:Comment> x = xml `<!--Comment${firstExpr}-->`;
    io:println(x); // @output <!--CommentstringVal-->

    x = xml `<!--Comment${"stringVal"}-->`;
    io:println(x); // @output <!--CommentstringVal-->

    string:Char char = "C";
    x = xml `<!--${char}omment-->`;
    io:println(x); // @output <!--Comment-->
}

Test-Case: output
Description: Test usage of interpolated expressions of xml type in xml content.
Fail-Issue:
Labels: xml-template-expr, xml, xml:Element

import ballerina/io;

public function main() {
    int|decimal|float|string|boolean firstExpr = 34;
    xml<xml:Element> secondExpr = xml `<Book>"${firstExpr}"</Book>`;
    xml<xml:Element> x = xml `<Books>${secondExpr}</Books>`;
    io:println(x); // @output <Books><Book>"34"</Book></Books>

    x = xml `<Books>${xml `<Book>"${firstExpr}"</Book>`}</Books>`;
    io:println(x); // @output <Books><Book>"34"</Book></Books>
}

Test-Case: output
Description: Test usage of queries as interpolated expressions in xml content.
Fail-Issue:
Labels: xml-template-expr, xml, query-expr

import ballerina/io;

public function main() {
    xml x = xml `<Books>${xml `<Book>"${from var char in "Ballerina" select char}"</Book>`}</Books>`;
    io:println(x); // @output <Books><Book>"Ballerina"</Book></Books>

    xml y = xml `<Books>${xml `<Book author="${from var char in "James" select char}">"Ballerina"</Book>`}</Books>`;
    io:println(y); // @output <Books><Book author="James">"Ballerina"</Book></Books>

    xml<xml:Comment> z = xml `<!--${from var char in "James" select char}-->`;
    io:println(z); // @output <!--James-->

    xml<xml:Text> text = xml `${from var char in "James" select char}`;
    io:println(text); // @output James
}

Test-Case: output
Description: Test usage of let expressions as interpolated expressions in xml content.
Fail-Issue:
Labels: xml-template-expr, xml, let-expr

import ballerina/io;

public function main() {
    xml x = xml `<Books>${xml `<Book>"${let int y = 5 in y}"</Book>`}</Books>`;
    io:println(x); // @output <Books><Book>"5"</Book></Books>

    xml<xml:Comment> c = xml `<!--${let string name = "James" in name}-->`;
    io:println(c); // @output <!--James-->

    xml z = xml `<Books>${xml `<Book author="${let string name = "James" in name}">"Ballerina"</Book>`}</Books>`;
    io:println(z); // @output <Books><Book author="James">"Ballerina"</Book></Books>

    xml<xml:Text> text = xml `${let string name = "James" in name}`;
    io:println(text); // @output James
}

Test-Case: output
Description: Test usage of field access expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, field-access-expr

import ballerina/io;

type Book record {
    string name;
    float price;
    string author;
};

public function main() {
    Book book = {name : "Ballerina", price: 20.0, author: "James"};

    xml x = xml `<Books>${xml `<Book>"${book.name}"</Book>`}</Books>`;
    io:println(x); // @output <Books><Book>"Ballerina"</Book></Books>

    xml<xml:Comment> y = xml `<!--${book.author}-->`;
    io:println(y); // @output <!--James-->

    xml z = xml `<Books>${xml `<Book author="${book.author}">"${book.name}"</Book>`}</Books>`;
    io:println(z); // @output <Books><Book author="James">"Ballerina"</Book></Books>

    xml<xml:Text> text = xml `${book.author}`;
    io:println(text); // @output James
}

Test-Case: error
Description: Test usage of optional field access expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, optional-field-access-expr

type Book record {
    string name;
    float price;
    string author;
    string coAuthor?;
};

public function main() {
    Book book = {name : "Ballerina", price: 20.0, author: "James", coAuthor: "Sanjiva"};

    xml x = xml `<Books>${xml `<Book>"${book?.coAuthor}"</Book>`}</Books>`; // @error static type of the interpolated expressions in xml content should not be nil
    xml<xml:Comment> y = xml `<!--${book?.coAuthor}-->`; // @error static type of the interpolated expressions in comments should not be nil
    xml z = xml `<Books>${xml `<Book author="${book?.coAuthor}">"${book.name}"</Book>`}</Books>`; // @error static type of the expressions in attribute values should not be nil
    xml<xml:Text> text = xml `${book?.coAuthor}`; // @error static type of the interpolated expressions in xml text should not be nil
}

Test-Case: error
Description: Test usage of member access expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, member-access-expr

type Book record {
    readonly string name;
    float price;
    string author;
};

float[] prices = [23.0, 45.0, 23.56];

map<string> authors = {
    "author1" : "James",
    "author2" : "Sanjiva"
};

table<Book> key<string> tbl = table key(name) [{name: "Ballerina", price: 45.0, author: "James"}];

public function main() {
    xml x = xml `<Books>${xml `<Book>"${tbl["Ballerina"]?.name}"</Book>`}</Books>`; // @error static type of the interpolated expressions in xml content should not be nil
    xml<xml:Comment> y = xml `<!--${authors["author1"]}-->`; // @error static type of the interpolated expressions in comments should not be nil
    xml z = xml `<Books>${xml `<Book author="${authors["author1"]}"></Book>`}</Books>`; // @error static type of the expressions in attribute values should not be nil
    xml<xml:Text> text = xml `${authors["author2"]}`; // @error static type of the interpolated expressions in xml text should not be nil
}

Test-Case: output
Description: Test usage of function call expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, function-call-expr

import ballerina/io;

public function main() {
    xml x = xml `<Books>${xml `<Book>"${getBookName()}"</Book>`}</Books>`;
    io:println(x); // @output <Books><Book>"Ballerina"</Book></Books>

    xml<xml:Comment> y = xml `<!--${getAuthorName()}-->`;
    io:println(y); // @output <!--James-->

    xml z = xml `<Books>${xml `<Book author="${getAuthorName()}">${getPrice()}</Book>`}</Books>`;
    io:println(z); // @output <Books><Book author="James">"23.0"</Book></Books>

    xml<xml:Text> text = xml `${getAuthorName()}`;
    io:println(text); // @output James
}

function getBookName() returns string {
    return "Ballerina";
}

function getAuthorName() returns string {
    return "James";
}

function getPrice() returns float {
    return 23.0;
}

function getCoAuthor() returns string {
    return "Sanjiva";
}

Test-Case: error
Description: Test usage of function call expressions which can return nil values as interpolated expressions in xml content.
Labels: xml-template-expr, xml, function-call-expr, nil-type

public function main() {
    xml x = xml `<Books>${xml `<Book>"${getBookName()}"</Book>`}</Books>`; // @error static type of the interpolated expressions in xml content should not be nil
    xml<xml:Comment> y = xml `<!--${getAuthorName()}-->`; // @error static type of the interpolated expressions in comments should not be nil
    xml z = xml `<Books>${xml `<Book author="${getAuthorName()}">${getPrice()}</Book>`}</Books>`; // @error static type of the expressions in attribute values should not be nil
    xml<xml:Text> text = xml `${getAuthorName()}`; // @error static type of the interpolated expressions in xml text should not be nil
}

function getBookName() returns string? {
    return "Ballerina";
}

function getAuthorName() returns string? {
    return "James";
}

function getPrice() returns float? {
    return 23.0;
}

function getCoAuthor() returns string? {
    return "Sanjiva";
}

Test-Case: output
Description: Test usage of method call expressions as interpolated expressions in xml content
Labels: xml-template-expr, xml, method-call-expr, string:toUpperAscii, module-class-defn

import ballerina/io;

class MyClass {
    function getAuthorName() returns string {
        return "James";
    }

    function getPrice() returns float {
        return 23.0;
    }
}

public function main() {
    MyClass myClass = new;

    xml x = xml `<Books>${xml `<Book>"${"ballerina".toUpperAscii()}"</Book>`}</Books>`;
    io:println(x); // @output <Books><Book>"Ballerina"</Book></Books>

    xml<xml:Comment> y = xml `<!--${myClass.getAuthorName()}-->`;
    io:println(y); // @output <!--James-->

    xml z = xml `<Books>${xml `<Book author="${myClass.getAuthorName()}">${myClass.getPrice()}</Book>`}</Books>`;
    io:println(z); // @output <Books><Book author="James">"23.0"</Book></Books>

    xml<xml:Text> text = xml `${myClass.getAuthorName()}`;
    io:println(text); // @output James
}

Test-Case: output
Description: Test usage of multiplicative expressions as interpolated expressions in xml content
Labels: xml-template-expr, xml, multiplicative-expr

import ballerina/io;

public function main() {
    xml z = xml `<Books>${xml `<Book>${23.0 * 1.0}</Book>`}</Books>`;
    io:println(z); // @output <Books><Book>"23.0"</Book></Books>

    float a = 23.0;
    float b = 1.0;
    z = xml `<Books>${xml `<Book>${a * b}</Book>`}</Books>`;
    io:println(z); // @output <Books><Book>"23.0"</Book></Books>
}

Test-Case: output
Description: Test usage of additive expressions as interpolated expressions in xml content
Labels: xml-template-expr, xml, additive-expr

import ballerina/io;

public function main() {
    xml z = xml `<Books>${xml `<Book>${23.0 + 1.0}</Book>`}</Books>`;
    io:println(z); // @output <Books><Book>"24.0"</Book></Books>

    float a = 23.0;
    float b = 1.0;
    z = xml `<Books>${xml `<Book>${a + b}</Book>`}</Books>`;
    io:println(z); // @output <Books><Book>"24.0"</Book></Books>
}

Test-Case: output
Description: Test usage of relational expressions as interpolated expressions in xml content
Labels: xml-template-expr, xml, relational-expr

import ballerina/io;

public function main() {

    float a = 23.0;
    float b = 1.0;
    xml z = xml `<A>${xml `<B>${a > b}</B>`}</A>`;
    io:println(z); // @output <A><B>true</B></A>

    z = xml `<A>${xml `<B>${a < b}</B>`}</A>`;
    io:println(z); // @output <A><B>false</B></A>

    z = xml `<A>${xml `<B>${a >= b}</B>`}</A>`;
    io:println(z); // @output <A><B>true</B></A>

    z = xml `<A>${xml `<B>${a <= b}</B>`}</A>`;
    io:println(z); // @output <A><B>false</B></A>
}

Test-Case: output
Description: Test usage of transactional expressions as interpolated expressions in xml content
Fail-Issue:
Labels: xml-template-expr, xml, transactional-expr

import ballerina/io;

public function main() {

    float a = 23.0;
    float b = 1.0;
    xml z = xml `<A>${xml `<B>${transactional}</B>`}</A>`;
    io:println(z); // @output <A><B>false</B></A>
}

Test-Case: output
Description: Test usage of conditional expressions as interpolated expressions in xml content
Labels: xml-template-expr, xml, conditional-expr

import ballerina/io;

public function main() {

    float a = 23.0;
    float b = 1.0;
    xml z = xml `<A>${xml `<B>${a > b ? a : b}</B>`}</A>`;
    io:println(z); // @output <A><B>false</B></A>
}

Test-Case: output
Description: Test usage of string template expressions as interpolated expressions in xml content
Labels: xml-template-expr, xml, string-template-expr

import ballerina/io;

public function main() {

    float a = 23.0;
    float b = 1.0;
    xml z = xml `<A>${xml `<B>${string `${b} some string ${a}`}</B>`}</A>`;
    io:println(z); // @output <A><B>1.0 some string 23.0</B></A>
}

Test-Case: error
Description: Test usage of structural constructor expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, list-constructor-expr

public function main() {
    xml z = xml `<A>${xml `<B>${[0, 2, 1, 4, 5]}</B>`}</A>`; // @error structural constructor expressions are not allowed in interpolated expressions
}

Test-Case: error
Description: Test usage of new expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, new-expr

public function main() {
    xml z = xml `<A>${xml `<B>${new stream<record{}>}</B>`}</A>`; // @error new expressions are not allowed in interpolated expressions
}

Test-Case: output
Description: Test usage of check expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, check-expr

import ballerina/io;

public function main() returns error? {
    int|error val = foo();
    xml z = xml `<A>${xml `<B>${check foo()}</B>`}</A>`;
    io:println(z); // @output <A><B>23</B></A>
}

function foo() returns error|int {
    return 23;
}

Test-Case: output
Description: Test usage of check expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, check

import ballerina/io;

public function main() returns error? {
    int|error val = foo();
    xml z = xml `<A>${xml `<B>${check foo()}</B>`}</A>`;
    io:println(z); // @output <A><B>23</B></A>
}

function foo() returns error|int {
    return 23;
}

Test-Case: output
Description: Test usage of checkpanic expressions as interpolated expressions in xml content.
Fail-Issue:
Labels: xml-template-expr, xml, checkpanic

import ballerina/io;

public function main() {
    int|error val = foo();
    xml z = xml `<A>${xml `<B>${checkpanic foo()}</B>`}</A>`;
    io:println(z); // @output <A><B>23</B></A>
}

function foo() returns error|int {
    return 23;
}

Test-Case: error
Description: Test usage of typeof expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, typeof-expr

public function main() {
    int x = 9;
    xml z = xml `<A>${xml `<B>${typeof x}</B>`}</A>`; // @error typeof expressions are not allowed in interpolated expressions
}

Test-Case: output
Description: Test usage of unary expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, unary-complement, unary-minus, unary-plus, unary-not

import ballerina/io;

public function main() {
    int x = 9;
    xml z = xml `<A>${xml `<B>${-x}</B>`}</A>`;
    io:println(z); // @output <A><B>-9</B></A>

    z = xml `<A>${xml `<B>${+x}</B>`}</A>`;
    io:println(z); // @output <A><B>9</B></A>

    z = xml `<A>${xml `<B>${~x}</B>`}</A>`;
    io:println(z); // @output <A><B>-10</B></A>

    boolean b = true;
    z = xml `<A>${xml `<B>${!b}</B>`}</A>`;
    io:println(z); // @output <A><B>false</B></A>
}


Test-Case: error
Description: Test usage of range expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, range-expr

public function main() {
    int x = 9;
    xml z = xml `<A>${xml `<B>${0 ... x}</B>`}</A>`; //@error range expressions are not allowed in interpolated expressions
    z = xml `<A>${xml `<B>${0 ..< x}</B>`}</A>`; //@error range expressions are not allowed in interpolated expressions
}


Test-Case: output
Description: Test usage of binary bitwise expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, binary-bitwise-expr

import ballerina/io;

public function main() {
    int x = 9;
    int y = 23;
    xml z = xml `<A>${xml `<B>${x | y}</B>`}</A>`;
    io:println(z); // @output <A><B>31</B></A>

    z = xml `<A>${xml `<B>${x & y}</B>`}</A>`;
    io:println(z); // @output <A><B>1</B></A>

    z = xml `<A>${xml `<B>${x ^ y}</B>`}</A>`;
    io:println(z); // @output <A><B>30</B></A>
}

Test-Case: output
Description: Test usage of type test expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, is-expr

import ballerina/io;

public function main() {
    int|string x = 9;
    xml z = xml `<A>${xml `<B>${x is string}</B>`}</A>`;
    io:println(z); // @output <A><B>false</B></A>
}


Test-Case: output
Description: Test usage of equality expressions as interpolated expressions in xml content.
Labels: xml-template-expr, xml, equality, exact-equality

import ballerina/io;

public function main() {
    int x = 9;
    int y = 9;
    int s = 2;
    xml z = xml `<A>${xml `<B>${x == y}</B>`}</A>`;
    io:println(z); // @output <A><B>true</B></A>

    z = xml `<A>${xml `<B>${x != s}</B>`}</A>`;
    io:println(z); // @output <A><B>true</B></A>

    z = xml `<A>${xml `<B>${x === y}</B>`}</A>`;
    io:println(z); // @output <A><B>true</B></A>

    z = xml `<A>${xml `<B>${x !== s}</B>`}</A>`;
    io:println(z); // @output <A><B>true</B></A>
}

Test-Case: output
Description: Test with CDATA in xml content.
Fail-Issue:
Labels: xml-template-expr, xml

import ballerina/io;

public function main() {
    int x = 9;
    int y = 9;
    int s = 2;
    xml z = xml `<exampleOfACDATA><![CDATA[character data]]></exampleOfACDATA>`;
    io:println(z); // @output <exampleOfACDATA><![CDATA[character data]]></exampleOfACDATA>
}
