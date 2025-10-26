/**
 * @description Demo class showing FormulaParser usage and AST visualization
 * @author Claude
 * @date 2025-10-26
 */
public class FormulaParserDemo {

    /**
     * @description Parses a formula and returns the AST
     * @param formula Formula string to parse
     * @return Root AST node
     */
    public static FormulaNode parseFormula(String formula) {
        // Step 1: Tokenize
        FormulaTokenizer tokenizer = new FormulaTokenizer(formula);
        List<FormulaToken> tokens = tokenizer.tokenize();

        // Step 2: Parse
        FormulaParser parser = new FormulaParser(tokens);
        FormulaNode ast = parser.parse();

        return ast;
    }

    /**
     * @description Parses and visualizes the AST for a formula
     * @param formula Formula string to parse
     * @return String representation of the AST
     */
    public static String visualizeAST(String formula) {
        FormulaNode ast = parseFormula(formula);
        return 'Formula: ' + formula + '\nAST: ' + ast.toString() + '\nTree:\n' + printTree(ast, '', true);
    }

    /**
     * @description Prints the AST as a tree structure
     * @param node Current node
     * @param prefix Prefix for current line
     * @param isTail Whether this is the last child
     * @return String representation of tree
     */
    private static String printTree(FormulaNode node, String prefix, Boolean isTail) {
        if (node == null) return '';

        String result = prefix + (isTail ? '└── ' : '├── ');
        FormulaNode.NodeType nodeType = node.getNodeType();

        if (nodeType == FormulaNode.NodeType.LITERAL) {
            FormulaNode.LiteralNode lit = (FormulaNode.LiteralNode)node;
            result += 'Literal: ' + lit.toString() + ' (type: ' + lit.literalType + ')\n';
        } else if (nodeType == FormulaNode.NodeType.FIELD_REFERENCE) {
            FormulaNode.FieldReferenceNode field = (FormulaNode.FieldReferenceNode)node;
            result += 'Field: ' + field.fieldName + '\n';
        } else if (nodeType == FormulaNode.NodeType.BINARY_OPERATOR) {
            FormulaNode.BinaryOperatorNode binOp = (FormulaNode.BinaryOperatorNode)node;
            result += 'BinaryOp: ' + binOp.operator + '\n';
            String childPrefix = prefix + (isTail ? '    ' : '│   ');
            result += printTree(binOp.left, childPrefix, false);
            result += printTree(binOp.right, childPrefix, true);
        } else if (nodeType == FormulaNode.NodeType.UNARY_OPERATOR) {
            FormulaNode.UnaryOperatorNode unOp = (FormulaNode.UnaryOperatorNode)node;
            result += 'UnaryOp: ' + unOp.operator + '\n';
            String childPrefix = prefix + (isTail ? '    ' : '│   ');
            result += printTree(unOp.operand, childPrefix, true);
        } else if (nodeType == FormulaNode.NodeType.FUNCTION_CALL) {
            FormulaNode.FunctionCallNode func = (FormulaNode.FunctionCallNode)node;
            result += 'Function: ' + func.functionName + ' (' + func.arguments.size() + ' args)\n';
            String childPrefix = prefix + (isTail ? '    ' : '│   ');
            for (Integer i = 0; i < func.arguments.size(); i++) {
                Boolean isLast = (i == func.arguments.size() - 1);
                result += printTree(func.arguments[i], childPrefix, isLast);
            }
        }

        return result;
    }

    /**
     * @description Demo method showing various parsing examples
     */
    public static void runExamples() {
        System.debug('========== FORMULA PARSER DEMO ==========\n');

        // Example 1: Simple comparison
        System.debug('--- Example 1: Simple Comparison ---');
        System.debug(visualizeAST('Amount > 100'));
        System.debug('\n');

        // Example 2: Logical operators with precedence
        System.debug('--- Example 2: Operator Precedence (NOT > AND > OR) ---');
        System.debug(visualizeAST('A OR B AND NOT C'));
        System.debug('Note: Parsed as A OR (B AND (NOT C))\n');

        // Example 3: Parentheses
        System.debug('--- Example 3: Parentheses Override Precedence ---');
        System.debug(visualizeAST('(A OR B) AND C'));
        System.debug('\n');

        // Example 4: Function call
        System.debug('--- Example 4: Function Call ---');
        System.debug(visualizeAST('ISBLANK(Name)'));
        System.debug('\n');

        // Example 5: Nested functions
        System.debug('--- Example 5: Nested Functions ---');
        System.debug(visualizeAST('AND(ISBLANK(Name), OR(Amount > 1000, Status == "Active"))'));
        System.debug('\n');

        // Example 6: Multiple parentheses levels
        System.debug('--- Example 6: Multiple Nested Parentheses ---');
        System.debug(visualizeAST('((A AND B) OR (C AND D))'));
        System.debug('\n');

        // Example 7: Complex expression
        System.debug('--- Example 7: Complex Expression ---');
        System.debug(visualizeAST('IF(Amount > 1000, UPPER(Status), LOWER(Status))'));
        System.debug('\n');

        // Example 8: All comparison operators
        System.debug('--- Example 8: Comparison Operators ---');
        List<String> comparisons = new List<String>{
            'A == B', 'A != B', 'A > B', 'A < B', 'A >= B', 'A <= B'
        };
        for (String comp : comparisons) {
            FormulaNode ast = parseFormula(comp);
            System.debug(comp + ' => AST: ' + ast.toString());
        }
        System.debug('\n');
    }

