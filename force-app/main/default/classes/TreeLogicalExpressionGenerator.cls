/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 01-23-2023
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class TreeLogicalExpressionGenerator {
    private static final String ANDv = 'AND';
    private static final String ORv = 'OR';
    private static final String OPEN = '{';
    private static final String CLOSE = '}';
    public static Node parse(String expression){
        expression = expression.replaceAll('\\|\\|', 'OR').replaceAll('&&', 'AND');
        return evaluate(expression, new Map<String, Node>(), new Node(), 0);
    }
    private static Node evaluate(String expression, Map<String, Node> ref, Node tree, Integer index){
        if(!expression.contains(OPEN)){
            return getNode(expression.trim(), ref, index);
        }

        Integer indexOfOpen = -1;
        Integer indexOfClose = -1;

        String[] chars = expression.split('');
        for(Integer i = 0; i < chars.size(); i++){

            String singleChar = chars[i];

            if(singleChar == OPEN) {
                indexOfOpen = i;
                continue;
            }

            if(singleChar == CLOSE) {
                indexOfClose = i;
                break;
            }
        }
        System.debug('before replace expression+> '+ expression);
        String replace = expression.substring(indexOfOpen + 1 , indexOfClose);
        expression = expression.replace( OPEN + replace + CLOSE, '??aa' + index + 'aa??');
        System.debug('after replaceexpression+> '+ expression);
        String replace1 = replace;//.deleteWhitespace();
        Node currentNode = getNode(replace1, ref, index);
        System.debug('??aa' + index + 'aa?? '+ currentNode);
        ref.put('??aa' + index + 'aa??', currentNode);
        return evaluate(expression, ref, currentNode, ++index);
    }
    private static Node getNode(String expression, Map<String, Node> ref, integer index){
        Node node = new Node();
        System.debug('"' + expression + '"');
        System.debug(ref.keySet());
            if(ref.keySet().contains(expression)){
                System.debug(ref.get(expression));
                return ref.get(expression);
            }
            if(!(expression.contains(ANDv) || expression.contains(ORv))){
            Expression exp = new Expression();
            String currentOp;
            if(expression.contains('!=')){
                currentOp = '!=';
            }  else if(expression.contains('<=')){
                currentOp = '<=';
            } else if(expression.contains('>=')){
                currentOp = '>=';
            } else if(expression.contains('<')){
                currentOp = '<';
            } else if(expression.contains('>')){
                currentOp = '>';
            } else if(expression.contains('=')){
                currentOp = '=';
            }
            if(!String.isBlank(currentOp)){
                exp.operator = currentOp;
                exp.rightValue = expression.substringAfter(currentOp).trim();
                exp.leftValue = expression.substringBefore(currentOp).trim();
                node.expression = exp;
                return node;
            }else {
                throw new TreeExpressionException('Error on the expression: the operator is not supported:=> '+expression);
            }
        } else if(expression.contains(ANDv) && expression.contains(ORv)){
            throw new TreeExpressionException('Error on the expression: there "AND" and "OR" operation on the same level:=>'+expression);
        } else if(expression.contains(ANDv)){
            node.nodes = new List<Node>();
            node.operator = ANDv;
            for( String conj : expression.split(ANDv) ){
                node.nodes.add(getNode(conj.trim(), ref, index));
            }
        } else if(expression.contains(ORv)){
            node.nodes = new List<Node>();
            node.operator = ORv;
            for( String conj : expression.split(ORv) ){
                node.nodes.add(getNode(conj.trim(), ref, index));
            }
        } else {
            // exception a mettre en place
            throw new TreeExpressionException('Error on the expression');
        }
        return node;
    }

    public static Set<String> getFieldsOfTheExpression(Node node){
        Set<String> setOfFields = new Set<String>();
        if(node.expression != null){
            System.debug(node);
            Expression exp = node.expression;
            setOfFields.add(exp.leftValue.toLowerCase());
            if(exp.rightValue.startsWith('$')){
                setOfFields.add(exp.rightValue.substringAfter('$').toLowerCase());
            }
            
        }else if(node.nodes != null && node.nodes.size() > 0){
            for(Node currentNode : node.nodes){
                setOfFields.addAll(getFieldsOfTheExpression(currentNode));
            }
        }
        return setOfFields;
    }

    public class Node {
        public String operator;
        public List<Node> nodes;
        public Expression expression;
    }
    public class Expression {
        public String operator;
        public String rightValue;
        public String leftValue;
    }
    public virtual class TreeExpressionException extends Exception {}
}