# Salesforce / Apex Coding Guidelines

> Sources: Naming Convention (03.06.04), Apex Code Style, Apex General Guidelines & Concepts

---

## 1. Naming Conventions (Salesforce Metadata)

### Capability Key Codes
| Code | Meaning |
|------|---------|
| CCID | Capability Code + Country Code/Core |
| SCID | Stream Code + Country Code/Core |
| CSCO | Customer Service Core |
| FSCO | Field Service Core |
| SMCO | Sales and Marketing Core |
| ONTCO | One Trust Core |

### Metadata Element API Names
| Element | Format | Example |
|---------|--------|---------|
| Custom Object | `<CCID>_<ObjectName>__c` | `WOMCO_Visit__c` |
| Custom Field | `<CCID>_<FieldName>__c` | `WOMFR_MainContact__c` |
| Page Layout | `<CCID>_<Page Name>` | `WOMCA Client Group Page Layout` |
| Record Type | `<CCID>_<RecordTypeName>` | `WOMCO_NoClient` |
| Validation Rule | `<CCID>_<ValidationRuleName>` | `WOMPT_RequiredRejectReason` |
| Custom Label | `<CCID>_<CustomLabelName>` | `WOMCO_TextVisitHelp` |
| Custom Label (Lightning Pages) | `CMNF_<ObjectName>_<LabelName>` | `CMNF_Account_InterventionAndPreferences` |
| Custom Setting | `<CCID>_<CustomSettingName>` | `WOMCO_DefectValues` |
| Custom Metadata | `<CCID>_<CustomMetadataName>` | `WOMCO_ProductFields` |
| Sharing Rule | `<TEK><CORE/Country>_<Name>_(RW/RO)` | `TEKCO_ShareOpNoVip_RW` |
| Permission Set (persona) | `<SCID>_<PermissionSetName>` | `CSCO_FrontOfficeAgentBasePermission` |
| Permission Set (functional) | `CMNF_<PermissionSetName>` | `CMNF_AccessToReports` |
| Permission Set Group | `<SCID>_<PermissionSetGroupName>` | `CSCO_FrontOfficeAgent` |
| Groups | `CORE_CS_GroupName` / `CAN_CS_GroupName` | |
| Flexi Pages | `<SCID>_<ObjectName>_<PageName>` | `CSCO_ObjectName_PageName` |
| LWC | `<ccid>ComponentName` (lowerCamelCase prefix) | |
| Aura Components | `<CCID>_ComponentName` | |
| Global Value Set | `<CCID>_ValueSetName` | |
| Queues | `<CCID>_BrandQueueName` | |
| Custom Tabs | `<CCID>_TabName` | |
| Application | `<SCID>_<AppName>` | `FSCO_AgentConsole` |
| Quick Action | `<CCID>_ActionName` | `FSCO_CloseCase` |
| Screen Flow | `<SCID>_FlowName` / `<SCID>_SUB_FlowName` | `CSCO_TheBestFlow` |
| Process Builder | `<CCID>_<Object>_<ProcessBuilderName>` | `WOMCO_OPPY_StageManagement` |
| Process Builder Actions | `<CCID>_<Object>_<Action>` | `WOMCO_OPPY_UpdatePlannedDate` |
| Approval Process | `<CCID>_<Object>_<ApprovalProcessName>` | `WOMCO_OPPY_RejectionCreditStart` |

### CRM Analytics Naming
Pattern: `<PROJECT> - <Name>` (Label) / `<PROJECT>_<Name>` (API)

Projects: `CRM`, `CSV`, `TECH`, `POC`, `EVM`, `STG`

Components: `<PROJECT>_<DashboardName>_<ComponentName>_CMP`

---

## 2. Source File Basics

- **File name**: matches the top-level class name exactly (case-sensitive) + `.cls`
- **Encoding**: UTF-8
- **Whitespace**: ASCII space (0x20) only — no tab characters
- **String escaping**: use Apex `String.escape*` methods for special characters in strings

