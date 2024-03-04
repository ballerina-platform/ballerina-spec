# Ballerina Test Framework Specification

# Introduction

Ballerina Language has a robust testing framework, which allows the user to test their code and verify that the module is behaving correctly. The test framework covers unit testing, integration testing, and end-to-end testing with the building blocks that the framework provides. The test framework also provides code coverage and test report generation. 


# Defining Tests


## Code Organization

In a Ballerina project, test cases are written in a separate directory/folder named tests within each module. The following is the basic structure of a Ballerina project.

```
project-name/
  - Ballerina.toml
  - modules/
    -- mymodule/
      --- Module.md      
      --- mymodule.bal       
      --- resources/     
      --- tests/           <- tests for a non-default module (e.g. unit tests)
        ---- lib_test.bal  <- test file for a non-default module
        ---- resources/    <- resources for these tests
  - main.bal
  - tests/              <- tests for the default module
    -- main_test.bal    <- test file for default module
    -- resources/       <- resources for these tests

```
In Ballerina testframework, tests are organized into per module test suites. The tests for a particular module should be added in a sub folder named `tests` within that module.
Tests defined outside the test directory will not get executed when executing tests for a Ballerina package/module.

### Visibility

The symbols defined in a module are accessible from within the test files of the same module. This includes globally-defined objects and variables.
 Hence, redefining a symbol in a test file is not allowed if it is already declared in the module. Instead, they can be reassigned in the test files.
 It must be noted that symbols defined in the test files will not be visible inside the module source files. 

### Test Resources

The test resources folder is meant to contain any files or resources that are required for testing. From the test
 code, test resources can be accessed using the absolute path or the path relative to the project root. 

## Writing Test Cases

A test case is a Ballerina function preceded by a test annotation which is provided by the `ballerina/test` module. The
 purpose of a test case is to test a particular functionality of the code. 

**Example**


```ballerina
@test:Config {}
function test1() {
    // Test code ...
}
```

### Annotations

Ballerina tests are defined using a set of annotations. The following are the annotations available in the test module
 along with their attributes.
 
<table>
  <tr>
   <td>@test:BeforeSuite {}
   </td>
   <td>Function specified will be run once before any of the tests in the test suite is run.
   </td>
  </tr>
  <tr>
   <td>@test:BeforeGroups {}
   </td>
    <td>Function specified will be run before any of the tests belonging to the specified groups are executed.
<p>
Annotation value fields :
<ul>

<li>groups : [“&lt;test group name&gt;”, ...] 
<ul>

<li>List of group names that this function should run before
</li> 
</ul>
</li> 
</ul>
   </td>
  </tr>
  <tr>
   <td>@test:BeforeEach {}
   </td>
   <td>Function specified will be run before every test when the test suite is run.
   </td>
  </tr>
  <tr>
   <td>@test:Config {}
   </td>
   <td>Function specified is considered as a test function.
<p>
Annotation value fields :
<ul>

<li>enable : { true | false } 
<ul>
 
<li>Enable or disable the test
 
<li>Default : true
</li> 
</ul>

<li>before : “&lt;function name&gt;” 
<ul>
 
<li>Name of the function to run before the test is run
</li> 
</ul>

<li>after : “&lt;function name&gt;” 
<ul>
 
<li>Name of the function to run after the test is run
</li> 
</ul>

<li>dependsOn : [“&lt;function name&gt;:”, … ] 
<ul>
 
<li>A list of function names on which the function depends on. These will be run before the test.
</li> 
</ul>

<li>dataProvider : “&lt;function name&gt;” 
<ul>
 
<li>Specifies the name of the function that will be used to provide the value sets to execute the test against
</li> 
</ul>

<li>groups : [“&lt;test group name&gt;”, ...] 
<ul>
 
<li>List of group names one or more that this test belongs to
</li> 
</ul>
</li> 
</ul>
   </td>
  </tr>
  <tr>
   <td>@test:AfterEach {}
   </td>
   <td>Function specified will be run after every test when the test suite is run.
   </td>
  </tr>
  <tr>
   <td>@test:AfterGroups {}
   </td>
    <td>Function specified will be run after all the tests belonging to the specified groups are executed.
<p>
Annotation value fields :
<ul>

<li>groups : [“&lt;test group name&gt;”, ...] 
<ul>

