/**
 * @description Represents a token in a formula expression
 * @author Claude
 * @date 2025-10-26
 */
public class FormulaToken {

    /**
     * @description Enum representing different token types
     */
    public enum TokenType {
        // Literals
        STRING_LITERAL,    // "text"
        NUMBER_LITERAL,    // 123, 45.67
        BOOLEAN_LITERAL,   // true, false
        NULL_LITERAL,      // null
        FIELD_REF,         // Field__c, Name, etc.

        // Comparison operators
        OP_EQ,             // ==
        OP_NEQ,            // !=
        OP_GT,             // >
        OP_LT,             // <
        OP_GTE,            // >=
        OP_LTE,            // <=

        // Logical operators
        OP_AND,            // AND
        OP_OR,             // OR
        OP_NOT,            // NOT

        // Functions
        FUNCTION_NAME,     // ISBLANK, ISNUMBER, etc.

        // Delimiters
        LEFT_PAREN,            // (
        RIGHT_PAREN,            // )
        COMMA,             // ,

        // End of input
        EOF
    }

    public TokenType type { get; private set; }
    public String value { get; private set; }
    public Integer position { get; private set; }

    /**
     * @description Constructor
     * @param type The token type
     * @param value The token value
     * @param position Position in the formula string
     */
    public FormulaToken(TokenType type, String value, Integer position) {
        this.type = type;
        this.value = value;
        this.position = position;
    }

    /**
     * @description Returns a string representation of the token
     * @return String representation
     */
    public override String toString() {
        return String.format('Token({0}, "{1}", pos={2})',
            new List<String>{
                String.valueOf(type),
                value,
                String.valueOf(position)
            });
    }

    /**
     * @description Checks if this token matches the expected type
     * @param expectedType The expected token type
     * @return true if types match
     */
    public Boolean isType(TokenType expectedType) {
        return this.type == expectedType;
    }

    /**
     * @description Checks if this token is an operator
     * @return true if token is an operator
     */
    public Boolean isOperator() {
        return type == TokenType.OP_EQ ||
               type == TokenType.OP_NEQ ||
               type == TokenType.OP_GT ||
               type == TokenType.OP_LT ||
               type == TokenType.OP_GTE ||
               type == TokenType.OP_LTE ||
               type == TokenType.OP_AND ||
               type == TokenType.OP_OR ||
               type == TokenType.OP_NOT;
    }

    /**
     * @description Checks if this token is a logical operator (AND, OR, NOT)
     * @return true if token is a logical operator
     */
    public Boolean isLogicalOperator() {
        return type == TokenType.OP_AND ||
               type == TokenType.OP_OR ||
               type == TokenType.OP_NOT;
    }

    /**
     * @description Checks if this token is a comparison operator
     * @return true if token is a comparison operator
     */
    public Boolean isComparisonOperator() {
        return type == TokenType.OP_EQ ||
               type == TokenType.OP_NEQ ||
               type == TokenType.OP_GT ||
               type == TokenType.OP_LT ||
               type == TokenType.OP_GTE ||
               type == TokenType.OP_LTE;
    }
}