    /**
     * @description Validates that a formula can be parsed
     * @param formula Formula to validate
     * @return true if valid, false otherwise
     */
    public static Boolean validateFormula(String formula) {
        try {
            parseFormula(formula);
            return true;
        } catch (Exception e) {
            System.debug('Invalid formula: ' + formula);
            System.debug('Error: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Demo of error handling
     */
    public static void runErrorExamples() {
        System.debug('========== ERROR HANDLING DEMO ==========\n');

        List<String> invalidFormulas = new List<String>{
            '(A AND B',                    // Missing closing parenthesis
            'A AND',                       // Missing right operand
            'ISBLANK(',                    // Incomplete function
            'A B C',                       // Invalid syntax
            '> 100',                       // Missing left operand
            'UNKNOWN(Field)',              // Unknown function (tokenized as field)
            '((A OR B)',                   // Unbalanced parentheses
            'AND(A, B, )',                 // Trailing comma
            'Field..Name'                  // Invalid field syntax (multiple dots)
        };

        for (String formula : invalidFormulas) {
            System.debug('Testing: ' + formula);
            validateFormula(formula);
            System.debug('---');
        }
    }

    /**
     * @description Shows operator precedence in action
     */
    public static void demonstratePrecedence() {
        System.debug('========== OPERATOR PRECEDENCE DEMO ==========');
        System.debug('Precedence (highest to lowest): NOT > AND > OR\n');

        Map<String, String> examples = new Map<String, String>{
            'A OR B AND C' => 'A OR (B AND C)',
            'NOT A AND B' => '(NOT A) AND B',
            'A AND NOT B OR C' => '(A AND (NOT B)) OR C',
            'NOT A OR B AND C' => '(NOT A) OR (B AND C)',
            'A OR B OR C AND D' => 'A OR B OR (C AND D)'
        };

        for (String formula : examples.keySet()) {
            System.debug('Formula: ' + formula);
            FormulaNode ast = parseFormula(formula);
            System.debug('Parsed as: ' + ast.toString());
            System.debug('Expected: ' + examples.get(formula));
            System.debug('---\n');
        }
    }

    /**
     * @description Compares tokenization and parsing stages
     */
    public static void showPipelineStages(String formula) {
        System.debug('========== PARSING PIPELINE ==========');
        System.debug('Input Formula: ' + formula + '\n');

        // Stage 1: Tokenization
        System.debug('STAGE 1: TOKENIZATION');
        FormulaTokenizer tokenizer = new FormulaTokenizer(formula);
        List<FormulaToken> tokens = tokenizer.tokenize();
        System.debug('Tokens (' + tokens.size() + ' total):');
        for (FormulaToken token : tokens) {
            if (token.type != FormulaToken.TokenType.EOF) {
                System.debug('  ' + token.toString());
            }
        }
        System.debug('\n');

        // Stage 2: Parsing
        System.debug('STAGE 2: PARSING (Building AST)');
        FormulaParser parser = new FormulaParser(tokens);
        FormulaNode ast = parser.parse();
        System.debug('AST Root: ' + ast.toString());
        System.debug('\nTree Structure:');
        System.debug(printTree(ast, '', true));
        System.debug('\n');

        // Stage 3: Evaluation (if possible)
        System.debug('STAGE 3: EVALUATION');
        try {
            Map<String, Object> context = new Map<String, Object>{
                'Amount' => 1500,
                'Name' => 'Test',
                'Status' => 'Active',
                'A' => true,
                'B' => false,
                'C' => true
            };
            FormulaEvaluator evaluator = new FormulaEvaluator(context);
            Object result = evaluator.evaluateNode(ast);
            System.debug('Result: ' + result + ' (type: ' + (result != null ? String.valueOf(result).getType() : 'null') + ')');
        } catch (Exception e) {
            System.debug('Cannot evaluate without proper context: ' + e.getMessage());
        }
    }
}