### File Structure Order
1. Top-level ApexDoc comment
2. Class declaration
*(No blank lines between sections)*

---

## 3. Class Structure & Ordering

Order inside a class:
1. Class/Interface documentation (ApexDoc)
2. `class` or `interface` statement
3. Static variables — `final` first, then `global > public > protected > private`
4. Instance variables — same order
5. Constructors — `public > protected > private`
6. Methods — logical order (as they appear in the call chain, not chronological)
7. Inner classes

**Overloads**: never split — consecutive, no other code between them.

---

## 4. Formatting

### Braces — K&R Style
```apex
// GOOD
if (x < 0) {
    negative(x);
} else {
    nonnegative(x);
}

// BAD
if (x < 0)
    negative(x);
```

Empty blocks: `{}` is acceptable **except** in multi-block statements (`if/else`, `try/catch`).

### Indentation
- **+4 spaces** per block level
- **+8 spaces** minimum for continuation lines
- No tab characters

### Line Length
- Column limit: **120 characters**
- Exceptions: long URLs in ApexDoc, shell commands in comments

### Line Wrapping Rules
- Break **before** non-assignment operators (including `.`)
- Break **after** assignment operators
- Method/constructor name stays attached to `(`
- Comma stays attached to the preceding token

**Method declarations** — preferred style:
```apex
// GOOD
public String downloadAnInternet(
    Internet internet,
    Tubes tubes,
    List<Decimal> bandwidth
) {
    ...
}
```

**Method call chaining**:
```apex
// GOOD
Iterable<Object> modules = new ListBuilder()
    .add(new LifecycleModule())
    .add(new AppLauncherModule())
    .build();
```

### SOQL Formatting
```apex
List<Account> accounts = [
    SELECT
        Id,
        Name,
        (
            SELECT
                Title,
                Body
            FROM Notes
            WHERE LastModifiedDate = LAST_N_YEARS:5
        )
    FROM Account
    WHERE LastModifiedDate = LAST_N_MONTHS:6
        AND Phone != NULL
    ORDER BY Phone ASC
];
```
- All SOQL reserved words in **UPPERCASE**
- Each field on its own line, indented +4 from SELECT
- Multiple WHERE clauses on separate lines starting with the SOQL operator

### Whitespace Rules
- Single blank line between class members
- Space after reserved words (`if`, `for`, `catch`, `else`)
- Space on both sides of binary/ternary operators
- **No trailing whitespace**
- No horizontal alignment (variable-width spacing to align tokens)

### Other
- **One statement per line**
- Annotations on their own line, immediately after the ApexDoc block
- Modifier order: `global/public/protected/private virtual/abstract with/without/inherited sharing`
- Long integer literals: uppercase `L` suffix (`3000000000L`)

---

## 5. Naming (Apex Identifiers)

### General Rules
- ASCII letters and digits only; underscores only where explicitly noted
- No double underscores (`__`) — reserved by the platform
- No special prefixes/suffixes like `name_`, `mName`, `s_name`, `kName`

### By Type
| Type | Convention | Example |
|------|-----------|---------|
| Class | UpperCamelCase noun/noun phrase | `AccountProcessor`, `ImmutableList` |
| Test Class | `<TestedClass>Test` | `HashTest` |
| Method | lowerCamelCase verb/verb phrase | `sendMessage`, `stop` |
| Constant | `CONSTANT_CASE` | `NUMBER`, `NAMES` |
| Non-constant field | lowerCamelCase | `computedValues`, `index` |
| Parameter | lowerCamelCase (no single-char) | `recipientEmailAddress` |
| Local variable | lowerCamelCase | `totalAmount` |
| Property | lowerCamelCase | |
| SOQL/SOSL keywords | ALL UPPERCASE | `SELECT`, `WHERE`, `FROM` |

### Naming Rules for Methods
- **get/set**: use for direct attribute access — `employee.getName()`
- **is/has/can/should**: prefix for booleans — `isVisible`, `hasLicense`, `canEvaluate`
- **compute**: prefix for potentially expensive operations — `computeAverage()`
- Avoid redundant class name in method name: `line.getLength()` not `line.getLineLength()`

