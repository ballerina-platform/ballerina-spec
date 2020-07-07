# Ballerina Test Framework Specification

**Contributors** :
Joseph Fonseka, Asma Jabir, Aquib Zulfikar, Fathima Dilhasha


# Introduction

Ballerina Language has a robust testing framework that allows the user to test their code and verify that the module is behaving correctly. The test framework covers unit testing, integration testing and end-to-end testing with the building blocks that the framework provides. The test framework also provides code coverage and test report generation. 


# Defining Tests


## Code Organization

In a Ballerina project, test cases are written in a separate directory/folder named tests within each module. The following is the basic structure of a Ballerina project.

```
project-name/
  - Ballerina.toml
  - src/
    -- mymodule/
      --- Module.md      
      --- main.bal       
      --- resources/     
      --- tests/           <- tests for this module (e.g. unit tests)
        ---- main_test.bal <- test file for main
        ---- resources/    <- resources for these tests
```


The Ballerina test framework will only execute tests defined inside the `tests/` directory of a module. Tests defined
 outside the test directory will not get executed when building the Ballerina project. Test files can be put into subdirectories within the tests folder much like a Ballerina module.


### Visibility

The symbols defined in a module are accessible from within the test files. This includes globally defined objects and variables. Hence, redefining a symbol in a test file is not allowed if it is already declared in the module. Instead they can be reassigned in test files. It must be noted that symbols defined in the test files will not be visible inside the module source files. 

### Test Resources

The test resources folder is meant to contain any files or resources that are required for testing. From the test
 code, test resources can be accessed using the absolute path or the path relative to the project root. 

## Writing Test Cases

A test case is a Ballerina function preceded by a test annotation which is provided by the _ballerina/test_ module. The
 purpose of a test case is to test a particular functionality of the code. 

**Example**


```ballerina
@test:Config {}
function test1() {
    // Test code ...
}
```

### Annotations

Ballerina tests are defined using a set of annotations. Following are the annotations available in the test module
 along with their attributes.
 
<table>
  <tr>
   <td>@test:BeforeSuite {}
   </td>
   <td>Function specified will be run once before any of the tests in the test suite is run
   </td>
  </tr>
  <tr>
   <td>@test:BeforeEach {}
   </td>
   <td>Function specified will be run before every test when the test suite is run
   </td>
  </tr>
  <tr>
   <td>@test:Config {}
   </td>
   <td>Function specified is considered as a test function
<p>
Annotation value fields :
<ul>

<li>enable : { true | false } 
<ul>
 
<li>Enable or disable test
 
<li>Default : true
</li> 
</ul>

<li>before : “&lt;function name&gt;” 
<ul>
 
<li>Name of function to run before the test is run
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
 
<li>List of group names, one or more, that this test belongs to
</li> 
</ul>
</li> 
</ul>
   </td>
  </tr>
  <tr>
   <td>@test:AfterSuite {}
   </td>
   <td>The function specified in the following annotation will be run once after all the tests in the test suite is run.
   </td>
  </tr>
</table>

### Assertions

The Ballerina test framework has built-in assertions that enable users to verify an actual  output against an expected output. 

The following are the list of available assertions available in the test framework.

<table>
  <tr>
   <td>@test:assertEquals
   </td>
   <td>Checks if the specified value is equal to the expected value
   </td>
  </tr>
  <tr>
   <td>@test:assertNotEquals
   </td>
   <td>Checks if the specified value is not equal to the expected value
   </td>
  </tr>
  <tr>
   <td>@test:assertTrue
   </td>
   <td>Checks if the specified value is true
   </td>
  </tr>
  <tr>
   <td>@test:assertFalse
   </td>
   <td>Checks if the specified value is false
   </td>
  </tr>
  <tr>
   <td>@test:assertFail
   </td>
   <td>Forces a test case to fail
   </td>
  </tr>
</table>


Each assertion allows providing an optional assertion fail message. 

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

The depends on attribute allows the user to define a list of function names that the test function depends on. These
functions will be executed before the test execution. The order in which the comma separated list of functions appears
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


