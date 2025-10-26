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
        STRING,           // "text"
        NUMBER,           // 123, 45.67
        BOOLEAN,          // true, false
        NULL_LITERAL,     // null
        FIELD,            // Field__c, Name, etc.

        // Operators
        EQUALS,           // ==
        NOT_EQUALS,       // !=
        GREATER_THAN,     // >
        LESS_THAN,        // <
        GREATER_EQUAL,    // >=
        LESS_EQUAL,       // <=

        // Logical operators
        AND,              // AND
        OR,               // OR
        NOT,              // NOT

        // Functions
        FUNCTION,         // ISBLANK, ISNUMBER, etc.

        // Delimiters
        LEFT_PAREN,       // (
        RIGHT_PAREN,      // )
        COMMA,            // ,

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
        return type == TokenType.EQUALS ||
               type == TokenType.NOT_EQUALS ||
               type == TokenType.GREATER_THAN ||
               type == TokenType.LESS_THAN ||
               type == TokenType.GREATER_EQUAL ||
               type == TokenType.LESS_EQUAL ||
               type == TokenType.AND ||
               type == TokenType.OR ||
               type == TokenType.NOT;
    }

    /**
     * @description Checks if this token is a logical operator (AND, OR, NOT)
     * @return true if token is a logical operator
     */
    public Boolean isLogicalOperator() {
        return type == TokenType.AND ||
               type == TokenType.OR ||
               type == TokenType.NOT;
    }

    /**
     * @description Checks if this token is a comparison operator
     * @return true if token is a comparison operator
     */
    public Boolean isComparisonOperator() {
        return type == TokenType.EQUALS ||
               type == TokenType.NOT_EQUALS ||
               type == TokenType.GREATER_THAN ||
               type == TokenType.LESS_THAN ||
               type == TokenType.GREATER_EQUAL ||
               type == TokenType.LESS_EQUAL;
    }
}