### Naming Rules for Variables
- Collections: reflect the type — `List<String> userNames`, `Map<Id, Contact> contactById`
- Count variables: `numOf` prefix — `numOfPoints`
- Entity number variables: no suffix — `accountNo`
- Include units in names: `pollIntervalMs`, `fileSizeGb`
- Complement pairs: `get/set`, `add/remove`, `start/stop`, `open/close`, `min/max`, etc.

### No Magic Numbers/Strings
```apex
// BAD
Player[] players = new Player[11];

// GOOD
private static final Integer TEAM_SIZE = 11;
Player[] players = new Player[TEAM_SIZE];
```

### Camel Case for Acronyms
| Prose | Correct | Wrong |
|-------|---------|-------|
| XML HTTP request | `XmlHttpRequest` | `XMLHTTPRequest` |
| new customer ID | `newCustomerId` | `newCustomerID` |
| supports IPv6 on iOS? | `supportsIpv6OnIos` | `supportsIPv6OnIOS` |

---

## 6. ApexDoc

### Required Format
```apex
/**
 * @author Author Name (email@example.com), dd/mm/yyyy
 * @description Utility class. Returns information about Record Types.
 */
public without sharing class Handler {

    /**
     * @author Author Name (email@example.com), dd/mm/yyyy
     * @description Returns the field label for the given field name.
     * @param fieldName The API name of the field.
     * @return The label string, or null if not found.
     * @throws ArgumentNullException if fieldName is null.
     */
    public Integer method(String fieldName) { ... }
}
```

- At-clause order: `@description`, `@param`, `@return`, `@throws`
- Required on every `global` and `public` class and member
- Exceptions: self-explanatory getters (`getFoo`), overrides

### @history Tag
```apex
/**
 * @author Author Name (email), dd/mm/yyyy
 * @description Some description
 * @history [CXHHC-0001] Author Name (email), dd/mm/yyyy, short description
 *          [CXHHC-0002] Author Name (email), dd/mm/yyyy, short description
 */
```

---

## 7. Testing

### Test Class Declaration
```apex
@isTest
private class ExampleTest {
    ...
}
```

### Test Method Pattern — GivenWhenThen
```apex
@isTest
private static void getRecord_withRecordId_expectRecordRetrieved() {
    // GIVEN
    ExampleController testController = new ExampleController();
    Id testRecordId = TestDataHelperClass.Instance.insertRecord().Id;

    // WHEN
    Test.startTest();
    SObject actualRecord = testController.getRecord(testRecordId);
    Test.stopTest();

    // THEN
    System.assertNotEquals(null, actualRecord, 'Did not expect a null record.');
    System.assertEquals(testRecordId, actualRecord.Id, 'Expected the test record.');
}
```

- Test method names: `<methodUnderTest>_<withState>_<expectation>`
- Always wrap the operation under test in `Test.startTest()` / `Test.stopTest()`
- Never use `@isTest(SeeAllData=true)` unless absolutely necessary
- Avoid randomness in test data — use fixed, known values
- All test classes are `private`

### Mocking
```apex
// Protected constructor for mocking
@testVisible
protected Example() { }

// Check mock before Test.isRunningTest()
if (mockInstance != null && Test.isRunningTest()) {
    return mockInstance;
}
```

---

## 8. Clean Code Principles (Apex)

### Meaningful Names
Every name must reveal intent. Avoid single-letter variables, abbreviations, and misleading names.
```apex
// BAD
Decimal t = 0;
for (OrderItem i : o) { t += i.Quantity * i.UnitPrice; }

// GOOD
Decimal totalAmount = 0;
for (OrderItem currentOrderItem : orderItems) {
    totalAmount += currentOrderItem.Quantity * currentOrderItem.UnitPrice;
}
```

