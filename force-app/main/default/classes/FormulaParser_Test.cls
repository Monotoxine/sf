/**
 * @description Comprehensive test class specifically for FormulaParser
 * @author Claude
 * @date 2025-10-26
 * Tests all parser functionality: precedence, parentheses, functions, validation
 */
@isTest
private class FormulaParser_Test {

    // ========== Helper Method ==========

    private static FormulaNode parseFormula(String formula) {
        FormulaTokenizer tokenizer = new FormulaTokenizer(formula);
        List<FormulaToken> tokens = tokenizer.tokenize();
        FormulaParser parser = new FormulaParser(tokens);
        return parser.parse();
    }

    // ========== Simple Expressions ==========

    @isTest
    static void testParseSimpleComparison_Equals() {
        // A == B
        FormulaNode ast = parseFormula('A == B');

        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, ast.getNodeType());
        FormulaNode.BinaryOperatorNode binOp = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('==', binOp.operator);

        System.assertEquals(FormulaNode.NodeType.FIELD_REFERENCE, binOp.left.getNodeType());
        FormulaNode.FieldReferenceNode leftField = (FormulaNode.FieldReferenceNode)binOp.left;
        System.assertEquals('A', leftField.fieldName);

        System.assertEquals(FormulaNode.NodeType.FIELD_REFERENCE, binOp.right.getNodeType());
        FormulaNode.FieldReferenceNode rightField = (FormulaNode.FieldReferenceNode)binOp.right;
        System.assertEquals('B', rightField.fieldName);
    }

    @isTest
    static void testParseSimpleComparison_GreaterThan() {
        // Amount > 100
        FormulaNode ast = parseFormula('Amount > 100');

        FormulaNode.BinaryOperatorNode binOp = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('>', binOp.operator);

        FormulaNode.FieldReferenceNode field = (FormulaNode.FieldReferenceNode)binOp.left;
        System.assertEquals('Amount', field.fieldName);

        FormulaNode.LiteralNode literal = (FormulaNode.LiteralNode)binOp.right;
        System.assertEquals(100, literal.value);
    }

    @isTest
    static void testParseSimpleComparison_AllOperators() {
        Map<String, String> operatorTests = new Map<String, String>{
            'A == B' => '==',
            'A != B' => '!=',
            'A > B' => '>',
            'A < B' => '<',
            'A >= B' => '>=',
            'A <= B' => '<='
        };

        for (String formula : operatorTests.keySet()) {
            FormulaNode ast = parseFormula(formula);
            FormulaNode.BinaryOperatorNode binOp = (FormulaNode.BinaryOperatorNode)ast;
            System.assertEquals(operatorTests.get(formula), binOp.operator, 'Failed for: ' + formula);
        }
    }

    // ========== Operator Precedence: NOT > AND > OR ==========

    @isTest
    static void testPrecedence_OrAndNot() {
        // A OR B AND NOT C
        // Should parse as: A OR (B AND (NOT C))
        FormulaNode ast = parseFormula('A OR B AND NOT C');

        // Root should be OR
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, ast.getNodeType());
        FormulaNode.BinaryOperatorNode orNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('OR', orNode.operator);

        // Left should be A
        FormulaNode.FieldReferenceNode leftField = (FormulaNode.FieldReferenceNode)orNode.left;
        System.assertEquals('A', leftField.fieldName);

        // Right should be AND
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, orNode.right.getNodeType());
        FormulaNode.BinaryOperatorNode andNode = (FormulaNode.BinaryOperatorNode)orNode.right;
        System.assertEquals('AND', andNode.operator);

        // AND's right should be NOT
        System.assertEquals(FormulaNode.NodeType.UNARY_OPERATOR, andNode.right.getNodeType());
        FormulaNode.UnaryOperatorNode notNode = (FormulaNode.UnaryOperatorNode)andNode.right;
        System.assertEquals('NOT', notNode.operator);
    }

    @isTest
    static void testPrecedence_NotHighestPriority() {
        // NOT A AND B
        // Should parse as: (NOT A) AND B
        FormulaNode ast = parseFormula('NOT A AND B');

        // Root should be AND
        FormulaNode.BinaryOperatorNode andNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('AND', andNode.operator);

        // Left should be NOT
        System.assertEquals(FormulaNode.NodeType.UNARY_OPERATOR, andNode.left.getNodeType());
        FormulaNode.UnaryOperatorNode notNode = (FormulaNode.UnaryOperatorNode)andNode.left;
        System.assertEquals('NOT', notNode.operator);
    }

    @isTest
    static void testPrecedence_AndOverOr() {
        // A OR B AND C
        // Should parse as: A OR (B AND C)
        FormulaNode ast = parseFormula('A OR B AND C');

        FormulaNode.BinaryOperatorNode orNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('OR', orNode.operator);

        // Right should be AND (higher precedence)
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, orNode.right.getNodeType());
        FormulaNode.BinaryOperatorNode andNode = (FormulaNode.BinaryOperatorNode)orNode.right;
        System.assertEquals('AND', andNode.operator);
    }

    @isTest
    static void testPrecedence_ComplexExpression() {
        // NOT A OR B AND NOT C OR D
        // Should parse as: (NOT A) OR (B AND (NOT C)) OR D
        FormulaNode ast = parseFormula('NOT A OR B AND NOT C OR D');

        // Root should be OR
        FormulaNode.BinaryOperatorNode orNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('OR', orNode.operator);

        // The structure should have OR at the root level (left-associative)
        // Left side should eventually contain NOT A
        // Right side or nested should contain B AND NOT C
    }

    @isTest
    static void testPrecedence_MultipleNots() {
        // NOT NOT A
        // Should parse as: NOT (NOT A)
        FormulaNode ast = parseFormula('NOT NOT A');

        FormulaNode.UnaryOperatorNode outerNot = (FormulaNode.UnaryOperatorNode)ast;
        System.assertEquals('NOT', outerNot.operator);

        System.assertEquals(FormulaNode.NodeType.UNARY_OPERATOR, outerNot.operand.getNodeType());
        FormulaNode.UnaryOperatorNode innerNot = (FormulaNode.UnaryOperatorNode)outerNot.operand;
        System.assertEquals('NOT', innerNot.operator);
    }

    // ========== Parentheses ==========

    @isTest
    static void testParentheses_OverridePrecedence() {
        // (A OR B) AND C
        // Parentheses override precedence
        FormulaNode ast = parseFormula('(A OR B) AND C');

        // Root should be AND
        FormulaNode.BinaryOperatorNode andNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('AND', andNode.operator);

        // Left should be OR (due to parentheses)
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, andNode.left.getNodeType());
        FormulaNode.BinaryOperatorNode orNode = (FormulaNode.BinaryOperatorNode)andNode.left;
        System.assertEquals('OR', orNode.operator);
    }

    @isTest
    static void testParentheses_Nested() {
        // ((A AND B) OR (C AND D))
        FormulaNode ast = parseFormula('((A AND B) OR (C AND D))');

        // Root should be OR
        FormulaNode.BinaryOperatorNode orNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('OR', orNode.operator);

        // Both left and right should be AND
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, orNode.left.getNodeType());
        FormulaNode.BinaryOperatorNode leftAnd = (FormulaNode.BinaryOperatorNode)orNode.left;
        System.assertEquals('AND', leftAnd.operator);

        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, orNode.right.getNodeType());
        FormulaNode.BinaryOperatorNode rightAnd = (FormulaNode.BinaryOperatorNode)orNode.right;
        System.assertEquals('AND', rightAnd.operator);
    }

    @isTest
    static void testParentheses_Complex() {
        // (A OR (B AND C)) OR (D AND (E OR F))
        FormulaNode ast = parseFormula('(A OR (B AND C)) OR (D AND (E OR F))');

        // Root should be OR
        FormulaNode.BinaryOperatorNode orNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('OR', orNode.operator);

        // Verify structure is maintained
        System.assertNotEquals(null, orNode.left);
        System.assertNotEquals(null, orNode.right);
    }

    @isTest
    static void testParentheses_WithComparisons() {
        // (Amount > 100) AND (Status == "Active")
        FormulaNode ast = parseFormula('(Amount > 100) AND (Status == "Active")');

        FormulaNode.BinaryOperatorNode andNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('AND', andNode.operator);

        // Both sides should be comparisons
        FormulaNode.BinaryOperatorNode leftComp = (FormulaNode.BinaryOperatorNode)andNode.left;
        System.assertEquals('>', leftComp.operator);

        FormulaNode.BinaryOperatorNode rightComp = (FormulaNode.BinaryOperatorNode)andNode.right;
        System.assertEquals('==', rightComp.operator);
    }

    // ========== Function Calls ==========

    @isTest
    static void testFunction_IsBlank() {
        // ISBLANK(Field__c)
        FormulaNode ast = parseFormula('ISBLANK(Field__c)');

        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, ast.getNodeType());
        FormulaNode.FunctionCallNode func = (FormulaNode.FunctionCallNode)ast;
        System.assertEquals('ISBLANK', func.functionName);
        System.assertEquals(1, func.arguments.size());

        FormulaNode.FieldReferenceNode arg = (FormulaNode.FieldReferenceNode)func.arguments[0];
        System.assertEquals('Field__c', arg.fieldName);
    }

    @isTest
    static void testFunction_AndWithMultipleArgs() {
        // AND(A, B, C)
        FormulaNode ast = parseFormula('AND(A, B, C)');

        FormulaNode.FunctionCallNode func = (FormulaNode.FunctionCallNode)ast;
        System.assertEquals('AND', func.functionName);
        System.assertEquals(3, func.arguments.size());
    }

    @isTest
    static void testFunction_Nested() {
        // AND(ISBLANK(Name), OR(Amount > 1000, Status == "Active"))
        FormulaNode ast = parseFormula('AND(ISBLANK(Name), OR(Amount > 1000, Status == "Active"))');

        FormulaNode.FunctionCallNode andFunc = (FormulaNode.FunctionCallNode)ast;
        System.assertEquals('AND', andFunc.functionName);
        System.assertEquals(2, andFunc.arguments.size());

        // First arg should be ISBLANK
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, andFunc.arguments[0].getNodeType());
        FormulaNode.FunctionCallNode isBlankFunc = (FormulaNode.FunctionCallNode)andFunc.arguments[0];
        System.assertEquals('ISBLANK', isBlankFunc.functionName);

        // Second arg should be OR
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, andFunc.arguments[1].getNodeType());
        FormulaNode.FunctionCallNode orFunc = (FormulaNode.FunctionCallNode)andFunc.arguments[1];
        System.assertEquals('OR', orFunc.functionName);
    }

    @isTest
    static void testFunction_WithComplexExpressions() {
        // CONTAINS(Name, "Test") AND ISNUMBER(Amount)
        FormulaNode ast = parseFormula('CONTAINS(Name, "Test") AND ISNUMBER(Amount)');

        FormulaNode.BinaryOperatorNode andNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('AND', andNode.operator);

        // Both sides should be function calls
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, andNode.left.getNodeType());
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, andNode.right.getNodeType());
    }

    @isTest
    static void testFunction_NoArguments() {
        // Create tokens manually for a no-arg function
        List<FormulaToken> tokens = new List<FormulaToken>{
            new FormulaToken(FormulaToken.TokenType.FUNCTION_NAME, 'TESTFUNC', 0),
            new FormulaToken(FormulaToken.TokenType.LEFT_PAREN, '(', 8),
            new FormulaToken(FormulaToken.TokenType.RIGHT_PAREN, ')', 9),
            new FormulaToken(FormulaToken.TokenType.EOF, '', 10)
        };

        FormulaParser parser = new FormulaParser(tokens);
        FormulaNode ast = parser.parse();

        FormulaNode.FunctionCallNode func = (FormulaNode.FunctionCallNode)ast;
        System.assertEquals('TESTFUNC', func.functionName);
        System.assertEquals(0, func.arguments.size());
    }

    @isTest
    static void testFunction_NestedInExpression() {
        // NOT ISBLANK(Field) AND Status == "Active"
        FormulaNode ast = parseFormula('NOT ISBLANK(Field) AND Status == "Active"');

        FormulaNode.BinaryOperatorNode andNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('AND', andNode.operator);

        // Left should be NOT
        System.assertEquals(FormulaNode.NodeType.UNARY_OPERATOR, andNode.left.getNodeType());
        FormulaNode.UnaryOperatorNode notNode = (FormulaNode.UnaryOperatorNode)andNode.left;

        // NOT's operand should be function
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, notNode.operand.getNodeType());
    }

    // ========== Composed Expressions ==========

    @isTest
    static void testComposed_AndOrCombination() {
        // AND(A, OR(B, C))
        FormulaNode ast = parseFormula('AND(A, OR(B, C))');

        FormulaNode.FunctionCallNode andFunc = (FormulaNode.FunctionCallNode)ast;
        System.assertEquals('AND', andFunc.functionName);

        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, andFunc.arguments[1].getNodeType());
        FormulaNode.FunctionCallNode orFunc = (FormulaNode.FunctionCallNode)andFunc.arguments[1];
        System.assertEquals('OR', orFunc.functionName);
        System.assertEquals(2, orFunc.arguments.size());
    }

    @isTest
    static void testComposed_MixedOperatorsAndFunctions() {
        // ISBLANK(Name) OR (Amount > 100 AND Status != "Inactive")
        FormulaNode ast = parseFormula('ISBLANK(Name) OR (Amount > 100 AND Status != "Inactive")');

        FormulaNode.BinaryOperatorNode orNode = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('OR', orNode.operator);

        // Left should be function
        System.assertEquals(FormulaNode.NodeType.FUNCTION_CALL, orNode.left.getNodeType());

        // Right should be AND
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, orNode.right.getNodeType());
        FormulaNode.BinaryOperatorNode andNode = (FormulaNode.BinaryOperatorNode)orNode.right;
        System.assertEquals('AND', andNode.operator);
    }

    @isTest
    static void testComposed_DeepNesting() {
        // ((A AND B) OR (C AND D)) AND (E OR F)
        FormulaNode ast = parseFormula('((A AND B) OR (C AND D)) AND (E OR F)');

        // Root should be AND
        FormulaNode.BinaryOperatorNode rootAnd = (FormulaNode.BinaryOperatorNode)ast;
        System.assertEquals('AND', rootAnd.operator);

        // Left should be OR
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, rootAnd.left.getNodeType());
        FormulaNode.BinaryOperatorNode leftOr = (FormulaNode.BinaryOperatorNode)rootAnd.left;
        System.assertEquals('OR', leftOr.operator);

        // Right should be OR
        System.assertEquals(FormulaNode.NodeType.BINARY_OPERATOR, rootAnd.right.getNodeType());
        FormulaNode.BinaryOperatorNode rightOr = (FormulaNode.BinaryOperatorNode)rootAnd.right;
        System.assertEquals('OR', rightOr.operator);
    }

    // ========== Error Cases ==========

    @isTest
    static void testError_UnbalancedParentheses_MissingClose() {
        // (A AND B
        try {
            parseFormula('(A AND B');
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('closing parenthesis'));
        }
    }

    @isTest
    static void testError_UnbalancedParentheses_ExtraClose() {
        // A AND B)
        try {
            parseFormula('A AND B)');
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('Unexpected token'));
        }
    }

    @isTest
    static void testError_MissingOperand() {
        // A AND
        try {
            parseFormula('A AND');
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(true, 'Correctly threw exception');
        }
    }

    @isTest
    static void testError_InvalidOperatorSequence() {
        // A AND AND B
        try {
            parseFormula('A AND AND B');
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(true, 'Correctly threw exception');
        }
    }

    @isTest
    static void testError_IncompleteComparison() {
        // > 100
        try {
            parseFormula('> 100');
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('Unexpected token'));
        }
    }

    @isTest
    static void testError_FunctionMissingParenthesis() {
        List<FormulaToken> tokens = new List<FormulaToken>{
            new FormulaToken(FormulaToken.TokenType.FUNCTION_NAME, 'ISBLANK', 0),
            new FormulaToken(FormulaToken.TokenType.FIELD_REF, 'Name', 8),
            new FormulaToken(FormulaToken.TokenType.EOF, '', 12)
        };

        try {
            FormulaParser parser = new FormulaParser(tokens);
            parser.parse();
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('opening parenthesis'));
        }
    }

    @isTest
    static void testError_FunctionMissingCloseParenthesis() {
        try {
            parseFormula('ISBLANK(Name');
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('closing parenthesis'));
        }
    }

    @isTest
    static void testError_EmptyExpression() {
        try {
            FormulaParser parser = new FormulaParser(new List<FormulaToken>());
            parser.parse();
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('No tokens'));
        }
    }

    @isTest
    static void testError_ExtraTokensAfterExpression() {
        List<FormulaToken> tokens = new List<FormulaToken>{
            new FormulaToken(FormulaToken.TokenType.FIELD_REF, 'A', 0),
            new FormulaToken(FormulaToken.TokenType.FIELD_REF, 'B', 2),
            new FormulaToken(FormulaToken.TokenType.EOF, '', 3)
        };

        try {
            FormulaParser parser = new FormulaParser(tokens);
            parser.parse();
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('Unexpected token'));
        }
    }

    @isTest
    static void testError_InvalidTokenType() {
        List<FormulaToken> tokens = new List<FormulaToken>{
            new FormulaToken(FormulaToken.TokenType.COMMA, ',', 0),
            new FormulaToken(FormulaToken.TokenType.EOF, '', 1)
        };

        try {
            FormulaParser parser = new FormulaParser(tokens);
            parser.parse();
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('Unexpected token'));
        }
    }

    @isTest
    static void testError_UnbalancedMultipleParentheses() {
        // ((A AND B) OR C
        try {
            parseFormula('((A AND B) OR C');
            System.assert(false, 'Should have thrown exception');
        } catch (FormulaParser.ParserException e) {
            System.assert(e.getMessage().contains('Unexpected token') ||
                         e.getMessage().contains('closing parenthesis'));
        }
    }

    // ========== Edge Cases ==========

    @isTest
    static void testEdgeCase_SingleLiteral() {
        FormulaNode ast = parseFormula('true');
        System.assertEquals(FormulaNode.NodeType.LITERAL, ast.getNodeType());
    }

    @isTest
    static void testEdgeCase_SingleField() {
        FormulaNode ast = parseFormula('FieldName');
        System.assertEquals(FormulaNode.NodeType.FIELD_REFERENCE, ast.getNodeType());
    }

    @isTest
    static void testEdgeCase_ExcessiveParentheses() {
        // ((((A))))
        FormulaNode ast = parseFormula('((((A))))');
        System.assertEquals(FormulaNode.NodeType.FIELD_REFERENCE, ast.getNodeType());
        FormulaNode.FieldReferenceNode field = (FormulaNode.FieldReferenceNode)ast;
        System.assertEquals('A', field.fieldName);
    }

    @isTest
    static void testEdgeCase_ComplexFieldNames() {
        // Account__r.Name
        FormulaNode ast = parseFormula('Account__r');
        FormulaNode.FieldReferenceNode field = (FormulaNode.FieldReferenceNode)ast;
        System.assertEquals('Account__r', field.fieldName);
    }

    @isTest
    static void testEdgeCase_StringWithSpaces() {
        // Name == "John Doe"
        FormulaNode ast = parseFormula('Name == "John Doe"');
        FormulaNode.BinaryOperatorNode binOp = (FormulaNode.BinaryOperatorNode)ast;
        FormulaNode.LiteralNode literal = (FormulaNode.LiteralNode)binOp.right;
        System.assertEquals('John Doe', literal.value);
    }

    // ========== AST Structure Validation ==========

    @isTest
    static void testAST_ToString() {
        FormulaNode ast = parseFormula('A AND B OR C');
        String astString = ast.toString();
        System.assertNotEquals(null, astString);
        System.assert(astString.contains('OR'));
    }

    @isTest
    static void testAST_ComplexToString() {
        FormulaNode ast = parseFormula('AND(ISBLANK(Name), Amount > 100)');
        String astString = ast.toString();
        System.assert(astString.contains('AND'));
        System.assert(astString.contains('ISBLANK'));
    }
}
