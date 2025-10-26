/**
 * @description Evaluates formula Abstract Syntax Tree with sObject context
 * @author Claude
 * @date 2025-10-26
 */
public class FormulaEvaluator {

    private SObject record;
    private Map<String, Object> contextMap;

    /**
     * @description Constructor with sObject
     * @param record The sObject to evaluate against
     */
    public FormulaEvaluator(SObject record) {
        this.record = record;
        this.contextMap = new Map<String, Object>();
    }

    /**
     * @description Constructor with context map
     * @param contextMap Map of field names to values
     */
    public FormulaEvaluator(Map<String, Object> contextMap) {
        this.contextMap = contextMap != null ? contextMap : new Map<String, Object>();
    }

    /**
     * @description Evaluates a formula string
     * @param formula The formula string to evaluate
     * @return Evaluation result
     */
    public Object evaluate(String formula) {
        FormulaTokenizer tokenizer = new FormulaTokenizer(formula);
        List<FormulaToken> tokens = tokenizer.tokenize();

        FormulaParser parser = new FormulaParser(tokens);
        FormulaNode ast = parser.parse();

        return evaluateNode(ast);
    }

    /**
     * @description Evaluates an AST node
     * @param node The node to evaluate
     * @return Evaluation result
     */
    public Object evaluateNode(FormulaNode node) {
        if (node == null) {
            return null;
        }

        FormulaNode.NodeType nodeType = node.getNodeType();

        if (nodeType == FormulaNode.NodeType.LITERAL) {
            return evaluateLiteral((FormulaNode.LiteralNode)node);
        } else if (nodeType == FormulaNode.NodeType.FIELD_REFERENCE) {
            return evaluateFieldReference((FormulaNode.FieldReferenceNode)node);
        } else if (nodeType == FormulaNode.NodeType.BINARY_OPERATOR) {
            return evaluateBinaryOperator((FormulaNode.BinaryOperatorNode)node);
        } else if (nodeType == FormulaNode.NodeType.UNARY_OPERATOR) {
            return evaluateUnaryOperator((FormulaNode.UnaryOperatorNode)node);
        } else if (nodeType == FormulaNode.NodeType.FUNCTION_CALL) {
            return evaluateFunctionCall((FormulaNode.FunctionCallNode)node);
        }

        throw new EvaluatorException('Unknown node type: ' + nodeType);
    }

    /**
     * @description Evaluates a literal node
     */
    private Object evaluateLiteral(FormulaNode.LiteralNode node) {
        return node.value;
    }

    /**
     * @description Evaluates a field reference (supports relational fields like Account.Owner.Name)
     */
    private Object evaluateFieldReference(FormulaNode.FieldReferenceNode node) {
        String fieldName = node.fieldName;

        // Try context map first
        if (contextMap.containsKey(fieldName)) {
            return contextMap.get(fieldName);
        }

        // Try sObject (supports relational fields with dot notation)
        if (record != null) {
            try {
                // Check if it's a relational field (contains dot)
                if (fieldName.contains('.')) {
                    return getRelationalFieldValue(record, fieldName);
                }
                return record.get(fieldName);
            } catch (Exception e) {
                throw new EvaluatorException('Field not found: ' + fieldName);
            }
        }

        throw new EvaluatorException('No context for field: ' + fieldName);
    }

    /**
     * @description Gets value from relational field path (e.g., Account.Owner.Name)
     * @param obj Starting sObject
     * @param fieldPath Dot-separated field path
     * @return Field value
     */
    private Object getRelationalFieldValue(SObject obj, String fieldPath) {
        if (obj == null || fieldPath == null) {
            return null;
        }

        String[] parts = fieldPath.split('\\.');
        Object currentValue = obj;

        for (Integer i = 0; i < parts.size(); i++) {
            String part = parts[i];

            if (currentValue == null) {
                return null;
            }

            if (currentValue instanceof SObject) {
                SObject currentObj = (SObject)currentValue;

                // Last part or regular field
                if (i == parts.size() - 1 || !part.endsWith('__r')) {
                    currentValue = currentObj.get(part);
                } else {
                    // Relationship field
                    currentValue = currentObj.getSObject(part);
                }
            } else {
                throw new EvaluatorException('Cannot traverse non-SObject value at: ' + part);
            }
        }

        return currentValue;
    }

