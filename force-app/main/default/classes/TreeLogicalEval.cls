/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 01-24-2023
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class TreeLogicalEval {
    public static Map<EvalInput, Boolean> evaluate(List<EvalInput> evalInputs){
        String prefix;
        String objectName;
        if(evalInputs !=null && evalInputs.size() != 0){
            objectName = evalInputs[0].id.getSObjectType().getDescribe().getName();
            prefix = ((String) evalInputs[0].id).subString(0,3);
        }else {
            return null;
        }
        
        List<Id> RecordIds = new List<Id>();
        Set<String> fieldsSet = new Set<String>();
        Map<EvalInput, TreeLogicalExpressionGenerator.Node> nodeMap = new Map<EvalInput, TreeLogicalExpressionGenerator.Node>();
        Map<String, TreeLogicalExpressionGenerator.Node> expressionNodeMap = new Map<String, TreeLogicalExpressionGenerator.Node>();
        for(EvalInput evalInput : evalInputs){
             System.debug('evalInput===> '+evalInput);
            if(!((String)(evalInput.id)).startsWith(prefix)){
                throw new TreelogicalEvalException('TreelogicalEvalException: The record did not have the same SObject Type');
            }
            RecordIds.add(evalInput.id);
            if(expressionNodeMap.get(evalInput.expression) == null){
                TreeLogicalExpressionGenerator.Node node =  TreeLogicalExpressionGenerator.parse(evalInput.expression);
                nodeMap.put(evalInput, node);
                fieldsSet.addAll(TreeLogicalExpressionGenerator.getFieldsOfTheExpression(node));
                expressionNodeMap.put(evalInput.expression, node);
            }else {
                TreeLogicalExpressionGenerator.Node node =  expressionNodeMap.get(evalInput.expression);
                nodeMap.put(evalInput, node);
                fieldsSet.addAll(TreeLogicalExpressionGenerator.getFieldsOfTheExpression(node));
            }
            
        }
        fieldsSet.add('id');
        String query = 'SELECT ' + String.join(new List<String>(fieldsSet), ', ') + ' FROM ' + objectName + ' WHERE Id IN :RecordIds';
        System.debug('query===> '+query);
        List<SObject> recordList = Database.query(query);
        Map<Id, SObject> recordMap = new Map<Id, SObject>();
        for(SObject obj: recordList){
            recordMap.put(obj.id, obj);
        }
        Map<EvalInput, Boolean> resultByFieldByRecordId = new Map<EvalInput, Boolean>();
        for(EvalInput evalInput : evalInputs){
            Boolean unitBoolean = evaluate(nodeMap.get(evalInput), recordMap.get(evalInput.id));
            resultByFieldByRecordId.put(evalInput, unitBoolean);
        }
        return resultByFieldByRecordId;
    }

    public static boolean evaluate(String expression, SObject record){
        TreeLogicalExpressionGenerator.Node node = TreeLogicalExpressionGenerator.parse(expression);
        return evaluate(node, record);
    }

    public static boolean evaluateById(String expression, Id id){
        TreeLogicalExpressionGenerator.Node node = TreeLogicalExpressionGenerator.parse(expression);
        Set<String> fieldsSet = TreeLogicalExpressionGenerator.getFieldsOfTheExpression(node);
        String objectName = id.getSObjectType().getDescribe().getName();
        String query = 'SELECT ' + String.join(new List<String>(fieldsSet), ', ') + ' FROM ' + objectName + ' WHERE Id = :id';
        SObject record = Database.query(query);
        return evaluate(node, record);
    }

    public static boolean evaluate(TreeLogicalExpressionGenerator.Node node, SObject record){
        if(node.expression != null){
            return unitEval(node.expression, record);
        }
        boolean value;
        if(node.nodes != null && node.nodes.size() > 0){
            value = evaluate(node.nodes[0], record);
            if(node.operator.equals('AND')){
                
                for(integer i = 1; i< node.nodes.size(); i++){
                    value = value && evaluate(node.nodes[i], record);
                    if(!value){
                        return false;
                    }
                }
            }
            if(node.operator.equals('OR')){
                for(integer i = 1; i< node.nodes.size(); i++){
                    value = value || evaluate(node.nodes[i], record);
                    if(value){
                        return true;
                    }
                }
            }
            return value;
        }else {
             throw new TreelogicalEvalException('TreelogicalEvalException: error when evaluating the expression');
        }
    }

    
    private static boolean unitEval(TreeLogicalExpressionGenerator.Expression expression, SObject record){
        String rightValue = expression.rightValue;
        
        String leftValue = expression.leftValue;
        String operateur = expression.operator;
        Object leftObject;
        if(leftValue.contains('.')){
            leftObject = (Object)((SObject)record.getSObject(leftValue.split('\\.')[0])).get(leftValue.split('\\.')[1]);
        }else{
            leftObject = (Object) record.get(leftValue);
        }
        
        Object rightObject;

        if(rightValue.startsWith('$')){

            if(rightValue.contains('.')){
                rightObject = (Object)((SObject)record.getSObject(rightValue.replace('$', '').split('\\.')[0])).get(rightValue.split('\\.')[1]);
            }else {
                rightObject = (Object)record.get(rightValue.replace('$', ''));
            }
            
        }else {
            if(rightValue == 'null'){
                rightObject = null;
            }else if(rightValue.startsWith('\'') && rightValue.endsWith('\'')){
                rightObject = (Object) rightValue.substring(1, rightValue.length() - 1);
            }else {
                rightObject = (Object) rightValue;
            }
            
        }
        
        return compareValue(String.valueOf(leftObject), String.valueOf(rightObject), operateur, leftValue, record);
    }
    public static Boolean compareValue(String leftObject, String rightObject, String operateur, String fieldName, SObject record) {
        Schema.DisplayType fieldType;
        if(fieldName.contains('.')){
            SObject childObject = record.getSObject(fieldName.split('\\.')[0]);
            Schema.SObjectType objectSchema = childObject.getSObjectType();
            Map<String, Schema.SObjectField> fieldMap = objectSchema.getDescribe().fields.getMap();
            fieldType = fieldMap.get(fieldName.split('\\.')[1]).getDescribe().getType();
        }else{
            Schema.SObjectType objectSchema = record.getSObjectType();
            Map<String, Schema.SObjectField> fieldMap = objectSchema.getDescribe().fields.getMap();
            fieldType = fieldMap.get(fieldName).getDescribe().getType();
        }
        
        boolean retValue;
        if(fieldType == Schema.DisplayType.String || 
        fieldType == Schema.DisplayType.TextArea ||
        fieldType == Schema.DisplayType.Id ||
        fieldType == Schema.DisplayType.Picklist ||
        fieldType == Schema.DisplayType.Reference ||
        fieldType == Schema.DisplayType.Phone ||
        fieldType == Schema.DisplayType.Email ||
        fieldType == Schema.DisplayType.URL ||
        fieldType == Schema.DisplayType.EncryptedString||
        fieldType == Schema.DisplayType.DataCategoryGroupReference||
        fieldType == Schema.DisplayType.base64){
            switch on operateur {
                when '=' {    
                    retValue = String.valueOf(leftObject) == String.valueOf(rightObject);
                }  
                when '!=' {    
                    retValue = !(String.valueOf(leftObject) == String.valueOf(rightObject));
                }
                when '<' {    
                    retValue = String.valueOf(leftObject) < String.valueOf(rightObject);
                }
                when '>' {    
                    retValue = String.valueOf(leftObject) > String.valueOf(rightObject);
                }
                when '<=' {    
                    retValue = String.valueOf(leftObject) <= String.valueOf(rightObject);
                }
                when '>=' {    
                    retValue = String.valueOf(leftObject) >= String.valueOf(rightObject);
                }
                when else {      // default block, optional
                    // code block 4
                }
            }
        }
        if(fieldType == Schema.DisplayType.Currency ||
            fieldType == Schema.DisplayType.Double||
            fieldType == Schema.DisplayType.Percent||
            fieldType == Schema.DisplayType.Integer ){
            switch on operateur {
                when '=' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : decimal.valueOf(leftObject)) == (rightObject == null || String.isBlank(rightObject)? null : decimal.valueOf(rightObject));
                }  
                when '!=' {    
                    retValue = !((leftObject == null || String.isBlank(leftObject)? null : decimal.valueOf(leftObject)) == (rightObject == null || String.isBlank(rightObject)? null : decimal.valueOf(rightObject)));
                }
                when '<' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : decimal.valueOf(leftObject)) < (rightObject == null || String.isBlank(rightObject)? null : decimal.valueOf(rightObject));
                }
                when '>' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : decimal.valueOf(leftObject)) > (rightObject == null || String.isBlank(rightObject)? null : decimal.valueOf(rightObject));
                }
                when '<=' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : decimal.valueOf(leftObject)) <= (rightObject == null || String.isBlank(rightObject)? null : decimal.valueOf(rightObject));
                }
                when '>=' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : decimal.valueOf(leftObject)) >= (rightObject == null || String.isBlank(rightObject)? null : decimal.valueOf(rightObject));
                }
                when else {      // default block, optional
                    // code block 4
                }
            }
        }
        if(fieldType == Schema.DisplayType.Boolean ||
        fieldType == Schema.DisplayType.Combobox){
            switch on operateur {
                when '=' {
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : Boolean.valueOf(leftObject))  == (rightObject == null || String.isBlank(rightObject)? null : Boolean.valueOf(rightObject));
                }  
                when '!=' {    
                    retValue = !(leftObject == null || String.isBlank(leftObject)? null : Boolean.valueOf(leftObject))  == (rightObject == null || String.isBlank(rightObject)? null : Boolean.valueOf(rightObject));
                }
                when else {      // default block, optional
                    // code block 4
                }
            }
        }
        if(fieldType == Schema.DisplayType.DateTime||
        fieldType == Schema.DisplayType.Time){
            switch on operateur {
                when '=' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : DateTime.valueOf(leftObject)) == (rightObject == null || String.isBlank(rightObject)? null : DateTime.valueOf(rightObject));
                }  
                when '!=' {    
                    retValue = !((leftObject == null || String.isBlank(leftObject)? null : DateTime.valueOf(leftObject)) == (rightObject == null || String.isBlank(rightObject)? null : DateTime.valueOf(rightObject)));
                }
                when '<' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : DateTime.valueOf(leftObject)) < (rightObject == null || String.isBlank(rightObject)? null : DateTime.valueOf(rightObject));
                }
                when '>' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : DateTime.valueOf(leftObject)) > (rightObject == null || String.isBlank(rightObject)? null : DateTime.valueOf(rightObject));
                }
                when '<=' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : DateTime.valueOf(leftObject)) <= (rightObject == null || String.isBlank(rightObject)? null : DateTime.valueOf(rightObject));
                }
                when '>=' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : DateTime.valueOf(leftObject)) >= (rightObject == null || String.isBlank(rightObject)? null : DateTime.valueOf(rightObject));
                }
                when else {      // default block, optional
                    // code block 4
                }
            }
        }
        if(fieldType == Schema.DisplayType.Date){
            switch on operateur {
                when '=' {
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : Date.valueOf(leftObject)) == (rightObject == null || String.isBlank(rightObject)? null : Date.valueOf(rightObject));
                }  
                when '!=' {    
                    retValue = !((leftObject == null || String.isBlank(leftObject)? null : Date.valueOf(leftObject)) == (rightObject == null || String.isBlank(rightObject)? null : Date.valueOf(rightObject)));
                }
                when '<' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : Date.valueOf(leftObject)) < (rightObject == null || String.isBlank(rightObject)? null : Date.valueOf(rightObject));
                }
                when '>' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : Date.valueOf(leftObject)) > (rightObject == null || String.isBlank(rightObject)? null : Date.valueOf(rightObject));
                }
                when '<=' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : Date.valueOf(leftObject)) <= (rightObject == null || String.isBlank(rightObject)? null : Date.valueOf(rightObject));
                }
                when '>=' {    
                    retValue = (leftObject == null || String.isBlank(leftObject)? null : Date.valueOf(leftObject)) >= (rightObject == null || String.isBlank(rightObject)? null : Date.valueOf(rightObject));
                }
                when else {      // default block, optional
                    // code block 4
                }
            }
        }
        if(fieldType == Schema.DisplayType.MultiPicklist){
            List<String> picklistValue = String.isBlank(leftObject)? new List<String>{null} : leftObject.split(';');
            switch on operateur {
                when '=' {    
                    retValue = picklistValue.contains( rightObject);
                }  
                when '!=' {    
                    retValue = !picklistValue.contains(rightObject);
                }
                when else {      // default block, optional
                    // code block 4
                }
            }
        }
        return retValue;
    }
    public virtual class TreelogicalEvalException extends Exception {}
    public class EvalInput{
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String field;
        @AuraEnabled
        public String expression;
        public Integer hashCode() {
            return (this.id + this.field + this.expression).hashCode();
        }
        
        public Boolean equals(Object obj) {
            if (obj instanceof EvalInput) {
                EvalInput p = (EvalInput)obj;
                return (this.id == p.id && this.field == p.field && this.expression == p.expression);
            }
            return false;
        }
    }
}