<li>List of group names that this function should run after
</li> 
</ul>
</li> 
</ul>
   </td>
  </tr>
  <tr>
   <td>@test:AfterSuite {}
   </td>
   <td>The function specified in the following annotation will be run once after all the tests in the test suite are run.
   </td>
  </tr>
</table>

### Assertions

The Ballerina test framework has built-in assertions, which enable users to verify an actual output against an expected output. 

The following are the list of available assertions available in the test framework.

<table>
  <tr>
   <td>@test:assertEquals(any|error actual, anydata expected, string message)
   </td>
   <td>Checks if the specified value is equal to the expected value. This assertion relies on `==` based deep equality check. 
For the deep equality check to be applicable, it is required that at least one of the participating operands is of a static type that is a subtype of `anydata`. 
Consequently, the permissible scope of the expected value is confined to `anydata` type.
   </td>
  </tr>
  <tr>
   <td>@test:assertNotEquals(any actual, anydata expected, string message)
   </td>
   <td>Checks if the specified value is not equal to the expected value. This assertion utilizes the != operator for a deep equality check, thus limiting the expected value to the `anydata` type.
The actual value does not include `error` type to avoid automatically passing the tests when there is an error.
This ensures that tests accurately reflect intended outcomes without misinterpreting errors as correct behavior.
   </td>
  </tr>
  <tr>
     <td>@test:assertExactEquals(any|error actual, any|error expected, string message)
     </td>
     <td>Checks if the specified value is exactly equal to the expected value i.e. both refer to the same entity. This assertion utilizes the === operator for an exact equality check.
     </td>
    </tr>
    <tr>
     <td>@test:assertNotExactEquals
     </td>
     <td>Checks if the specified value is not exactly equal to the expected value i.e. both do not refer to the same entity.
This assertion utilizes the === operator for an exact equality check.
     </td>
    </tr>
  <tr>
   <td>@test:assertTrue(boolean expression, string message)	
   </td>
   <td>Checks if the specified boolean expression is true.
   </td>
  </tr>
  <tr>
   <td>@test:assertFalse
   </td>
   <td>Checks if the specified boolean expression is false.
   </td>
  </tr>
  <tr>
   <td>@test:assertFail
   </td>
   <td>Forces a test case to fail. This assertion facilitate the failing of a test during its execution when a specific condition is not met.
   </td>
  </tr>
</table>

Each assertion allows providing an optional assertion failure message. 

**Example**


```ballerina
@test:Config {}
function testAssertIntEquals() {
    int answer = 0;
    int a = 5;
    int b = 3;
    answer = intAdd(a, b);
    test:assertEquals(answer, 8, msg = "int values not equal");
}
```


### Grouping Tests

Organizing tests into groups allows the user to run a specific group of tests using the `--groups` option. 

**Example**

```ballerina
@test:Config { groups: ['group1'] }
function test1() {
    // Test code ...
}
```

### Enabling / Disabling Tests

Individual test cases can be disabled by adding the `enable : false` option in the test config annotation. This makes sure that the particular test case is skipped when running the tests. 

```ballerina
@test:Config { enable : false }
function test1() {
    // Test code ...
}
```

When a test case is disabled, before and after functions specified in the test configurations and all the dependent
 test cases will be skipped. 


### Order of Execution

The `depends on` attribute allows the user to define a list of function names that the test function depends on. These
functions will be executed before the test execution. The order in which the comma-separated list of functions appears
has no prominence and thus will be executed in an arbitrary manner. This attribute can be used to ensure that the
tests are being executed in the expected order.


```ballerina
@test:Config { }
function test1() {
    // Test code ...
}

@test:Config { dependsOn: ["test1"] }
function test2() {
    // Test code ...
}
```

## Mocking

The mocking support in the Ballerina test framework provides capabilities to mock a function or an object for unit testing. 
The mocking feature can be used to control the behavior of functions and objects by defining return values or
 replacing the entire object/function with a user-defined equivalent. This feature will help the user to test the
  Ballerina code independently from other modules and external endpoints.


### Annotation

Initializing a function mock needs a preceding annotation in order to identify and replace the occurrence of the original function during compilation.

<table>
  <tr>
   <td>@test:Mock {}
   </td>
   <td>This annotation can be applied to either a function or a test:MockFunction intialization. When placed before a function, it identifies that function as a mock, which will be invoked whenever the original function is called.
 If it is a test:MockFunction initialization, the behaviour of the function needs to be stubbed in the test cases.

<p>
Annotation value fields :
<ul>

<li>moduleName 
<ul>
 