    /**
     * @description Evaluates a binary operator
     */
    private Object evaluateBinaryOperator(FormulaNode.BinaryOperatorNode node) {
        String operator = node.operator;

        // Logical operators
        if (operator == 'AND') {
            Boolean left = toBoolean(evaluateNode(node.left));
            if (!left) return false; // Short-circuit
            return toBoolean(evaluateNode(node.right));
        } else if (operator == 'OR') {
            Boolean left = toBoolean(evaluateNode(node.left));
            if (left) return true; // Short-circuit
            return toBoolean(evaluateNode(node.right));
        }

        // Comparison operators
        Object leftValue = evaluateNode(node.left);
        Object rightValue = evaluateNode(node.right);

        if (operator == '==') {
            return compareEquals(leftValue, rightValue);
        } else if (operator == '!=') {
            return !compareEquals(leftValue, rightValue);
        } else if (operator == '>') {
            return compareGreaterThan(leftValue, rightValue);
        } else if (operator == '<') {
            return compareLessThan(leftValue, rightValue);
        } else if (operator == '>=') {
            return compareGreaterThan(leftValue, rightValue) || compareEquals(leftValue, rightValue);
        } else if (operator == '<=') {
            return compareLessThan(leftValue, rightValue) || compareEquals(leftValue, rightValue);
        }

        throw new EvaluatorException('Unknown operator: ' + operator);
    }

    /**
     * @description Evaluates a unary operator
     */
    private Object evaluateUnaryOperator(FormulaNode.UnaryOperatorNode node) {
        if (node.operator == 'NOT') {
            return !toBoolean(evaluateNode(node.operand));
        }

        throw new EvaluatorException('Unknown unary operator: ' + node.operator);
    }

    /**
     * @description Evaluates a function call
     */
    private Object evaluateFunctionCall(FormulaNode.FunctionCallNode node) {
        String funcName = node.functionName.toUpperCase();
        List<Object> args = new List<Object>();

        for (FormulaNode argNode : node.arguments) {
            args.add(evaluateNode(argNode));
        }

        // Functions
        if (funcName == 'ISBLANK') {
            return functionIsBlank(args);
        } else if (funcName == 'ISNUMBER') {
            return functionIsNumber(args);
        } else if (funcName == 'ISPICKVAL') {
            return functionIsPickval(args);
        } else if (funcName == 'TEXT') {
            return functionText(args);
        } else if (funcName == 'VALUE') {
            return functionValue(args);
        } else if (funcName == 'LEN') {
            return functionLen(args);
        } else if (funcName == 'CONTAINS') {
            return functionContains(args);
        } else if (funcName == 'BEGINS') {
            return functionBegins(args);
        } else if (funcName == 'UPPER') {
            return functionUpper(args);
        } else if (funcName == 'LOWER') {
            return functionLower(args);
        } else if (funcName == 'TRIM') {
            return functionTrim(args);
        } else if (funcName == 'IF') {
            return functionIf(args, node.arguments);
        } else if (funcName == 'ABS') {
            return functionAbs(args);
        } else if (funcName == 'CEILING') {
            return functionCeiling(args);
        } else if (funcName == 'FLOOR') {
            return functionFloor(args);
        } else if (funcName == 'ROUND') {
            return functionRound(args);
        } else if (funcName == 'MOD') {
            return functionMod(args);
        } else if (funcName == 'TODAY') {
            return functionToday(args);
        } else if (funcName == 'NOW') {
            return functionNow(args);
        }

        throw new EvaluatorException('Unknown function: ' + funcName);
    }

    // ========== Function Implementations ==========

    private Boolean functionIsBlank(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('ISBLANK requires 1 argument');
        Object value = args[0];
        return value == null || String.valueOf(value).trim() == '';
    }

