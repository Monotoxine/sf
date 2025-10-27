/**
 * @description Tokenizer for formula expressions - performs lexical analysis
 * @author Claude
 * @date 2025-10-26
 * Complexity: O(n) where n is the length of the formula string
 */
public class FormulaTokenizer {

    private String formula;
    private Integer position;
    private Integer length;

    private static final Set<String> KEYWORDS = new Set<String>{
        'AND', 'OR', 'NOT', 'true', 'false', 'null'
    };

    private static final Set<String> FUNCTIONS = new Set<String>{
        'ISBLANK', 'ISNUMBER', 'ISPICKVAL', 'TEXT', 'VALUE',
        'LEN', 'CONTAINS', 'BEGINS', 'IF', 'CASE', 'MOD',
        'ABS', 'CEILING', 'FLOOR', 'ROUND', 'UPPER', 'LOWER',
        'LEFT', 'RIGHT', 'MID', 'TRIM', 'SUBSTITUTE', 'FIND',
        'TODAY', 'NOW'
    };

    /**
     * @description Constructor
     * @param formula The formula string to tokenize
     */
    public FormulaTokenizer(String formula) {
        this.formula = formula != null ? formula : '';
        this.position = 0;
        this.length = this.formula.length();
    }

    /**
     * @description Tokenizes the formula and returns a list of tokens
     * @return List of tokens
     * @throws FormulaException if invalid syntax is encountered
     */
    public List<FormulaToken> tokenize() {
        List<FormulaToken> tokens = new List<FormulaToken>();

        while (position < length) {
            // Skip whitespace
            if (isWhitespace(currentChar())) {
                advance();
                continue;
            }

            FormulaToken token = nextToken();
            if (token != null) {
                tokens.add(token);
            }
        }

        // Add EOF token
        tokens.add(new FormulaToken(FormulaToken.TokenType.EOF, '', position));
        return tokens;
    }

    /**
     * @description Gets the next token from the formula
     * @return The next token
     * @throws FormulaException if invalid character is encountered
     */
    private FormulaToken nextToken() {
        String ch = currentChar();
        Integer startPos = position;

        // String literals
        if (ch == '"' || ch == '\'') {
            return tokenizeString(ch);
        }

        // Numbers
        if (isDigit(ch)) {
            return tokenizeNumber();
        }

        // Identifiers (fields, keywords, functions)
        if (isAlpha(ch) || ch == '_') {
            return tokenizeIdentifier();
        }

        // Two-character operators
        if (position + 1 < length) {
            String twoChar = formula.substring(position, position + 2);
            FormulaToken.TokenType twoCharType = getTwoCharOperator(twoChar);
            if (twoCharType != null) {
                advance();
                advance();
                return new FormulaToken(twoCharType, twoChar, startPos);
            }
        }

        // Single-character operators and delimiters
        FormulaToken.TokenType singleCharType = getSingleCharOperator(ch);
        if (singleCharType != null) {
            advance();
            return new FormulaToken(singleCharType, ch, startPos);
        }

        // Unknown character
        throw new FormulaException('Unexpected character "' + ch + '" at position ' + position);
    }

    /**
     * @description Tokenizes a string literal
     * @param quote The quote character (single or double)
     * @return String token
     */
    private FormulaToken tokenizeString(String quote) {
        Integer startPos = position;
        advance(); // Skip opening quote

        StringBuilder sb = new StringBuilder();

        while (position < length && currentChar() != quote) {
            String ch = currentChar();

            // Handle escape sequences
            if (ch == '\\' && position + 1 < length) {
                advance();
                String escaped = currentChar();
                if (escaped == 'n') {
                    sb.append('\n');
                } else if (escaped == 't') {
                    sb.append('\t');
                } else if (escaped == 'r') {
                    sb.append('\r');
                } else if (escaped == '\\') {
                    sb.append('\\');
                } else if (escaped == quote) {
                    sb.append(quote);
                } else {
                    sb.append(escaped);
                }
                advance();
            } else {
                sb.append(ch);
                advance();
            }
        }

        if (position >= length) {
            throw new FormulaException('Unterminated string literal starting at position ' + startPos);
        }

        advance(); // Skip closing quote
        return new FormulaToken(FormulaToken.TokenType.STRING_LITERAL, sb.toString(), startPos);
    }

    /**
     * @description Tokenizes a number
     * @return Number token
     */
    private FormulaToken tokenizeNumber() {
        Integer startPos = position;
        StringBuilder sb = new StringBuilder();

        while (position < length && (isDigit(currentChar()) || currentChar() == '.')) {
            sb.append(currentChar());
            advance();
        }

        String numStr = sb.toString();

        // Validate number format
        if (numStr.countMatches('.') > 1) {
            throw new FormulaException('Invalid number format at position ' + startPos);
        }

        return new FormulaToken(FormulaToken.TokenType.NUMBER_LITERAL, numStr, startPos);
    }

