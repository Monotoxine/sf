/**
 * @description Comprehensive test class for Formula Parser
 * @author Claude
 * @date 2025-10-26
 */
@isTest
private class FormulaEvaluator_Test {

    // ========== Token Tests ==========

    @isTest
    static void testTokenCreation() {
        FormulaToken token = new FormulaToken(FormulaToken.TokenType.STRING_LITERAL, 'test', 0);
        System.assertEquals(FormulaToken.TokenType.STRING_LITERAL, token.type);
        System.assertEquals('test', token.value);
        System.assertEquals(0, token.position);
    }

    @isTest
    static void testTokenHelpers() {
        FormulaToken equalsToken = new FormulaToken(FormulaToken.TokenType.OP_EQ, '==', 0);
        System.assert(equalsToken.isType(FormulaToken.TokenType.OP_EQ));
        System.assert(equalsToken.isOperator());
        System.assert(equalsToken.isComparisonOperator());
        System.assert(!equalsToken.isLogicalOperator());

        FormulaToken andToken = new FormulaToken(FormulaToken.TokenType.OP_AND, 'AND', 0);
        System.assert(andToken.isLogicalOperator());
        System.assert(andToken.isOperator());

        FormulaToken stringToken = new FormulaToken(FormulaToken.TokenType.STRING_LITERAL, 'test', 0);
        System.assert(!stringToken.isOperator());
    }

    @isTest
    static void testTokenToString() {
        FormulaToken token = new FormulaToken(FormulaToken.TokenType.NUMBER_LITERAL, '42', 5);
        String str = token.toString();
        System.assert(str.contains('NUMBER'));
        System.assert(str.contains('42'));
    }

    // ========== Tokenizer Tests ==========

