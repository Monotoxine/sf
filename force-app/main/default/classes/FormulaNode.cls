/**
 * @description Abstract Syntax Tree (AST) node for formula expressions
 * @author Claude
 * @date 2025-10-26
 */
public abstract class FormulaNode {

    /**
     * @description Enum representing different node types
     */
    public enum NodeType {
        LITERAL,
        FIELD_REFERENCE,
        BINARY_OPERATOR,
        UNARY_OPERATOR,
        FUNCTION_CALL
    }

    public abstract NodeType getNodeType();
    public abstract override String toString();
    /**
     * @description Literal node (string, number, boolean, null)
     */
    public class LiteralNode extends FormulaNode {
        public Object value { get; private set; }
        public String literalType { get; private set; } // 'STRING', 'NUMBER', 'BOOLEAN', 'NULL'

        public LiteralNode(Object value, String literalType) {
            this.value = value;
            this.literalType = literalType;
        }

        public override NodeType getNodeType() {
            return NodeType.LITERAL;
        }

        public override String toString() {
            if (literalType == 'STRING') {
                return '"' + String.valueOf(value) + '"';
            } else if (literalType == 'NULL') {
                return 'null';
            }
            return String.valueOf(value);
        }
    }

    /**
     * @description Field reference node
     */
    public class FieldReferenceNode extends FormulaNode {
        public String fieldName { get; private set; }

        public FieldReferenceNode(String fieldName) {
            this.fieldName = fieldName;
        }

        public override NodeType getNodeType() {
            return NodeType.FIELD_REFERENCE;
        }

        public override String toString() {
            return fieldName;
        }
    }

    /**
     * @description Binary operator node (e.g., AND, OR, ==, !=, >, <, >=, <=)
     */
    public class BinaryOperatorNode extends FormulaNode {
        public String operator { get; private set; }
        public FormulaNode left { get; private set; }
        public FormulaNode right { get; private set; }

        public BinaryOperatorNode(String operator, FormulaNode left, FormulaNode right) {
            this.operator = operator;
            this.left = left;
            this.right = right;
        }

        public override NodeType getNodeType() {
            return NodeType.BINARY_OPERATOR;
        }

        public override String toString() {
            return '(' + left.toString() + ' ' + operator + ' ' + right.toString() + ')';
        }
    }

    /**
     * @description Unary operator node (e.g., NOT)
     */
    public class UnaryOperatorNode extends FormulaNode {
        public String operator { get; private set; }
        public FormulaNode operand { get; private set; }

        public UnaryOperatorNode(String operator, FormulaNode operand) {
            this.operator = operator;
            this.operand = operand;
        }

        public override NodeType getNodeType() {
            return NodeType.UNARY_OPERATOR;
        }

        public override String toString() {
            return operator + '(' + operand.toString() + ')';
        }
    }

    /**
     * @description Function call node (e.g., ISBLANK(field), CONTAINS(text, search))
     */
    public class FunctionCallNode extends FormulaNode {
        public String functionName { get; private set; }
        public List<FormulaNode> arguments { get; private set; }

        public FunctionCallNode(String functionName, List<FormulaNode> arguments) {
            this.functionName = functionName;
            this.arguments = arguments != null ? arguments : new List<FormulaNode>();
        }

        public override NodeType getNodeType() {
            return NodeType.FUNCTION_CALL;
        }

        public override String toString() {
            List<String> argStrings = new List<String>();
            for (FormulaNode arg : arguments) {
                argStrings.add(arg.toString());
            }
            return functionName + '(' + String.join(argStrings, ', ') + ')';
        }
    }
}