<li>Default : Uses the current module
 
<li>Name of the module where the function to be mocked resides in.
</li> 
</ul>

<li>functionName 
<ul>
 
<li>Name of the function to be mocked
</li> 
</ul>
</li> 
</ul>
   </td>
  </tr>
</table>

### Initialization

*   Mock object 

    ```ballerina
    http:Client mockClient = test:mock(http:Client, new MockHttpClient());
    ```

*   Mock function 
    
    Compile-time mocking

    ```ballerina
    @test:Mock { 
        functionName: "intializeClient" 
    }
    function getMockClient() returns http:Client|error {
        return test:mock(http:Client);
    }
    ```

    MockFunction based mocking

    ```ballerina
    @test:Mock {
        moduleName : "ballerina/io"
        functionName : "println"
    }
    test:MockFunction mockFunc1  = new();
    ```

### Features

**Default behavior**

If a mock object or a mock function initialization is used without registering any cases, the default behavior would be to throw a runtime exception. 

Using the available features, the user can stub with preferred behaviors for function calls and values for member
 variables (of objects) before testing the required function. 

#### Case A: Features available in object mocking

1. Provide a replacement mock object defined by the user at initialization.

   The MockClient serves as a custom mock object designed to replace the actual object.
   It allows for the implementation of only those member functions utilized within the module, acting as a test double. 
   Should there be an attempt to invoke any other member function of the MockClient, a runtime error will occur.

    ```ballerina
    http:Client mockClient = test:mock (http:Client, new MockClient());
    ```

2. If the function doesn't have a return type or has an optional return type, then do nothing. 
    
    ```ballerina
    test:prepare(mockClient).when("functionName").doNothing();
    ```

3. Provide a return value. The function call will return the specified value, regardless of the arguments' values.

    ```ballerina
    test:prepare(mockClient).when("functionName").thenReturn(5);
    ```

4. Provide a return value based on the arguments.  

    ```ballerina
    test:prepare(mockClient).when("functionName").withArguments(anydata...).thenReturn(5);
    ```

5. Mock the member variables of an object.

    ```ballerina
    test:prepare(mockClient).getMember("member").thenReturn(5);
    ```

6. Provide generalized inputs to accept any value for certain arguments.

   This feature can be used when there is a need to selectively differentiate the mock behavior for a set of arguments.

   ```ballerina
   test:prepare(mockClient).when("functionName").withArguments("/pets", test:ANY, ...).thenReturn(5);
   ```

7. Provide multiple return values to be returned sequentially for each function call

   This feature can be used when the arguments cannot be identified to differentiate the mock behavior based on
   the arguments.

   ```ballerina
   test:prepare(mockClient).when("functionName").thenReturnSequence(5, 10, 15);
   ```

#### Case B : Features available in MockFunction based function mocking 

1. Provide a replacement function body.

    ```ballerina
    test:when(mockFunc1).call("mockFuncName");
    ```

2. If the function doesn't have a return type, do nothing. 

    ```ballerina
    test:when(mockFunc1).doNothing();
    ```

3. Provide a return value.

    ```ballerina
    test:when(mockFunc1).thenReturn(5);
    ```

4. Provide a return value based on the input.

    ```ballerina
    test:when(mockFunc1).withArguments(anydata...).thenReturn(5);
    ```

5. If mocking should not take place, call the original function.

    ```ballerina
    test:when(mockFunc1).callOriginal();
    ```

6. Provide generalized inputs to accept any value for certain arguments.

  This feature can be used when there is a need to selectively differentiate the mock behavior for a set of arguments.

   ```ballerina
   test:when(mockFunc1).withArguments(test:ANY,...).thenReturn(5);
   ```

7. Provide multiple return values to be returned sequentially for each function call

   This feature can be used when the arguments cannot be identified to differentiate the mock behavior based on
   the arguments.
   
    ```ballerina
    test:when(mockFunc1).thenReturnSequence(5,6,0)
    ```

#### Case C : Features available in compile-time function mocking

1. Annotate a function as the mock function for a specific function.

This annotation replaces the usage of the original function with the mock function at compile time.

```ballerina
    @test:Mock { 
        moduleName: "client"
        functionName: "intializeClient" 
    }
    function getMockClient() returns http:Client|error {
        return test:mock(http:Client);
    }

```

#### Errors

The above cases can throw errors at the runtime for the following reasons:

