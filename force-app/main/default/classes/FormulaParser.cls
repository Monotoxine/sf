/**
 * @description Parser for formula expressions - builds Abstract Syntax Tree
 * @author Claude
 * @date 2025-10-26
 * Uses recursive descent parsing with operator precedence
 */
public class FormulaParser {

    private List<FormulaToken> tokens;
    private Integer position;

    /**
     * @description Constructor
     * @param tokens List of tokens from tokenizer
     */
    public FormulaParser(List<FormulaToken> tokens) {
        this.tokens = tokens != null ? tokens : new List<FormulaToken>();
        this.position = 0;
    }

    /**
     * @description Parses the tokens and returns the root AST node
     * @return Root AST node
     * @throws ParserException if syntax error is encountered
     */
    public FormulaNode parse() {
        if (tokens.isEmpty()) {
            throw new ParserException('No tokens to parse');
        }

        FormulaNode root = parseOrExpression();

        if (!currentToken().isType(FormulaToken.TokenType.EOF)) {
            throw new ParserException('Unexpected token after expression: ' + currentToken().value);
        }

        return root;
    }

    /**
     * @description Parses OR expressions (lowest precedence)
     * Grammar: orExpr = andExpr ( 'OR' andExpr )*
     */
    private FormulaNode parseOrExpression() {
        FormulaNode left = parseAndExpression();

        while (currentToken().isType(FormulaToken.TokenType.OP_OR)) {
            advance();
            FormulaNode right = parseAndExpression();
            left = new FormulaNode.BinaryOperatorNode('OR', left, right);
        }

        return left;
    }

    /**
     * @description Parses AND expressions
     * Grammar: andExpr = notExpr ( 'AND' notExpr )*
     */
    private FormulaNode parseAndExpression() {
        FormulaNode left = parseNotExpression();

        while (currentToken().isType(FormulaToken.TokenType.OP_AND)) {
            advance();
            FormulaNode right = parseNotExpression();
            left = new FormulaNode.BinaryOperatorNode('AND', left, right);
        }

        return left;
    }

    /**
     * @description Parses NOT expressions
     * Grammar: notExpr = 'NOT' notExpr | comparisonExpr
     */
    private FormulaNode parseNotExpression() {
        if (currentToken().isType(FormulaToken.TokenType.OP_NOT)) {
            advance();
            FormulaNode operand = parseNotExpression();
            return new FormulaNode.UnaryOperatorNode('NOT', operand);
        }

        return parseComparisonExpression();
    }

    /**
     * @description Parses comparison expressions
     * Grammar: comparisonExpr = primary ( comparisonOp primary )?
     */
    private FormulaNode parseComparisonExpression() {
        FormulaNode left = parsePrimary();

        if (currentToken().isComparisonOperator()) {
            String operator = getOperatorString(currentToken().type);
            advance();
            FormulaNode right = parsePrimary();
            return new FormulaNode.BinaryOperatorNode(operator, left, right);
        }

        return left;
    }

    /**
     * @description Parses primary expressions (highest precedence)
     * Grammar: primary = literal | field | function | '(' orExpr ')'
     */
    private FormulaNode parsePrimary() {
        FormulaToken token = currentToken();

        // Parenthesized expression
        if (token.isType(FormulaToken.TokenType.LEFT_PAREN)) {
            advance();
            FormulaNode expr = parseOrExpression();
            expect(FormulaToken.TokenType.RIGHT_PAREN, 'Expected closing parenthesis');
            return expr;
        }

        // Function call
        if (token.isType(FormulaToken.TokenType.FUNCTION_NAME)) {
            return parseFunctionCall();
        }

        // Literal values
        if (token.isType(FormulaToken.TokenType.STRING_LITERAL)) {
            advance();
            return new FormulaNode.LiteralNode(token.value, 'STRING');
        }

        if (token.isType(FormulaToken.TokenType.NUMBER_LITERAL)) {
            advance();
            Decimal numValue = Decimal.valueOf(token.value);
            return new FormulaNode.LiteralNode(numValue, 'NUMBER');
        }

        if (token.isType(FormulaToken.TokenType.BOOLEAN_LITERAL)) {
            advance();
            Boolean boolValue = token.value == 'true';
            return new FormulaNode.LiteralNode(boolValue, 'BOOLEAN');
        }

        if (token.isType(FormulaToken.TokenType.NULL_LITERAL)) {
            advance();
            return new FormulaNode.LiteralNode(null, 'NULL');
        }

        // Field reference
        if (token.isType(FormulaToken.TokenType.FIELD_REF)) {
            advance();
            return new FormulaNode.FieldReferenceNode(token.value);
        }

        throw new ParserException('Unexpected token: ' + token.value + ' at position ' + token.position);
    }

    /**
     * @description Parses a function call
     * Grammar: functionCall = FUNCTION '(' argumentList? ')'
     */
    private FormulaNode parseFunctionCall() {
        FormulaToken funcToken = currentToken();
        String functionName = funcToken.value;
        advance();

        expect(FormulaToken.TokenType.LEFT_PAREN, 'Expected opening parenthesis after function name');

        List<FormulaNode> arguments = new List<FormulaNode>();

        // Parse arguments
        if (!currentToken().isType(FormulaToken.TokenType.RIGHT_PAREN)) {
            arguments.add(parseOrExpression());

            while (currentToken().isType(FormulaToken.TokenType.COMMA)) {
                advance();
                arguments.add(parseOrExpression());
            }
        }

        expect(FormulaToken.TokenType.RIGHT_PAREN, 'Expected closing parenthesis after function arguments');

        return new FormulaNode.FunctionCallNode(functionName, arguments);
    }

    /**
     * @description Returns the current token without advancing
     * @return Current token
     */
    private FormulaToken currentToken() {
        if (position >= tokens.size()) {
            return tokens[tokens.size() - 1]; // Return EOF
        }
        return tokens[position];
    }

    /**
     * @description Advances to the next token
     */
    private void advance() {
        if (position < tokens.size() - 1) {
            position++;
        }
    }

    /**
     * @description Expects a specific token type and advances
     * @param expectedType The expected token type
     * @param errorMessage Error message if token doesn't match
     * @throws ParserException if token doesn't match
     */
    private void expect(FormulaToken.TokenType expectedType, String errorMessage) {
        if (!currentToken().isType(expectedType)) {
            throw new ParserException(errorMessage + ' (found "' + currentToken().value + '" at position ' + currentToken().position + ')');
        }
        advance();
    }

    /**
     * @description Converts token type to operator string
     * @param tokenType Token type
     * @return Operator string
     */
    private String getOperatorString(FormulaToken.TokenType tokenType) {
        if (tokenType == FormulaToken.TokenType.OP_EQ) return '==';
        if (tokenType == FormulaToken.TokenType.OP_NEQ) return '!=';
        if (tokenType == FormulaToken.TokenType.OP_GT) return '>';
        if (tokenType == FormulaToken.TokenType.OP_LT) return '<';
        if (tokenType == FormulaToken.TokenType.OP_GTE) return '>=';
        if (tokenType == FormulaToken.TokenType.OP_LTE) return '<=';
        if (tokenType == FormulaToken.TokenType.OP_AND) return 'AND';
        if (tokenType == FormulaToken.TokenType.OP_OR) return 'OR';
        if (tokenType == FormulaToken.TokenType.OP_NOT) return 'NOT';
        return tokenType.name();
    }

    /**
     * @description Exception class for parser errors
     */
    public class ParserException extends Exception {}
}