### Single Responsibility
Each method does **one thing**. If it can be named with "and", split it.
```apex
// BAD — two responsibilities
public static void parseAndSaveData(String data) { ... }

// GOOD — separated
public static List<String> parseCsvData(String csvData) { ... }
public static void saveAccount(List<String> parsedData) { ... }
public static void processAccountData(String inputData) {
    saveAccount(parseCsvData(inputData));
}
```

### Short Functions
Aim for ~15–25 lines max. Extract sub-tasks into named helper methods.

### Comments — Explain "Why", Not "What"
```apex
// BAD
acc.OwnerId = newOwnerId; // Update the account owner

// GOOD
// Transfer ownership so the new owner can manage related opportunities and contracts.
acc.OwnerId = newOwnerId;
```

- Use `// TODO:` for incomplete work
- Use `// WARNING:` for performance concerns or gotchas
- Remove commented-out code — use version control instead

### Early Returns to Reduce Nesting
```apex
// BAD
public static void processAccount(Account acc) {
    if (acc != null) {
        if (!String.isBlank(acc.Name)) {
            // ... logic ...
        }
    }
}

// GOOD
public static void processAccount(Account acc) {
    if (acc == null) return;
    if (String.isBlank(acc.Name)) return;
    // ... logic ...
}
```

---

## 9. Apex-Specific Best Practices

### Bulkify Everything
Never process records one-by-one. Always design for collections.

```apex
// BAD — SOQL in loop
for (Account acc : accounts) {
    List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acc.Id];
    ...
}

// GOOD — bulk query + map
Set<Id> accountIds = new Set<Id>();
for (Account acc : accounts) { accountIds.add(acc.Id); }

Map<Id, List<Contact>> contactMap = new Map<Id, List<Contact>>();
for (Contact con : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds]) {
    if (!contactMap.containsKey(con.AccountId)) {
        contactMap.put(con.AccountId, new List<Contact>());
    }
    contactMap.get(con.AccountId).add(con);
}
```

### Never Put SOQL or DML Inside Loops
- Collect records in a `List` inside the loop
- Perform a single DML operation after the loop
- Use `Map` lookups to access related data inside loops

### Trigger Management
- **One trigger per object** — no logic inside the trigger itself
- Delegate to a handler class
- Handler separates concerns by trigger event

### Error Handling
```apex
// GOOD
try {
    if (String.isBlank(name)) {
        throw new AccountValidationException('Account name cannot be blank.');
    }
    insert new Account(Name = name);
} catch (DmlException e) {
    System.debug('DML Error: ' + e.getMessage());
    throw new AuraHandledException('Error saving account. Contact your administrator.');
} catch (AccountValidationException e) {
    throw new AuraHandledException(e.getMessage());
}
public class AccountValidationException extends Exception {}
```

- Catch **specific** exception types, not generic `Exception` alone
- Never swallow exceptions silently
- Use `addError()` in trigger context for user-facing messages
- Define custom exception classes for business logic errors

### No Hardcoded IDs or Values
Use Custom Settings, Custom Metadata, Named Credentials, or Custom Labels:
```apex
// BAD
Account acc = [SELECT Id FROM Account WHERE Id = '001XXXXXXXXX'];

// GOOD
Id defaultId = MyAppSettings__c.getInstance().DefaultAccountId__c;
```

### Governor Limits Awareness
| Limit | Sync | Async |
|-------|------|-------|
| SOQL queries | 100 | 200 |
| DML statements | 150 | 150 |
| CPU time | 10,000 ms | 60,000 ms |
| Heap size | 6 MB | 12 MB |

- Select only needed fields — never `SELECT FIELDS(ALL)`
- Use sub-selects to avoid multiple queries
- Use SOQL `for` loops for large datasets (processes in batches of 200)
- Set class-level collections to `null` when done; use `transient` for Visualforce
- Monitor with `Limits.getHeapSize()` / `Limits.getLimitHeapSize()`

### Asynchronous Apex
Choose the right tool:
- `@future` — simple fire-and-forget async tasks
- `Queueable` — chaining jobs, complex parameter types
- `Batch Apex` — large dataset processing
- `Scheduled Apex` — time-based execution