    private Boolean functionIsNumber(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('ISNUMBER requires 1 argument');
        Object value = args[0];
        if (value == null) return false;
        if (value instanceof Decimal || value instanceof Integer || value instanceof Long || value instanceof Double) {
            return true;
        }
        try {
            Decimal.valueOf(String.valueOf(value));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private Boolean functionIsPickval(List<Object> args) {
        if (args.size() != 2) throw new EvaluatorException('ISPICKVAL requires 2 arguments');
        String fieldValue = String.valueOf(args[0]);
        String checkValue = String.valueOf(args[1]);
        return fieldValue == checkValue;
    }

    private String functionText(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('TEXT requires 1 argument');
        return args[0] != null ? String.valueOf(args[0]) : '';
    }

    private Decimal functionValue(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('VALUE requires 1 argument');
        try {
            return Decimal.valueOf(String.valueOf(args[0]));
        } catch (Exception e) {
            throw new EvaluatorException('Cannot convert to number: ' + args[0]);
        }
    }

    private Integer functionLen(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('LEN requires 1 argument');
        String str = args[0] != null ? String.valueOf(args[0]) : '';
        return str.length();
    }

    private Boolean functionContains(List<Object> args) {
        if (args.size() != 2) throw new EvaluatorException('CONTAINS requires 2 arguments');
        String text = args[0] != null ? String.valueOf(args[0]) : '';
        String search = args[1] != null ? String.valueOf(args[1]) : '';
        return text.contains(search);
    }

    private Boolean functionBegins(List<Object> args) {
        if (args.size() != 2) throw new EvaluatorException('BEGINS requires 2 arguments');
        String text = args[0] != null ? String.valueOf(args[0]) : '';
        String prefix = args[1] != null ? String.valueOf(args[1]) : '';
        return text.startsWith(prefix);
    }

    private String functionUpper(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('UPPER requires 1 argument');
        String str = args[0] != null ? String.valueOf(args[0]) : '';
        return str.toUpperCase();
    }

    private String functionLower(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('LOWER requires 1 argument');
        String str = args[0] != null ? String.valueOf(args[0]) : '';
        return str.toLowerCase();
    }

    private String functionTrim(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('TRIM requires 1 argument');
        String str = args[0] != null ? String.valueOf(args[0]) : '';
        return str.trim();
    }

    private Object functionIf(List<Object> args, List<FormulaNode> argNodes) {
        if (args.size() != 3) throw new EvaluatorException('IF requires 3 arguments');
        // Evaluate condition first
        Boolean condition = toBoolean(args[0]);
        // Only evaluate the branch we need (short-circuit)
        if (condition) {
            return evaluateNode(argNodes[1]);
        } else {
            return evaluateNode(argNodes[2]);
        }
    }

    private Decimal functionAbs(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('ABS requires 1 argument');
        Decimal num = toDecimal(args[0]);
        return num.abs();
    }

    private Integer functionCeiling(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('CEILING requires 1 argument');
        Decimal num = toDecimal(args[0]);
        return num.round(System.RoundingMode.CEILING);
    }

    private Integer functionFloor(List<Object> args) {
        if (args.size() != 1) throw new EvaluatorException('FLOOR requires 1 argument');
        Decimal num = toDecimal(args[0]);
        return num.round(System.RoundingMode.FLOOR);
    }

    private Decimal functionRound(List<Object> args) {
        if (args.size() < 1 || args.size() > 2) throw new EvaluatorException('ROUND requires 1 or 2 arguments');
        Decimal num = toDecimal(args[0]);
        Integer decimals = args.size() == 2 ? Integer.valueOf(args[1]) : 0;
        return num.setScale(decimals, System.RoundingMode.HALF_UP);
    }

    private Decimal functionMod(List<Object> args) {
        if (args.size() != 2) throw new EvaluatorException('MOD requires 2 arguments');
        Decimal num = toDecimal(args[0]);
        Decimal divisor = toDecimal(args[1]);
        return Math.mod(num.intValue(), divisor.intValue());
    }

    private Date functionToday(List<Object> args) {
        if (args.size() != 0) throw new EvaluatorException('TODAY requires 0 arguments');
        return Date.today();
    }

    private Datetime functionNow(List<Object> args) {
        if (args.size() != 0) throw new EvaluatorException('NOW requires 0 arguments');
        return Datetime.now();
    }

    // ========== Helper Methods ==========

    private Boolean toBoolean(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean)value;
        String str = String.valueOf(value).toLowerCase();
        return str == 'true' || str == '1';
    }

    private Decimal toDecimal(Object value) {
        if (value == null) return 0;
        if (value instanceof Decimal) return (Decimal)value;
        if (value instanceof Integer) return Decimal.valueOf((Integer)value);
        if (value instanceof Long) return Decimal.valueOf((Long)value);
        if (value instanceof Double) return Decimal.valueOf((Double)value);
        return Decimal.valueOf(String.valueOf(value));
    }

    private Boolean compareEquals(Object left, Object right) {
        if (left == null && right == null) return true;
        if (left == null || right == null) return false;

        // Try numeric comparison
        if (isNumeric(left) && isNumeric(right)) {
            return toDecimal(left) == toDecimal(right);
        }

        // String comparison
        return String.valueOf(left) == String.valueOf(right);
    }

    private Boolean compareGreaterThan(Object left, Object right) {
        if (left == null || right == null) return false;

        if (isNumeric(left) && isNumeric(right)) {
            return toDecimal(left) > toDecimal(right);
        }

        // Date comparison
        if (left instanceof Date && right instanceof Date) {
            return (Date)left > (Date)right;
        }
        if (left instanceof Datetime && right instanceof Datetime) {
            return (Datetime)left > (Datetime)right;
        }

        // String comparison
        return String.valueOf(left) > String.valueOf(right);
    }

    private Boolean compareLessThan(Object left, Object right) {
        if (left == null || right == null) return false;

        if (isNumeric(left) && isNumeric(right)) {
            return toDecimal(left) < toDecimal(right);
        }

        // Date comparison
        if (left instanceof Date && right instanceof Date) {
            return (Date)left < (Date)right;
        }
        if (left instanceof Datetime && right instanceof Datetime) {
            return (Datetime)left < (Datetime)right;
        }

        // String comparison
        return String.valueOf(left) < String.valueOf(right);
    }

    private Boolean isNumeric(Object value) {
        return value instanceof Decimal || value instanceof Integer ||
               value instanceof Long || value instanceof Double;
    }

    /**
     * @description Exception class for evaluation errors
     */
    public class EvaluatorException extends Exception {}
}