*   All Cases - If the function is not available
*   Case A1
    *   If the function signatures are not equal
    *   If the corresponding functions are not found
*   Case A2, Case B2
    *   If the function has a return type specified in it
*   Case A3, Case B3
    *   If the return value does not match the function return type
*   Case A4, Case B4
    *   If the number/type of arguments provided do not match the function return type
    *   If the the return value does not match the function signature
*   Case A5
    *   If the object does not have a member variable of the specified name
    *   If the variable type does not match the return value
*   Case B1
    *   If the function signatures are not equal
    *   If the replacing mock function is not found
*   Case A7, Case B7
    *   If the number of function invocations is not equal to the number of 
        return values specified in the sequence
*   Case C1
    *   If the function is not available

#### Examples

**Case A**

The mocking examples are written to mock the HTTP calls of the following *main.bal* file.


```ballerina
    // main.bal
    import ballerina/http;
    
    http:Client clientEndpoint = check new ("https://api.chucknorris.io/jokes/");
    
    type Joke readonly & record {
        string value;
    };
    
    // This function performs a `get` request to the Chuck Norris API and returns a random joke 
    // with the name replaced by the provided name or an error if the API invocation fails.
    function getRandomJoke(string name) returns string|error {
        Joke joke = check clientEndpoint->get("/random");
        string replacedText = re `Chuck Norris`.replaceAll(joke.value, name);
        return replacedText;
    }

```

1. Provide a replacement mock object defined by the user

```ballerina
    // main_test.bal
    import ballerina/http;
    import ballerina/test;
    
    // An instance of this object can be used as the test double for the `clientEndpoint`.
    public client class MockHttpClient {
    
        remote function get(string path, map<string|string[]>? headers = (), http:TargetType targetType = http:Response) returns http:Response|anydata|http:ClientError {
            Joke joke = {"value": "Mock When Chuck Norris wants an egg, he cracks open a chicken."};
            return joke;
        }
    
    }
    
    @test:Config {}
    public function testGetRandomJoke() {
    
        // create and assign a test double to the `clientEndpoint` object
        clientEndpoint = test:mock(http:Client, new MockHttpClient());
    
        // invoke the function to test
        string|error result = getRandomJoke("Sheldon");
    
        // verify that the function returns the mock value after replacing the name
        test:assertEquals(result, "Mock When Sheldon wants an egg, he cracks open a chicken.");
    }
    
```

2. Provide a return value

```ballerina
    // main_test.bal
    import ballerina/http;
    import ballerina/test;
    
    @test:Config {}
    public function testGetRandomJoke() {
        // Create a default mock HTTP Client and assign it to the `clientEndpoint` object
        clientEndpoint = test:mock(http:Client);
    
        // Stub to return the specified mock response when the `get` function is called.
        test:prepare(clientEndpoint).when("get").thenReturn(getMockResponse());
    
        // Stub to return the specified mock response when the specified argument is passed.
        test:prepare(clientEndpoint).when("get").withArguments("/categories")
                .thenReturn(getCategoriesResponse());
    
        // Invoke the function to test.
        string|error result = getRandomJoke("Sheldon");
    
        // Verify the return value against the expected string.
        test:assertEquals(result, "When Sheldon wants an egg, he cracks open a chicken.");
    }
    
    // Returns a mock Joke to be used for the random joke API invocation.
    function getMockResponse() returns Joke {
        Joke joke = {"value": "When Chuck Norris wants an egg, he cracks open a chicken."};
        return joke;
    }
    
    // Returns a mock response to be used for the category API invocation.
    function getCategoriesResponse() returns string[] {
        return ["animal", "food", "history", "money", "movie"];
    }

```

3. If function doesn't have a return type or has an optional return type then do nothing 

```ballerina
    // main.bal
    import ballerina/email;
    
    email:SmtpClient smtpClient = check new ("localhost", "admin", "admin");
    
    // This function sends out emails to specified email addresses and returns an error if sending failed.
    function sendNotification(string[] emailIds) returns error? {
        email:Message msg = {
            'from: "builder@abc.com",
            subject: "Error Alert ...",
            to: emailIds,
            body: ""
        };
        return check smtpClient->sendMessage(msg);
    }

```