### Mock Annotation

Initializing a function mock needs a preceding annotation in order to identify and replace the occurrence of the original function during compilation.

This annotation is only required when mocking functions since a part of function mocking is handled in compile time. Mocking an object is completely handled in the runtime and therefore, this annotation is not required when initializing a mock for an object.

<table>
  <tr>
   <td>@test:Mock {}
   </td>
   <td>The function specified will be considered as a mock function that gets triggered every time the original function is called. 
<p>
Annotation value fields :
<ul>

<li>moduleName 
<ul>
 
<li>Default : Uses the current module
 
<li>Name of the module where the function to be mocked resides in
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
    http:Client mockClient = <http:Client> test:mock(http:Client, mockObj = new);
    ```

*   Mock function 

    ```ballerina
    @test:Mock {
        moduleName : "ballerina/io"
        functionName : "println"
    }
    test:MockFunction mockFunc1  = new();
    ```

### Features

**Default behavior**

If a mock object or function is used without registering any cases, the default behavior would be to throw a runtime exception. 

Using the available features, the user can stub with preferred behaviors for function calls and values for member
 variables (of objects) before testing the required function. 


#### Case A: Features available in object mocking

**Basic Cases**


1. Provide a replacement mock object defined by the user at initialization

    ```ballerina
    http:Client mockClient = <http:Client> test:mock (http:Client, mockClient);
    ```

2. If function doesn't have a return type or has an optional return type then do nothing 
    
    ```ballerina
    test:prepare(mockClient).when("functionName").doNothing();
    ```

3. Provide a return value

    ```ballerina
    test:prepare(mockClient).when("functionName").thenReturn(5);
    ```

4. Provide return value based on input

    ```ballerina
    test:prepare(mockClient).when("functionName").withArguments(anydata...).thenReturn(5);
    ```
   
5. Mock member variables of an object

    ```ballerina
    test:prepare(mockClient).getMember("member").thenReturn(5);
    ```

#### Case B : Features available in function mocking 

1. Provide a replacement function body

    ```ballerina
    test:when(mockFunc1).call("mockFuncName");
    ```

2. If function doesn't have a return type do nothing 

    ```ballerina
    test:when(mockFunc1).doNothing();
    ```

3. Provide a return value

    ```ballerina
    test:when(mockFunc1).thenReturn(5);
    ```

4. Provide return value based on input

    ```ballerina
    test:when(mockFunc1).withArguments(any...).thenReturn(5);
    ```

5. If mocking should not take place, call the real function

    ```ballerina
    test:when(mockFunc1).callRealFunction();

    ```

**Advance Cases**

6. Provide generalized inputs to accept any value for certain arguments
    
   ```ballerina
   test:prepare(mockClient).when("functionName").withArguments("/pets", test:ANY, ...).thenReturn(5);
   ```
   ```ballerina
   test:when(mockFunc1).withArguments(test:ANY,...).thenReturn(5);
    ```

7. Provide multiple return values to be returned sequentially for each function call

    ```ballerina
    test:when(mockFunc1).thenReturnSequence(5,6,0)
    ```

#### Errors

The cases can throw errors at the runtime for following reasons:

*   All Cases - If the function is not available in the mocked type
*   Case A1
    *   If function signatures are not equal
    *   If corresponding functions are not found
*   Case A2, Case B2
    *   If the function has a return type specified
*   Case A3, Case B3
    *   If the the return value does not match the function return type
*   Case A4, Case B4
    *   If the number/type of arguments provided does not match the function return type
    *   If the the return value does not match the function signature
*   Case A5
    *   If the object does not have a member variable of specified name
    *   If the variable type does not match the return value
*   Case B1
    *   If function signatures are not equal
    *   If the replacing mock function is not found

#### Examples

**Case A**

The mocking examples are written to mock the http calls of the following _main.bal_ file.


```ballerina
    // main.bal
    http:Client petStoreClient = new("http://petstore.com");
    email:SmtpClient smtpClient = new ("localhost", "admin","admin");

    // performs a get request and returns the Pet object or an error
    function getPet(string petId) returns Pet | error {
      http:Response|error result = petStoreClient->get("/pets?id="+petId);
      if(result is error) {
    	return result;
      } else {
          Pet pet = constructPetObj(result); 
    	return pet;
      }
    }

    // sends an email and optionally returns an error if sending fails
    function sendEmail() returns email:Error? {
       email:SmtpClient smtpClient = new(
       config:getAsString("MAIL_SMTP_HOST"),
       config:getAsString("MAIL_SMTP_AUTH_USERNAME"),
       config:getAsString("MAIL_SMTP_AUTH_PASSWORD")


       //create email
       email:Email msg = {
         'from: "builder@test.com",
         to: "dev@test.com",
         subject: "#54 - Build Failure",
         body: ""
       };

       // send email
       email:Error? response = smtpClient->send(msg);
       if (response is email:Error) {
          string errMsg = <string> response.detail()["message"];
          log:printError("error while sending the email: " + errMsg);
          return response;
       }
    }

```

1. Provide a replacement mock object defined by the user

    ```ballerina
    // main_test.bal
    // Mock object definition
    public type MockHttpClient client object {
       public remote function get(@untainted string path, public http:RequestMessage message = ()) returns http:Response|http:ClientError {
          http:Response res = new;
          res.statusCode = 500;
          return res;
       }
    };

    @test:Config {}
    function testGetPet() {
       // 1) create and assign mock to global http client
       petStoreClient = <http:Client>mock(http:Client, new MockHttpClient());

       // 2) invoke getPet function
       http:Response res = getPet("D123");
       test:assertEquals(res.statusCode, 500);
    }
    ```


2. Provide a return value

    ```ballerina
    // main_test.bal
   
    @test:Config {}
    function testGetPet2() {
       // 1) create mock
       http:Client mockHttpClient = <http:Client>mock(http:Client);
       http:Response mockResponse = new;
       mockResponse.statusCode = 500;
   
       test:prepare(mockHttpClient).when("get").thenReturn(mockResponse);

       // 2) assign mock to global http client
       petStoreClient = mockHttpClient;

       // 3) invoke getPet function
       http:Response res = getPet("D123");
       test:assertEquals(res.statusCode, 500);
    }

    @test:Config {}
    function testGetPet2WithArgs() {
       // 1) create mock
       http:Client mockHttpClient = <http:Client>mock(http:Client);
       http:Response mockResponse = new;
       mockResponse.statusCode = 500;

       test:prepare(mockHttpClient).when("get").withArguments("/pets?id=D123", test:ANY).thenReturn(mockResponse);

       // 2) assign mock to global http client
       petStoreClient = mockHttpClient;

       // 3) invoke getPet function
       http:Response res = getPet("D123");
       test:assertEquals(res.statusCode, 500);
    }
    ```

3. If function doesn't have a return type or has an optional return type then do nothing 

    ```ballerina
    // main_test.bal
    @test:Config {}
    function testSendEmail() {
       email:SmtpClient mockSmtpCl = <email:SmtpClient>mock(email:SmtpClient);
       test:prepare(mockSmtpCl).when("send").doNothing();

       smtpClient = mockSmtpCl;
       error? sendResult = sendEmail();
       test:assertTrue(sendResult is ());
    }
    ```

4. Mock member variables of an object

    ```ballerina
    // main_test.bal
    test:prepare(mockHttpClient).getMember("method").thenReturn("get");

    ```

### Case B

1. Provide a replacement function body

    ```ballerina
    // main.bal
    public function printMathConsts() {
       io:println("Value of PI : ", math:PI);
       io:println("Value of E  : ", math:E);
    }

    // main_test.bal
    @test:Mock { functionName : "io:println" }
    test:MockFunction mockIoPrintLnFunc = new();

    string[] logs = [];

    function mockIoPrintLn(string text) {
     logs.push(text);
    }

    @test:Config {}
    function testMathConsts() {
       test:when(mockIoPrintLnFunc).call("mockIoPrintLn");

       // Invoke the printMathConsts function
       printMathConsts();

       string out1 = "Value of PI : 3.141592653589793";
       string out2 = "Value of E  : 2.718281828459045";

       test:assertEquals(outputs[0], out1);
       test:assertEquals(outputs[1], out2);
    }
    ```

2. Provide a return value
    
    ```ballerina
    // main.bal
    public function calculateAvg(int a, int b) returns int {
        log:printDebug("Calling intAdd function to add the provided integers");
        return intAdd(a, b)/2;
    }
        
    public function intAdd(int a, int b) returns int {
        return a + b;
    }
    ```
   
   ```ballerina
    // main_test.bal
    @test:Mock { functionName : "intAdd" }
    test:MockFunction mockIntAddFunc = new();

    @test:Config {}
    function testCalculateAvg() {
       test:when(mockIntAddFunc).thenReturn(10);

       // Invoke the calculateAvg function
       int average1 = calculateAvg(6,5);
       int average2 = calculateAvg(8,7);

       test:assertEquals(average1, 5);
       test:assertEquals(average2, 5);
    }
   ```

3. Provide return value based on input

    ```ballerina
	// main.bal
    public function calculateAvg(int a, int b) returns int {
       log:printDebug("Calling intAdd function to add the provided integers");
       return intAdd(a, b)/2;
    }

    public function intAdd(int a, int b) returns int {
       return a + b;
    }
    ```
    ```ballerina
    // main_test.bal
    @test:Mock { functionName : "intAdd" }
    test:MockFunction mockIntAddFunc = new();

    @test:Config {}
    function testCalculateAvg() {
       test:when(mockIntAddFunc).withArguments(6,5).thenReturn(10);
       test:when(mockIntAddFunc).withArguments(6,-5).thenReturn(0);

       // Invoke the calculateAvg function
       int average1 = calculateAvg(6,5);
       int average2 = calculateAvg(6,-5);

       test:assertEquals(average1, 5);
       test:assertEquals(average2, 0);
    }
    ```

4. If the function does not have a return type do nothing
 
    ```ballerina
    // main.bal
    public function calculateAvg(int a, int b) returns int {
       log:printDebug("Calling intAdd function to add the provided integers");
       return intAdd(a, b)/2;
    }

    public function intAdd(int a, int b) returns int {
       return a + b;
    }
    ```
    ```ballerina
    // main_test.bal
    @test:Mock { functionName : "log:printDebug" }
    test:MockFunction mockLogPrintDebugFunc = new();

    @test:Config {}
    function testCalculateAvg() {
       test:when(mockLogPrintDebugFunc).doNothing();

       // Invoke the calculateAvg function
       int average2 = calculateAvg(9,7);
       test:assertEquals(average2, 8);
    }

    ```

5. If mocking should not take place, then call the real function

    ```ballerina
    // main.bal
    public function calculateAvg(int a, int b) returns int {
       log:printDebug("Calling intAdd function to add the provided integers");
       return intAdd(a, b)/2;
    }

    public function intAdd(int a, int b) returns int {
       return a + b;
    }
    ```
    ```ballerina
    // main_test.bal
    @test:Mock { functionName : "intAdd" }
    test:MockFunction mockIntAddFunc = new();

    @test:Config {}
    function testCalculateAvg() {
       // return a specific value when intAdd is called
       test:when(mockIntAddFunc).thenReturn(10);
       int average1 = calculateAvg(6,8);
       test:assertEquals(average1, 5);
       
       // call the real function when intAdd is called
       test:when(mockIntAddFunc).callRealFunction();
       int average2 = calculateAvg(6,8);
       test:assertEquals(average2, 7);
    }
    ```
    
## Running the Test Suite

Tests will be automatically executed when you run the build command or the user can explicitly run them using the test command. Running the test command will exit the process once the tests are executed whereas running the build command will continue to generate the executables after executing the tests.

**Executing tests of a specific module**

```
$ ballerina build <module_name>
```
```
$ ballerina test <module_name>
```

**Executing tests in the entire project**

```
$ ballerina test --all
```
```
$ ballerina build --all
```
Single test files can be executed as long as they are stand-alone files, and not within a Ballerina project. This is
 only supported with the test command.

```
$ ballerina test <test_file>.bal
```

**Executing Groups**

Execute grouped tests using the following command :

```
$ ballerina build  --groups <group name> <module_name>
```
```
$ ballerina test  --groups <group name> <module_name>
```


**Execution with Test Configuration**

```
$ ballerina build <module_name> --b7a.config.file=<path_to_config_file>
```
```
$ ballerina test <module_name> --b7a.config.file=<path_to_config_file>
```

### Startup order of module and the test suite

In Ballerina, there is a specific startup order attached to building modules. When building a module that contains tests, 
initialization of the module and the test suite happens sequentially in the following order:

1. Initialization of the module
2. Initialization of the test suite

### Execution of the test suite

Once the test suite is initialized, functions in the test suite are executed in the following order.

1. Execution of the `BeforeSuite` function
2. Execution of the `BeforeEach` function
3. Execution of before function (the function declared by the `before` field of `@Config` annotation)
4. Execution of the test function
5. Execution of the after function (the function declared by the `after` field of `@Config` annotation)
6. Execution of `AfterEach` function
7. Execution of the `AfterSuite` function

The test cases are executed in an arbitrary manner unless a particular order is defined
 using the `dependsOn` attribute within the test configurations. After executing a test function, regardless of the
  test status, the `after` function and the `AfterEach` functions are executed before moving on to the next test function.


### Test Results

#### Test Statuses

The result of a test can be one of the following three statuses: 

1. **Pass** - Test is executed to the end without any exceptions thrown
2. **Fail** - Test throws an exception due an assertion failure or any other runtime exception
3. **Skipped** - Test is not executed due to failure of another test function on which it depends or due to an exception thrown from the before functions

A summary of the test statuses is printed in the console at the end of the test execution. This displays the passed tests with the prefix `[pass]` and the failed tests with the prefix `[fail]` followed by the exception thrown that caused the failure.

The final test result can be one of the two statuses: Passing or Failing. If all tests pass, then the test result is said to be Passing and if there are any failing tests, then the result is said to be failing. Failing status can contain a combination of one or more failed tests and optionally skipped and passed tests.


#### Exit Code

The exit code of the test execution process can be two values: 0 or 1. Exit code 0 denotes the successful execution of the 
command while the exit code 1 denotes that the test execution contains exceptions. 
If the final result is Passing, the exit code will be 0, else the exit code will be set as 1.


#### Test Report

In addition to the results printed in the console, a test report can be generated by passing the flag `--test-report`
 to the test execution command. This flag is supported with both  `ballerina
  build` and `ballerina test` commands. The generated file is in HTML format and link to the file will be printed in
   the console at the end of test execution.

The test report contains the total passed, failed and skipped tests of the entire project and of individual modules.

**Example** 

```
$ ballerina build --test-report <module_name> [args]
```
```
$ ballerina test --test-report <module_name> [args]
```

### Code Coverage

The test framework provides an option to analyze the code coverage of a Ballerina project. This feature provides details about coverage of program source code by the tests executed. 

When the `--code-coverage` flag is passed to the test execution command, an HTML file will be generated at the end of the test execution. The generated file is an extended version of the test report. In addition to the test results, this file contains details about source code coverage by tests that are calculated in three levels.

*   Project coverage
*   Module coverage
*   Individual source file coverage

The code coverage only includes the source files being tested and not any files under the `tests/` directory.

This option is supported with `ballerina build` and `ballerina test` commands. The link to the file will be printed in the console at the end of test execution.

**Example**

```
$ ballerina build --code-coverage <module_name> 
```
```
$ ballerina test --code-coverage <module_name>    
```