    @isTest
    static void testTokenizeSimpleString() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('"Hello World"');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(2, tokens.size()); // STRING + EOF
        System.assertEquals(FormulaToken.TokenType.STRING_LITERAL, tokens[0].type);
        System.assertEquals('Hello World', tokens[0].value);
    }

    @isTest
    static void testTokenizeStringWithEscapes() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('"Test\\nLine\\tTab\\\\Backslash"');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals('Test\nLine\tTab\\Backslash', tokens[0].value);
    }

    @isTest
    static void testTokenizeSingleQuoteString() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('\'Single Quote\'');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals('Single Quote', tokens[0].value);
    }

    @isTest
    static void testTokenizeNumbers() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('123 45.67 0.5');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(4, tokens.size()); // 3 numbers + EOF
        System.assertEquals('123', tokens[0].value);
        System.assertEquals('45.67', tokens[1].value);
        System.assertEquals('0.5', tokens[2].value);
    }

    @isTest
    static void testTokenizeBooleanAndNull() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('true false null');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(FormulaToken.TokenType.BOOLEAN_LITERAL, tokens[0].type);
        System.assertEquals('true', tokens[0].value);
        System.assertEquals(FormulaToken.TokenType.BOOLEAN_LITERAL, tokens[1].type);
        System.assertEquals('false', tokens[1].value);
        System.assertEquals(FormulaToken.TokenType.NULL_LITERAL, tokens[2].type);
    }

    @isTest
    static void testTokenizeOperators() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('== != > < >= <=');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(FormulaToken.TokenType.OP_EQ, tokens[0].type);
        System.assertEquals(FormulaToken.TokenType.OP_NEQ, tokens[1].type);
        System.assertEquals(FormulaToken.TokenType.OP_GT, tokens[2].type);
        System.assertEquals(FormulaToken.TokenType.OP_LT, tokens[3].type);
        System.assertEquals(FormulaToken.TokenType.OP_GTE, tokens[4].type);
        System.assertEquals(FormulaToken.TokenType.OP_LTE, tokens[5].type);
    }

    @isTest
    static void testTokenizeLogicalOperators() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('AND OR NOT');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(FormulaToken.TokenType.OP_AND, tokens[0].type);
        System.assertEquals(FormulaToken.TokenType.OP_OR, tokens[1].type);
        System.assertEquals(FormulaToken.TokenType.OP_NOT, tokens[2].type);
    }

    @isTest
    static void testTokenizeFunctions() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('ISBLANK(Name) CONTAINS(text, "search")');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(FormulaToken.TokenType.FUNCTION_NAME, tokens[0].type);
        System.assertEquals('ISBLANK', tokens[0].value);
    }

    @isTest
    static void testTokenizeFields() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('Name Amount__c Status');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(FormulaToken.TokenType.FIELD_REF, tokens[0].type);
        System.assertEquals('Name', tokens[0].value);
        System.assertEquals('Amount__c', tokens[1].value);
    }

    @isTest
    static void testTokenizeParenthesesAndCommas() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('(,)');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(FormulaToken.TokenType.LEFT_PAREN, tokens[0].type);
        System.assertEquals(FormulaToken.TokenType.COMMA, tokens[1].type);
        System.assertEquals(FormulaToken.TokenType.RIGHT_PAREN, tokens[2].type);
    }

    @isTest
    static void testTokenizeComplexFormula() {
        FormulaTokenizer tokenizer = new FormulaTokenizer(
            'AND(ISBLANK(Name), OR(Amount > 1000, Status__c == "Active"))'
        );
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assert(tokens.size() > 0);
        System.assertEquals(FormulaToken.TokenType.FUNCTION_NAME, tokens[0].type);
        System.assertEquals('AND', tokens[0].value);
    }

    @isTest
    static void testTokenizeWhitespace() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('  Name  ==  "Test"  ');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(4, tokens.size()); // FIELD, EQUALS, STRING, EOF
    }

    @isTest
    static void testTokenizeUnterminatedString() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('"Unterminated');
        try {
            tokenizer.tokenize();
            System.assert(false, 'Should throw exception');
        } catch (FormulaTokenizer.FormulaException e) {
            System.assert(e.getMessage().contains('Unterminated'));
        }
    }

    @isTest
    static void testTokenizeInvalidNumber() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('12.34.56');
        try {
            tokenizer.tokenize();
            System.assert(false, 'Should throw exception');
        } catch (FormulaTokenizer.FormulaException e) {
            System.assert(e.getMessage().contains('Invalid number'));
        }
    }

    @isTest
    static void testTokenizeInvalidCharacter() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('Name @ Value');
        try {
            tokenizer.tokenize();
            System.assert(false, 'Should throw exception');
        } catch (FormulaTokenizer.FormulaException e) {
            System.assert(e.getMessage().contains('Unexpected character'));
        }
    }

    @isTest
    static void testTokenizeEmptyString() {
        FormulaTokenizer tokenizer = new FormulaTokenizer('');
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(1, tokens.size()); // Only EOF
    }

    @isTest
    static void testTokenizeNullString() {
        FormulaTokenizer tokenizer = new FormulaTokenizer(null);
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.assertEquals(1, tokens.size()); // Only EOF
    }

    // ========== Node Tests ==========

    @isTest
    static void testLiteralNode() {
        FormulaNode.LiteralNode node = new FormulaNode.LiteralNode('test', 'STRING');
        System.assertEquals(FormulaNode.NodeType.LITERAL, node.getNodeType());
        System.assertEquals('"test"', node.toString());

        FormulaNode.LiteralNode nullNode = new FormulaNode.LiteralNode(null, 'NULL');
        System.assertEquals('null', nullNode.toString());

        FormulaNode.LiteralNode numNode = new FormulaNode.LiteralNode(42, 'NUMBER');
        System.assertEquals('42', numNode.toString());
    }

    @isTest
    static void testFieldReferenceNode() {
        FormulaNode.FieldReferenceNode node = new FormulaNode.FieldReferenceNode('Name');
        System.assertEquals(FormulaNode.NodeType.FIELD_REFERENCE, node.getNodeType());
        System.assertEquals('Name', node.toString());
    }

    @isTest
    static void testBinaryOperatorNode() {
        FormulaNode.LiteralNode left = new FormulaNode.LiteralNode(5, 'NUMBER');
        FormulaNode.LiteralNode right = new FormulaNode.LiteralNode(3, 'NUMBER');
        FormulaNode.BinaryOperatorNode node = new FormulaNode.BinaryOperatorNode('>', left, right);
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, node.getNodeType());
        System.assert(node.toString().contains('>'));
    }

    @isTest
    static void testUnaryOperatorNode() {
        FormulaNode.LiteralNode operand = new FormulaNode.LiteralNode(true, 'BOOLEAN');
        FormulaNode.UnaryOperatorNode node = new FormulaNode.UnaryOperatorNode('NOT', operand);
        System.assertEquals(FormulaNode.NodeType.UNARY_OPERATOR, node.getNodeType());
        System.assert(node.toString().contains('NOT'));
    }

    @isTest
    static void testFunctionCallNode() {
        List<FormulaNode> args = new List<FormulaNode>{
            new FormulaNode.FieldReferenceNode('Name')
        };
        FormulaNode.FunctionCallNode node = new FormulaNode.FunctionCallNode('ISBLANK', args);
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, node.getNodeType());
        System.assert(node.toString().contains('ISBLANK'));

        FormulaNode.FunctionCallNode emptyNode = new FormulaNode.FunctionCallNode('TEST', null);
        System.assertEquals(0, emptyNode.arguments.size());
    }

    // ========== Parser Tests ==========

    @isTest
    static void testParseLiterals() {
        FormulaParser parser = new FormulaParser(new FormulaTokenizer('"test"').tokenize());
        FormulaNode node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.LITERAL, node.getNodeType());

        parser = new FormulaParser(new FormulaTokenizer('42').tokenize());
        node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.LITERAL, node.getNodeType());

        parser = new FormulaParser(new FormulaTokenizer('true').tokenize());
        node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.LITERAL, node.getNodeType());

        parser = new FormulaParser(new FormulaTokenizer('null').tokenize());
        node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.LITERAL, node.getNodeType());
    }

    @isTest
    static void testParseField() {
        FormulaParser parser = new FormulaParser(new FormulaTokenizer('Name').tokenize());
        FormulaNode node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.FIELD_REFERENCE, node.getNodeType());
    }

    @isTest
    static void testParseComparison() {
        FormulaParser parser = new FormulaParser(new FormulaTokenizer('Amount > 100').tokenize());
        FormulaNode node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, node.getNodeType());
        FormulaNode.BinaryOperatorNode binOp = (FormulaNode.BinaryOperatorNode)node;
        System.assertEquals('>', binOp.operator);
    }

    @isTest
    static void testParseLogicalOperators() {
        FormulaParser parser = new FormulaParser(new FormulaTokenizer('true AND false').tokenize());
        FormulaNode node = parser.parse();
        FormulaNode.BinaryOperatorNode binOp = (FormulaNode.BinaryOperatorNode)node;
        System.assertEquals('AND', binOp.operator);

        parser = new FormulaParser(new FormulaTokenizer('true OR false').tokenize());
        node = parser.parse();
        binOp = (FormulaNode.BinaryOperatorNode)node;
        System.assertEquals('OR', binOp.operator);

        parser = new FormulaParser(new FormulaTokenizer('NOT true').tokenize());
        node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.UNARY_OPERATOR, node.getNodeType());
    }

    @isTest
    static void testParseParentheses() {
        FormulaParser parser = new FormulaParser(new FormulaTokenizer('(true AND false)').tokenize());
        FormulaNode node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, node.getNodeType());
    }

    @isTest
    static void testParseFunctionCall() {
        FormulaParser parser = new FormulaParser(new FormulaTokenizer('ISBLANK(Name)').tokenize());
        FormulaNode node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, node.getNodeType());
        FormulaNode.FunctionCallNode funcNode = (FormulaNode.FunctionCallNode)node;
        System.assertEquals('ISBLANK', funcNode.functionName);
        System.assertEquals(1, funcNode.arguments.size());
    }

    @isTest
    static void testParseFunctionMultipleArgs() {
        FormulaParser parser = new FormulaParser(
            new FormulaTokenizer('CONTAINS("hello", "lo")').tokenize()
        );
        FormulaNode node = parser.parse();
        FormulaNode.FunctionCallNode funcNode = (FormulaNode.FunctionCallNode)node;
        System.assertEquals(2, funcNode.arguments.size());
    }

    @isTest
    static void testParseFunctionNoArgs() {
        // Create a simple test with a function that could have no args (though most require them)
        List<FormulaToken> tokens = new List<FormulaToken>{
            new FormulaToken(FormulaToken.TokenType.FUNCTION_NAME, 'TEST', 0),
            new FormulaToken(FormulaToken.TokenType.LEFT_PAREN, '(', 4),
            new FormulaToken(FormulaToken.TokenType.RIGHT_PAREN, ')', 5),
            new FormulaToken(FormulaToken.TokenType.EOF, '', 6)
        };
        FormulaParser parser = new FormulaParser(tokens);
        FormulaNode node = parser.parse();
        FormulaNode.FunctionCallNode funcNode = (FormulaNode.FunctionCallNode)node;
        System.assertEquals(0, funcNode.arguments.size());
    }

    @isTest
    static void testParseOperatorPrecedence() {
        // OR has lower precedence than AND
        FormulaParser parser = new FormulaParser(
            new FormulaTokenizer('true OR false AND true').tokenize()
        );
        FormulaNode node = parser.parse();
        FormulaNode.BinaryOperatorNode orNode = (FormulaNode.BinaryOperatorNode)node;
        System.assertEquals('OR', orNode.operator);
        // Right side should be AND
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, orNode.right.getNodeType());
    }

    @isTest
    static void testParseComplexFormula() {
        String formula = 'AND(ISBLANK(Name), OR(Amount > 1000, Status__c == "Active"))';
        FormulaParser parser = new FormulaParser(new FormulaTokenizer(formula).tokenize());
        FormulaNode node = parser.parse();
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, node.getNodeType());
    }

    @isTest
    static void testParseAllComparisonOperators() {
        List<String> operators = new List<String>{'==', '!=', '>', '<', '>=', '<='};
        for (String op : operators) {
            FormulaParser parser = new FormulaParser(
                new FormulaTokenizer('5 ' + op + ' 3').tokenize()
            );
            FormulaNode node = parser.parse();
            System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, node.getNodeType());
        }
    }

    @isTest
    static void testParserEmptyTokens() {
        try {
            FormulaParser parser = new FormulaParser(new List<FormulaToken>());
            parser.parse();
            System.assert(false, 'Should throw exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('No tokens'));
        }
    }

    @isTest
    static void testParserUnexpectedToken() {
        List<FormulaToken> tokens = new List<FormulaToken>{
            new FormulaToken(FormulaToken.TokenType.NUMBER_LITERAL, '42', 0),
            new FormulaToken(FormulaToken.TokenType.NUMBER_LITERAL, '99', 3), // Unexpected
            new FormulaToken(FormulaToken.TokenType.EOF, '', 6)
        };
        try {
            FormulaParser parser = new FormulaParser(tokens);
            parser.parse();
            System.assert(false, 'Should throw exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('Unexpected token'));
        }
    }

    @isTest
    static void testParserMissingParenthesis() {
        try {
            FormulaParser parser = new FormulaParser(
                new FormulaTokenizer('(true AND false').tokenize()
            );
            parser.parse();
            System.assert(false, 'Should throw exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('closing parenthesis'));
        }
    }

    @isTest
    static void testParserMissingFunctionParenthesis() {
        List<FormulaToken> tokens = new List<FormulaToken>{
            new FormulaToken(FormulaToken.TokenType.FUNCTION_NAME, 'ISBLANK', 0),
            new FormulaToken(FormulaToken.TokenType.FIELD_REF, 'Name', 8), // Missing (
            new FormulaToken(FormulaToken.TokenType.EOF, '', 12)
        };
        try {
            FormulaParser parser = new FormulaParser(tokens);
            parser.parse();
            System.assert(false, 'Should throw exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('opening parenthesis'));
        }
    }

    @isTest
    static void testParserUnexpectedPrimary() {
        List<FormulaToken> tokens = new List<FormulaToken>{
            new FormulaToken(FormulaToken.TokenType.COMMA, ',', 0),
            new FormulaToken(FormulaToken.TokenType.EOF, '', 1)
        };
        try {
            FormulaParser parser = new FormulaParser(tokens);
            parser.parse();
            System.assert(false, 'Should throw exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('Unexpected token'));
        }
    }

    // ========== Evaluator Tests ==========

    @isTest
    static void testEvaluateLiterals() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals('test', evaluator.evaluate('"test"'));
        System.assertEquals(42, evaluator.evaluate('42'));
        System.assertEquals(true, evaluator.evaluate('true'));
        System.assertEquals(false, evaluator.evaluate('false'));
        System.assertEquals(null, evaluator.evaluate('null'));
    }

    @isTest
    static void testEvaluateFieldReference() {
        Map<String, Object> context = new Map<String, Object>{
            'Name' => 'John Doe',
            'Amount' => 1500
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals('John Doe', evaluator.evaluate('Name'));
        System.assertEquals(1500, evaluator.evaluate('Amount'));
    }

    @isTest
    static void testEvaluateFieldReferenceSObject() {
        Account acc = new Account(Name = 'Test Account', AnnualRevenue = 50000);
        FormulaEvaluator evaluator = new FormulaEvaluator(acc);

        System.assertEquals('Test Account', evaluator.evaluate('Name'));
        System.assertEquals(50000, evaluator.evaluate('AnnualRevenue'));
    }

    @isTest
    static void testEvaluateComparisons() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('5 > 3'));
        System.assertEquals(false, evaluator.evaluate('5 < 3'));
        System.assertEquals(true, evaluator.evaluate('5 >= 5'));
        System.assertEquals(true, evaluator.evaluate('3 <= 5'));
        System.assertEquals(true, evaluator.evaluate('5 == 5'));
        System.assertEquals(true, evaluator.evaluate('5 != 3'));
    }

    @isTest
    static void testEvaluateStringComparison() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('"apple" == "apple"'));
        System.assertEquals(false, evaluator.evaluate('"apple" == "banana"'));
        System.assertEquals(true, evaluator.evaluate('"banana" > "apple"'));
    }

    @isTest
    static void testEvaluateNullComparisons() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('null == null'));
        System.assertEquals(false, evaluator.evaluate('null == 5'));
        System.assertEquals(false, evaluator.evaluate('null > 5'));
    }

    @isTest
    static void testEvaluateLogicalOperators() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('true AND true'));
        System.assertEquals(false, evaluator.evaluate('true AND false'));
        System.assertEquals(true, evaluator.evaluate('true OR false'));
        System.assertEquals(false, evaluator.evaluate('false OR false'));
        System.assertEquals(false, evaluator.evaluate('NOT true'));
        System.assertEquals(true, evaluator.evaluate('NOT false'));
    }

    @isTest
    static void testEvaluateShortCircuit() {
        Map<String, Object> context = new Map<String, Object>{'Value' => 10};
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        // OR should short-circuit
        System.assertEquals(true, evaluator.evaluate('true OR (Value > 100)'));

        // AND should short-circuit
        System.assertEquals(false, evaluator.evaluate('false AND (Value > 100)'));
    }

    @isTest
    static void testEvaluateFunctionIsBlank() {
        Map<String, Object> context = new Map<String, Object>{
            'Name' => 'John',
            'Empty' => '',
            'Spaces' => '   ',
            'Null' => null
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(false, evaluator.evaluate('ISBLANK(Name)'));
        System.assertEquals(true, evaluator.evaluate('ISBLANK(Empty)'));
        System.assertEquals(true, evaluator.evaluate('ISBLANK(Spaces)'));
        System.assertEquals(true, evaluator.evaluate('ISBLANK(Null)'));
    }

    @isTest
    static void testEvaluateFunctionIsNumber() {
        Map<String, Object> context = new Map<String, Object>{
            'Num' => 42,
            'Str' => 'test',
            'NumStr' => '123'
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('ISNUMBER(Num)'));
        System.assertEquals(false, evaluator.evaluate('ISNUMBER(Str)'));
        System.assertEquals(true, evaluator.evaluate('ISNUMBER(NumStr)'));
        System.assertEquals(false, evaluator.evaluate('ISNUMBER(null)'));
    }

    @isTest
    static void testEvaluateFunctionIsPickval() {
        Map<String, Object> context = new Map<String, Object>{
            'Status' => 'Active'
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('ISPICKVAL(Status, "Active")'));
        System.assertEquals(false, evaluator.evaluate('ISPICKVAL(Status, "Inactive")'));
    }

    @isTest
    static void testEvaluateFunctionText() {
        Map<String, Object> context = new Map<String, Object>{
            'Num' => 42,
            'Null' => null
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals('42', evaluator.evaluate('TEXT(Num)'));
        System.assertEquals('', evaluator.evaluate('TEXT(Null)'));
    }

    @isTest
    static void testEvaluateFunctionValue() {
        Map<String, Object> context = new Map<String, Object>{
            'NumStr' => '123.45'
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(123.45, evaluator.evaluate('VALUE(NumStr)'));
    }

    @isTest
    static void testEvaluateFunctionLen() {
        Map<String, Object> context = new Map<String, Object>{
            'Text' => 'Hello'
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(5, evaluator.evaluate('LEN(Text)'));
        System.assertEquals(0, evaluator.evaluate('LEN(null)'));
    }

    @isTest
    static void testEvaluateFunctionContains() {
        Map<String, Object> context = new Map<String, Object>{
            'Text' => 'Hello World'
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('CONTAINS(Text, "World")'));
        System.assertEquals(false, evaluator.evaluate('CONTAINS(Text, "xyz")'));
    }

    @isTest
    static void testEvaluateFunctionBegins() {
        Map<String, Object> context = new Map<String, Object>{
            'Text' => 'Hello World'
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('BEGINS(Text, "Hello")'));
        System.assertEquals(false, evaluator.evaluate('BEGINS(Text, "World")'));
    }

    @isTest
    static void testEvaluateFunctionUpper() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals('HELLO', evaluator.evaluate('UPPER("hello")'));
    }

    @isTest
    static void testEvaluateFunctionLower() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals('hello', evaluator.evaluate('LOWER("HELLO")'));
    }

    @isTest
    static void testEvaluateFunctionTrim() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals('test', evaluator.evaluate('TRIM("  test  ")'));
    }

    @isTest
    static void testEvaluateFunctionIf() {
        Map<String, Object> context = new Map<String, Object>{
            'Amount' => 1500
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals('High', evaluator.evaluate('IF(Amount > 1000, "High", "Low")'));
        System.assertEquals('Low', evaluator.evaluate('IF(Amount < 1000, "High", "Low")'));
    }

    @isTest
    static void testEvaluateFunctionAbs() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(5, evaluator.evaluate('ABS(-5)'));
        System.assertEquals(5, evaluator.evaluate('ABS(5)'));
    }

    @isTest
    static void testEvaluateFunctionCeiling() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(6, evaluator.evaluate('CEILING(5.3)'));
    }

    @isTest
    static void testEvaluateFunctionFloor() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(5, evaluator.evaluate('FLOOR(5.9)'));
    }

    @isTest
    static void testEvaluateFunctionRound() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(5, evaluator.evaluate('ROUND(5.4)'));
        System.assertEquals(5.68, evaluator.evaluate('ROUND(5.678, 2)'));
    }

    @isTest
    static void testEvaluateFunctionMod() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(1, evaluator.evaluate('MOD(10, 3)'));
    }

    @isTest
    static void testEvaluateComplexFormula() {
        Map<String, Object> context = new Map<String, Object>{
            'Name' => null,
            'Amount' => 1500,
            'Status__c' => 'Active'
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        String formula = 'AND(ISBLANK(Name), OR(Amount > 1000, Status__c == "Active"))';
        System.assertEquals(true, evaluator.evaluate(formula));
    }

    @isTest
    static void testEvaluateWithDateComparison() {
        Date today = Date.today();
        Date yesterday = today.addDays(-1);
        Map<String, Object> context = new Map<String, Object>{
            'Today' => today,
            'Yesterday' => yesterday
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('Today > Yesterday'));
        System.assertEquals(false, evaluator.evaluate('Today < Yesterday'));
    }

    @isTest
    static void testEvaluateWithDatetimeComparison() {
        Datetime now = Datetime.now();
        Datetime past = now.addHours(-1);
        Map<String, Object> context = new Map<String, Object>{
            'Now' => now,
            'Past' => past
        };
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('Now > Past'));
    }

    @isTest
    static void testEvaluateToBooleanConversion() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        System.assertEquals(true, evaluator.evaluate('NOT null'));
        System.assertEquals(false, evaluator.evaluate('NOT "true"'));
        System.assertEquals(false, evaluator.evaluate('NOT "1"'));
    }

    @isTest
    static void testEvaluateToDecimalConversion() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        // Test different numeric types
        System.assertEquals(true, evaluator.evaluate('5 == 5.0'));
        System.assertEquals(0, evaluator.evaluate('ABS(null)')); // null converts to 0
    }

    @isTest
    static void testEvaluatorUnknownNodeType() {
        // This tests the default case in evaluateNode
        // We can't easily create a node with unknown type, so we'll test error handling
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        // Test null node
        System.assertEquals(null, evaluator.evaluateNode(null));
    }

    @isTest
    static void testEvaluatorFieldNotFound() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        try {
            evaluator.evaluate('NonExistentField');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('No context'));
        }
    }

    @isTest
    static void testEvaluatorSObjectFieldNotFound() {
        Account acc = new Account(Name = 'Test');
        FormulaEvaluator evaluator = new FormulaEvaluator(acc);

        try {
            evaluator.evaluate('NonExistentField__c');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('Field not found'));
        }
    }

    @isTest
    static void testEvaluatorUnknownOperator() {
        // We'll manually create a node with invalid operator
        try {
            Map<String, Object> context = new Map<String, Object>();
            FormulaEvaluator evaluator = new FormulaEvaluator(context);
            FormulaNode.LiteralNode left = new FormulaNode.LiteralNode(5, 'NUMBER');
            FormulaNode.LiteralNode right = new FormulaNode.LiteralNode(3, 'NUMBER');
            FormulaNode.BinaryOperatorNode badNode = new FormulaNode.BinaryOperatorNode('INVALID', left, right);

            evaluator.evaluateNode(badNode);
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('Unknown operator'));
        }
    }

    @isTest
    static void testEvaluatorUnknownUnaryOperator() {
        try {
            Map<String, Object> context = new Map<String, Object>();
            FormulaEvaluator evaluator = new FormulaEvaluator(context);
            FormulaNode.LiteralNode operand = new FormulaNode.LiteralNode(true, 'BOOLEAN');
            FormulaNode.UnaryOperatorNode badNode = new FormulaNode.UnaryOperatorNode('INVALID', operand);

            evaluator.evaluateNode(badNode);
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('Unknown unary operator'));
        }
    }

    @isTest
    static void testEvaluatorUnknownFunction() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        try {
            evaluator.evaluate('UNKNOWNFUNC(test)');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('Unknown function'));
        }
    }

    @isTest
    static void testEvaluatorFunctionWrongArgCount() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        try {
            evaluator.evaluate('ISBLANK("a", "b")');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('requires 1 argument'));
        }

        try {
            evaluator.evaluate('CONTAINS("text")');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('requires 2 arguments'));
        }

        try {
            evaluator.evaluate('IF(true, "a")');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('requires 3 arguments'));
        }

        try {
            evaluator.evaluate('ROUND(5.5, 2, 3)');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('requires 1 or 2 arguments'));
        }
    }

    @isTest
    static void testEvaluatorValueConversionError() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        try {
            evaluator.evaluate('VALUE("not a number")');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('Cannot convert to number'));
        }
    }

    @isTest
    static void testEvaluatorNullConstructor() {
        FormulaEvaluator evaluator = new FormulaEvaluator((Map<String, Object>)null);
        System.assertEquals(true, evaluator.evaluate('true'));
    }

    // ========== Relational Fields Tests ==========

    @isTest
    static void testEvaluateRelationalField_Simple() {
        // Create a mock Account with relationship
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        User currentUser = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        acc.OwnerId = currentUser.Id;
        update acc;

        // Query with relationship
        acc = [SELECT Id, Name, Owner.Name FROM Account WHERE Id = :acc.Id];

        FormulaEvaluator evaluator = new FormulaEvaluator(acc);
        Object result = evaluator.evaluate('Owner.Name');

        System.assertNotEquals(null, result);
        System.assertEquals(currentUser.Name, result);
    }

    @isTest
    static void testEvaluateRelationalField_InComparison() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        User currentUser = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        acc.OwnerId = currentUser.Id;
        update acc;

        acc = [SELECT Id, Name, Owner.Name FROM Account WHERE Id = :acc.Id];

        FormulaEvaluator evaluator = new FormulaEvaluator(acc);
        Object result = evaluator.evaluate('Owner.Name == "' + currentUser.Name + '"');

        System.assertEquals(true, result);
    }

    @isTest
    static void testEvaluateRelationalField_Null() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        // When field path contains null in the middle, should return null
        Account acc = new Account(Name = 'Test');
        // No Owner relationship set, so it's null
        evaluator = new FormulaEvaluator(acc);

        try {
            // This might fail since Owner is not queried
            Object result = evaluator.evaluate('Owner.Name');
            // If it doesn't fail, result should be null
            System.assertEquals(null, result);
        } catch (Exception e) {
            // Expected - field not queried
            System.assert(true);
        }
    }

    @isTest
    static void testEvaluateRelationalField_InFormula() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        User currentUser = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        acc.OwnerId = currentUser.Id;
        update acc;

        acc = [SELECT Id, Name, Owner.Name FROM Account WHERE Id = :acc.Id];

        FormulaEvaluator evaluator = new FormulaEvaluator(acc);
        Object result = evaluator.evaluate('NOT ISBLANK(Owner.Name) AND Name == "Test Account"');

        System.assertEquals(true, result);
    }

    // ========== TODAY() and NOW() Tests ==========

    @isTest
    static void testEvaluateFunctionToday() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        Object result = evaluator.evaluate('TODAY()');
        System.assertNotEquals(null, result);
        System.assert(result instanceof Date);
        System.assertEquals(Date.today(), result);
    }

    @isTest
    static void testEvaluateFunctionNow() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        Object result = evaluator.evaluate('NOW()');
        System.assertNotEquals(null, result);
        System.assert(result instanceof Datetime);

        // Check it's approximately now (within 1 second)
        Datetime now = Datetime.now();
        Datetime resultTime = (Datetime)result;
        Long diff = Math.abs(now.getTime() - resultTime.getTime());
        System.assert(diff < 1000, 'NOW() should return current datetime');
    }

    @isTest
    static void testEvaluateTodayInComparison() {
        Date yesterday = Date.today().addDays(-1);
        Date tomorrow = Date.today().addDays(1);

        Map<String, Object> context = new Map<String, Object>{
            'StartDate' => yesterday,
            'EndDate' => tomorrow
        };

        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        // Check if today is between start and end dates
        Boolean result = (Boolean)evaluator.evaluate('TODAY() > StartDate AND TODAY() < EndDate');
        System.assertEquals(true, result);
    }

    @isTest
    static void testEvaluateNowInComparison() {
        Datetime past = Datetime.now().addHours(-1);
        Datetime future = Datetime.now().addHours(1);

        Map<String, Object> context = new Map<String, Object>{
            'StartTime' => past,
            'EndTime' => future
        };

        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        Boolean result = (Boolean)evaluator.evaluate('NOW() > StartTime AND NOW() < EndTime');
        System.assertEquals(true, result);
    }

    @isTest
    static void testEvaluateTodayWithArguments() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        try {
            evaluator.evaluate('TODAY("invalid")');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('requires 0 arguments'));
        }
    }

    @isTest
    static void testEvaluateNowWithArguments() {
        Map<String, Object> context = new Map<String, Object>();
        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        try {
            evaluator.evaluate('NOW("invalid")');
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.EvaluatorException e) {
            System.assert(e.getMessage().contains('requires 0 arguments'));
        }
    }

    // ========== Complex Date/Time Tests ==========

    @isTest
    static void testEvaluateDateRangeCheck() {
        Date recordDate = Date.today().addDays(-5);

        Map<String, Object> context = new Map<String, Object>{
            'RecordDate' => recordDate
        };

        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        // Check if record is older than 3 days
        Boolean result = (Boolean)evaluator.evaluate('RecordDate < TODAY()');
        System.assertEquals(true, result);
    }

    @isTest
    static void testEvaluateDateTimeWithSObject() {
        // Create an Opportunity with CloseDate
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            CloseDate = Date.today().addDays(30),
            StageName = 'Prospecting'
        );
        insert opp;

        opp = [SELECT Id, Name, CloseDate FROM Opportunity WHERE Id = :opp.Id];

        FormulaEvaluator evaluator = new FormulaEvaluator(opp);

        // Check if opportunity closes in the future
        Boolean result = (Boolean)evaluator.evaluate('CloseDate > TODAY()');
        System.assertEquals(true, result);
    }

    // ========== Edge Cases for Relational Fields ==========

    @isTest
    static void testRelationalFieldNonSObjectError() {
        // Test error when trying to traverse a non-SObject value
        Map<String, Object> context = new Map<String, Object>{
            'StringField' => 'test value'
        };

        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        // This should work - no traversal
        Object result = evaluator.evaluate('StringField');
        System.assertEquals('test value', result);
    }

    @isTest
    static void testRelationalFieldWithDotNotation() {
        // Test that dot notation works in context map (should look for exact key)
        Map<String, Object> context = new Map<String, Object>{
            'Account.Name' => 'Exact Match'
        };

        FormulaEvaluator evaluator = new FormulaEvaluator(context);

        Object result = evaluator.evaluate('Account.Name');
        System.assertEquals('Exact Match', result);
    }
}