```ballerina
    // main_test.bal
    import ballerina/email;
    import ballerina/test;
    
    @test:Config {}
    function testSendNotification() {
        string[] emailIds = ["user1@test.com", "user2@test.com"];
    
        // Create a default mock SMTP client and assign it to the `smtpClient` object.
        smtpClient = test:mock(email:SmtpClient);
    
        // Stub to do nothing when the`send` function is invoked.
        test:prepare(smtpClient).when("sendMessage").doNothing();
    
        // Invoke the function to test and verify that no error occurred.
        test:assertEquals(sendNotification(emailIds), ());
    }

```

4. Mock member variables of an object

```ballerina
    // main.bal
    # A record that represents a Product.
    #
    # + code - Code used to identify the product
    # + name - Product Name
    # + quantity - Quantity included in the product
    public type Product record {|
        readonly int code;
        string name;
        string quantity;
    |};
    
    # A table with a list of Products uniquely identified using the code.
    public type ProductInventory table<Product> key(code);
    
    // This is a sample data set in the defined inventory.
    ProductInventory inventory = table [
        {code: 1, name: "Milk", quantity: "1l"},
        {code: 2, name: "Bread", quantity: "500g"},
        {code: 3, name: "Apple", quantity: "750g"}
    ];
    
    # This client represents a product.
    #
    # + productCode - An int code used to identify the product.
    public client class ProductClient {
        public int productCode;
    
        public function init(int productCode) {
            self.productCode = productCode;
        }
    }
    
    // The Client represents the product with the code `1` (i.e. "Milk").
    ProductClient productClient = new (1);
    
    # Get the name of the product represented by the ProductClient.
    #
    # + return - The name of the product
    public function getProductName() returns string? {
        if !inventory.hasKey(productClient.productCode) {
            return;
        }
        Product? product = inventory.get(productClient.productCode);
        return product is Product ? product.name : ();
    }

```

```ballerina
    // main_test.bal
    import ballerina/test;
    
    @test:Config {}
    function testMemberVariable() {
        int mockProductCode = 2;
        // Create a mockClient which represents product with the code `mockProductCode`
        ProductClient mockClient = test:mock(ProductClient);
        // Stub the member variable `productCode`
        test:prepare(mockClient).getMember("productCode").thenReturn(mockProductCode);
        // Replace `productClient` with the `mockClient`
        productClient = mockClient;
        // Assert for the mocked product name.
        test:assertEquals(getProductName(), "Bread");
    }

```

**Case B**

The mocking examples are written to mock the functions of the following *main.bal* file.

```ballerina
    // main.bal
    // This function returns the result provided by the `intAdd` function.
    public function addValues(int a, int b) returns int {
        return intAdd(a, b);
    }
    
    // This function adds two integers and returns the result.
    public function intAdd(int a, int b) returns int {
        return (a + b);
    }

```

1. Provide a replacement function body

```ballerina
    // main_test.bal
    import ballerina/test;
    
    @test:Mock {functionName: "intAdd"}
    test:MockFunction intAddMockFn = new ();
    
    @test:Config {}
    function testCall() {
        // Stub to call another function when `intAdd` is called.
        test:when(intAddMockFn).call("mockIntAdd");
        test:assertEquals(addValues(11, 6), 5, msg = "function mocking failed");
    }
        
    // The mock function to be used in place of the `intAdd` function
    public function mockIntAdd(int a, int b) returns int {
        return (a - b);
    }

```

2. Provide a return value

```ballerina
    // main_test.bal
    import ballerina/test;
    
    @test:Mock {functionName: "intAdd"}
    test:MockFunction intAddMockFn = new ();
       
    @test:Config {}
    function testReturn() {
        // Stub to return the specified value when the `intAdd` is invoked.
        test:when(intAddMockFn).thenReturn(20);

        test:assertEquals(addValues(10, 6), 20, msg = "function mocking failed");
        test:assertEquals(addValues(0, 0), -1, msg = "function mocking with arguments failed");
    }

```

3. Provide return value based on input

```ballerina
    // main_test.bal
    import ballerina/test;
    
    @test:Mock {functionName: "intAdd"}
    test:MockFunction intAddMockFn = new ();
       
    @test:Config {}
    function testReturn() {
        // Stub to return the specified value when the `intAdd` is invoked with the specified arguments.
        test:when(intAddMockFn).withArguments(0, 0).thenReturn(-1);
        test:when(intAddMockFn).withArguments(10, 6).thenReturn(20);

        test:assertEquals(addValues(10, 6), 20, msg = "function mocking failed");
        test:assertEquals(addValues(0, 0), -1, msg = "function mocking with arguments failed");
    }

```