    /**
     * @description Tokenizes an identifier (field, keyword, or function)
     * @return Token representing field, keyword, or function
     */
   private FormulaToken tokenizeIdentifier() {
        Integer startPos = position;
        StringBuilder sb = new StringBuilder();

        while (position < length && (isAlphaNumeric(currentChar()) || currentChar() == '_')) {
            sb.append(currentChar());
            advance();
        }

        String identifier = sb.toString();
        String upperIdent = identifier.toUpperCase();

        // --- 1️⃣ Check if it’s a function (followed by '(') ---
        if (FUNCTIONS.contains(upperIdent) || KEYWORDS.contains(upperIdent)) {
            Integer tempPos = position;
            while (tempPos < length && isWhitespace(formula.substring(tempPos, tempPos + 1))) {
                tempPos++;
            }
            if (tempPos < length && formula.substring(tempPos, tempPos + 1) == '(') {
                return new FormulaToken(FormulaToken.TokenType.FUNCTION_NAME, upperIdent, startPos);
            }
        }

        // --- 2️⃣ Logical operators (when not used as functions) ---
        if (upperIdent == 'AND') return new FormulaToken(FormulaToken.TokenType.OP_AND, identifier, startPos);
        if (upperIdent == 'OR')  return new FormulaToken(FormulaToken.TokenType.OP_OR, identifier, startPos);
        if (upperIdent == 'NOT') return new FormulaToken(FormulaToken.TokenType.OP_NOT, identifier, startPos);

        // --- 3️⃣ Literals ---
        if (upperIdent == 'TRUE' || upperIdent == 'FALSE') {
            return new FormulaToken(FormulaToken.TokenType.BOOLEAN_LITERAL, identifier, startPos);
        }
        if (upperIdent == 'NULL') {
            return new FormulaToken(FormulaToken.TokenType.NULL_LITERAL, identifier, startPos);
        }

        // --- 4️⃣ Otherwise, field reference ---
        return new FormulaToken(FormulaToken.TokenType.FIELD_REF, identifier, startPos);
    }

    /**
     * @description Gets the token type for two-character operators
     * @param twoChar Two-character string
     * @return Token type or null
     */
    private FormulaToken.TokenType getTwoCharOperator(String twoChar) {
        if (twoChar == '==') return FormulaToken.TokenType.OP_EQ;
        if (twoChar == '!=') return FormulaToken.TokenType.OP_NEQ;
        if (twoChar == '>=') return FormulaToken.TokenType.OP_GTE;
        if (twoChar == '<=') return FormulaToken.TokenType.OP_LTE;
        return null;
    }

    /**
     * @description Gets the token type for single-character operators
     * @param ch Single character
     * @return Token type or null
     */
    private FormulaToken.TokenType getSingleCharOperator(String ch) {
        if (ch == '(') return FormulaToken.TokenType.LEFT_PAREN;
        if (ch == ')') return FormulaToken.TokenType.RIGHT_PAREN;
        if (ch == ',') return FormulaToken.TokenType.COMMA;
        if (ch == '>') return FormulaToken.TokenType.OP_GT;
        if (ch == '<') return FormulaToken.TokenType.OP_LT;
        if (ch == '=') return FormulaToken.TokenType.OP_EQ;
        return null;
    }

    /**
     * @description Returns the current character without advancing
     * @return Current character or empty string if at end
     */
    private String currentChar() {
        if (position >= length) return '';
        return formula.substring(position, position + 1);
    }

    /**
     * @description Advances the position by one
     */
    private void advance() {
        position++;
    }

    /**
     * @description Checks if a character is whitespace
     * @param ch Character to check
     * @return true if whitespace
     */
    private Boolean isWhitespace(String ch) {
        return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
    }

    /**
     * @description Checks if a character is a digit
     * @param ch Character to check
     * @return true if digit
     */
    private Boolean isDigit(String ch) {
        return ch >= '0' && ch <= '9';
    }

    /**
     * @description Checks if a character is alphabetic
     * @param ch Character to check
     * @return true if alphabetic
     */
    private Boolean isAlpha(String ch) {
        return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
    }

    /**
     * @description Checks if a character is alphanumeric
     * @param ch Character to check
     * @return true if alphanumeric
     */
    private Boolean isAlphaNumeric(String ch) {
        return isAlpha(ch) || isDigit(ch);
    }

    /**
     * @description Simple StringBuilder implementation for Apex
     */
    private class StringBuilder {
        private List<String> parts = new List<String>();

        public void append(String s) {
            parts.add(s);
        }

        public override String toString() {
            return String.join(parts, '');
        }
    }

    /**
     * @description Exception class for formula errors
     */
    public class FormulaException extends Exception {}
}