4. If mocking should not take place, then call the real function

```ballerina
    // main_test.bal
    import ballerina/test;
    
    @test:Mock {functionName: "intAdd"}
    test:MockFunction intAddMockFn = new ();
    
    @test:Config {}
    function testCallOriginal() {
        // Stub to call another function when `intAdd` is called.
        test:when(intAddMockFn).call("mockIntAdd");
    
        test:assertEquals(addValues(11, 6), 5, msg = "function mocking failed");
    
        // Stub to call the original `intAdd` function.
        test:when(intAddMockFn).callOriginal();
        test:assertEquals(addValues(11, 6), 17, msg = "function mocking failed");
    }
    
    // The mock function to be used in place of the `intAdd` function
    public function mockIntAdd(int a, int b) returns int {
        return (a - b);
    }

```
   
4. If the function does not have a return type do nothing
 
```ballerina
    // main.bal
    import ballerina/io;
    
    public function func() {
        io:println("hello");
    }

```
```ballerina
    // main_test.bal
    import ballerina/test;
    
    @test:Mock {functionName: "func"}
    test:MockFunction funcMockFn = new ();
    
    @test:Config {}
    function testReturn() {
        func();
    }

```
    
## Running the Test Suite

Tests will be executed when the user can explicitly run the test command.

**Executing tests of a specific module**

```
$ bal test <module_name>
```

**Executing tests in the entire project**

```
$ bal test
```

Single test files can be executed as long as they are stand-alone files, and not within a Ballerina project.

```
$ bal test <test_file>.bal
```

**Executing Groups**

Execute grouped tests using the following command :

```
$ bal test  --groups <group1>,<group2>
```

### Startup order of module and the test suite

In Ballerina, there is a specific startup order attached to building modules. When building a module that contains tests, 
initialization of the module and the test suite happens sequentially in the following order:

1. Initialization of the module
2. Initialization of the test suite

### Execution of the test suite

Once the test suite is initialized, functions in the test suite are executed in the following order.

1. Execution of the `BeforeSuite` function
2. Execution of the `BeforeGroups` function
3. Execution of the `BeforeEach` function
4. Execution of before function (the function declared by the `before` field of `@test:Config` annotation)
5. Execution of the test function
6. Execution of the after function (the function declared by the `after` field of `@test:Config` annotation)
7. Execution of `AfterEach` function 
8. Execution of the `AfterGroups` function
9. Execution of the `AfterSuite` function

The test cases are executed in an arbitrary manner unless a particular order is defined
 using the `dependsOn` attribute within the test configurations. 

### Test Results

#### Test Statuses

The result of a test can be one of the following three statuses: 

1. **Pass** - Test is executed to the end without any exceptions thrown
2. **Fail** - Test throws an exception due an assertion failure or any other runtime exception
3. **Skipped** - Test is not executed due to failure of another test function on which it depends or due to an exception thrown from the before functions

A summary of the test statuses is printed in the console at the end of the test execution.
The final test result can be one of the two statuses: Passing or Failing. If all tests pass, then the test result is said to be Passing and if there are any failing tests, then the result is said to be failing.
Failing status can contain a combination of one or more failed tests and optionally skipped and passed tests.

#### Exit Code

The exit code of the test execution process can be two values: 0 or 1. Exit code 0 denotes the successful execution of the 
command while the exit code 1 denotes that the test execution contains exceptions. 
If the final result is Passing, the exit code will be 0, else the exit code will be set as 1.


#### Test Report

In addition to the results printed in the console, a test report can be generated by passing the flag `--test-report`
 to the test execution command. The generated file is in HTML format and link to the file will be printed in
   the console at the end of test execution.

The test report contains the total passed, failed and skipped tests of the entire project.

**Example** 

```
$ ballerina test --test-report
```

### Code Coverage

The test framework provides an option to analyze the code coverage of a Ballerina project. This feature provides details about coverage of program source code by the tests executed. 

When the `--code-coverage` flag is passed to the test execution command along with the `--test-report` flag, an HTML file will be generated at the end of the test execution. The generated file is an extended version of the test report.
In addition to the test results, this file contains details about source code coverage by tests that are calculated in three levels.

*   Project coverage
*   Module coverage
*   Individual source file coverage

The code coverage only includes the source files being tested and not any files under the `tests/` directory.

The link to the file will be printed in the console at the end of test execution.

**Example**

```
$ bal test --code-coverage --test-report    
```
