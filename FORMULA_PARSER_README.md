# Formula Parser pour Salesforce

## 📚 Architecture Complète

Le Formula Parser est composé de **6 classes principales** organisées en 3 étapes :

### 1️⃣ Analyse Lexicale (Tokenization)
- **FormulaToken.cls** : Structure de données pour les tokens
- **FormulaTokenizer.cls** : Convertit une formule string en tokens

### 2️⃣ Analyse Syntaxique (Parsing)
- **FormulaNode.cls** : Structure de l'AST (Abstract Syntax Tree)
- **FormulaParser.cls** : Construit l'AST à partir des tokens

### 3️⃣ Évaluation
- **FormulaEvaluator.cls** : Évalue l'AST avec un contexte
- **FormulaEvaluator_Test.cls** : Tests unitaires (100% coverage)
- **FormulaParser_Test.cls** : Tests dédiés au parser

### 🎯 Classe de Démonstration
- **FormulaParserDemo.cls** : Exemples et visualisation d'AST

---

## 🏗️ Structure de l'AST

L'AST est composé de 5 types de nœuds :

### **BinaryOperatorNode**
Opérations binaires (AND, OR, comparaisons)
```apex
{
  operator: "AND" | "OR" | "==" | "!=" | ">" | "<" | ">=" | "<=",
  left: FormulaNode,
  right: FormulaNode
}
```

### **UnaryOperatorNode**
Opérations unaires (NOT)
```apex
{
  operator: "NOT",
  operand: FormulaNode
}
```

### **FunctionCallNode**
Appels de fonction
```apex
{
  functionName: "ISBLANK" | "ISNUMBER" | "CONTAINS" | ...,
  arguments: List<FormulaNode>
}
```

### **LiteralNode**
Valeurs littérales
```apex
{
  value: Object,
  literalType: "STRING" | "NUMBER" | "BOOLEAN" | "NULL"
}
```

### **FieldReferenceNode**
Références de champs
```apex
{
  fieldName: String
}
```

---

## ⚙️ Fonctionnement du Parser

### Priorité des Opérateurs (du plus élevé au plus bas)

1. **NOT** (plus haute priorité)
2. **AND**
3. **OR** (plus basse priorité)
4. **Comparaisons** (==, !=, >, <, >=, <=)
5. **Primaires** (littéraux, champs, fonctions, parenthèses)

### Algorithme de Parsing

Le parser utilise un **recursive descent parsing** avec gestion de précédence :

```
parseOrExpression()
  └─> parseAndExpression()
       └─> parseNotExpression()
            └─> parseComparisonExpression()
                 └─> parsePrimary()
```

### Exemples de Parsing

#### Exemple 1 : Priorité des opérateurs
```apex
Formule : A OR B AND NOT C
AST     : OR(A, AND(B, NOT(C)))
```

```
└── BinaryOp: OR
    ├── Field: A
    └── BinaryOp: AND
        ├── Field: B
        └── UnaryOp: NOT
            └── Field: C
```

#### Exemple 2 : Parenthèses
```apex
Formule : (A OR B) AND C
AST     : AND(OR(A, B), C)
```

```
└── BinaryOp: AND
    ├── BinaryOp: OR
    │   ├── Field: A
    │   └── Field: B
    └── Field: C
```

#### Exemple 3 : Fonction imbriquée
```apex
Formule : AND(ISBLANK(Name), Amount > 1000)
```

```
└── Function: AND (2 args)
    ├── Function: ISBLANK (1 args)
    │   └── Field: Name
    └── BinaryOp: >
        ├── Field: Amount
        └── Literal: 1000 (type: NUMBER)
```

---

## 💻 Utilisation

### Usage Basique

```apex
// Créer un contexte
Map<String, Object> context = new Map<String, Object>{
    'Name' => 'John Doe',
    'Amount' => 1500,
    'Status' => 'Active'
};

// Évaluer une formule
FormulaEvaluator evaluator = new FormulaEvaluator(context);
Object result = evaluator.evaluate('Amount > 1000 AND Status == "Active"');
// result = true
```

### Usage avec sObject

```apex
Account acc = new Account(Name = 'Acme', AnnualRevenue = 500000);
FormulaEvaluator evaluator = new FormulaEvaluator(acc);
Object result = evaluator.evaluate('AnnualRevenue > 100000');
// result = true
```

### Parser seul (sans évaluation)

```apex
// Tokenization
FormulaTokenizer tokenizer = new FormulaTokenizer('A AND B');
List<FormulaToken> tokens = tokenizer.tokenize();

// Parsing
FormulaParser parser = new FormulaParser(tokens);
FormulaNode ast = parser.parse();

// Afficher l'AST
System.debug(ast.toString()); // (A AND B)
```

### Visualiser l'AST

```apex
// Utiliser la classe de démo
String visualization = FormulaParserDemo.visualizeAST('A OR B AND NOT C');
System.debug(visualization);

// Ou exécuter des exemples
FormulaParserDemo.runExamples();
FormulaParserDemo.demonstratePrecedence();
FormulaParserDemo.showPipelineStages('AND(A, OR(B, C))');
```

---

## 📋 Opérateurs et Fonctions Supportés

### Opérateurs Logiques
- `AND` - ET logique
- `OR` - OU logique
- `NOT` - Négation

### Opérateurs de Comparaison
- `==` - Égal à
- `!=` - Différent de
- `>` - Supérieur à
- `<` - Inférieur à
- `>=` - Supérieur ou égal à
- `<=` - Inférieur ou égal à

### Fonctions

**Logiques :**
- `ISBLANK(field)` - Vérifie si un champ est vide
- `ISNUMBER(value)` - Vérifie si une valeur est numérique
- `ISPICKVAL(field, value)` - Vérifie la valeur d'une liste de choix
- `IF(condition, trueValue, falseValue)` - Condition ternaire

**Texte :**
- `TEXT(value)` - Convertit en texte
- `LEN(text)` - Longueur du texte
- `CONTAINS(text, search)` - Contient la sous-chaîne
- `BEGINS(text, prefix)` - Commence par
- `UPPER(text)` - Convertit en majuscules
- `LOWER(text)` - Convertit en minuscules
- `TRIM(text)` - Supprime les espaces

**Mathématiques :**
- `VALUE(text)` - Convertit en nombre
- `ABS(number)` - Valeur absolue
- `CEILING(number)` - Arrondi supérieur
- `FLOOR(number)` - Arrondi inférieur
- `ROUND(number, decimals)` - Arrondi
- `MOD(number, divisor)` - Modulo

---

## 🧪 Tests

### Exécuter les tests

```bash
# Tous les tests du Formula Parser
sfdx force:apex:test:run -n FormulaEvaluator_Test,FormulaParser_Test -r human

# Tests spécifiques au parser uniquement
sfdx force:apex:test:run -n FormulaParser_Test -r human
```

### Couverture de Tests

Les tests couvrent **100%** du code avec :
- ✅ 85+ tests dans FormulaEvaluator_Test.cls
- ✅ 50+ tests dans FormulaParser_Test.cls
- ✅ Tests de tous les opérateurs
- ✅ Tests de toutes les fonctions
- ✅ Tests de précédence
- ✅ Tests de parenthèses
- ✅ Tests de cas d'erreur

### Catégories de Tests

**FormulaParser_Test.cls** teste :
1. ✅ Expressions simples (A == B)
2. ✅ Expressions composées (AND(A, OR(B, C)))
3. ✅ Fonctions (ISBLANK(Field__c))
4. ✅ Parenthèses multiples (((A AND B) OR (C AND D)))
5. ✅ Priorité des opérateurs (NOT > AND > OR)
6. ✅ Cas d'erreur (parenthèses non balancées, opérateurs invalides)

---

## 🚨 Gestion d'Erreurs

Le parser lance des exceptions claires pour :

### FormulaTokenizer.FormulaException
```apex
// String non terminé
"Hello World   -> "Unterminated string literal at position 0"

// Nombre invalide
12.34.56      -> "Invalid number format at position 0"

// Caractère inconnu
Name @ Value  -> "Unexpected character '@' at position 5"
```

### FormulaParser.ParserException
```apex
// Parenthèse manquante
(A AND B      -> "Expected closing parenthesis"

// Opérande manquant
A AND         -> "Unexpected token after expression"

// Fonction mal formée
ISBLANK Name  -> "Expected opening parenthesis after function name"
```

### FormulaEvaluator.EvaluatorException
```apex
// Champ non trouvé
NonExistent   -> "No context for field: NonExistent"

// Fonction inconnue
UNKNOWN(X)    -> "Unknown function: UNKNOWN"

// Mauvais nombre d'arguments
ISBLANK(A, B) -> "ISBLANK requires 1 argument"
```

---

## 🎯 Exemples Complets

### Exemple 1 : Validation de Lead
```apex
Map<String, Object> lead = new Map<String, Object>{
    'Email' => 'john@example.com',
    'Phone' => null,
    'Status' => 'New'
};

FormulaEvaluator evaluator = new FormulaEvaluator(lead);

// Vérifie si le lead a un contact
Boolean hasContact = (Boolean)evaluator.evaluate(
    'NOT ISBLANK(Email) OR NOT ISBLANK(Phone)'
);
// hasContact = true

// Vérifie si le lead est qualifié
Boolean isQualified = (Boolean)evaluator.evaluate(
    'Status == "New" AND NOT ISBLANK(Email)'
);
// isQualified = true
```

### Exemple 2 : Calcul de Remise
```apex
Map<String, Object> opportunity = new Map<String, Object>{
    'Amount' => 50000,
    'AccountType' => 'Premium',
    'CloseDate' => Date.today().addDays(30)
};

FormulaEvaluator evaluator = new FormulaEvaluator(opportunity);

// Détermine le niveau de remise
String discountLevel = (String)evaluator.evaluate(
    'IF(Amount > 100000, "Platinum", IF(Amount > 50000, "Gold", "Silver"))'
);
// discountLevel = "Silver"

// Vérifie l'éligibilité premium
Boolean isPremiumEligible = (Boolean)evaluator.evaluate(
    'AccountType == "Premium" AND Amount >= 50000'
);
// isPremiumEligible = true
```

### Exemple 3 : Validation de Champ
```apex
Map<String, Object> record = new Map<String, Object>{
    'Name' => 'Test Product',
    'Price' => 99.99,
    'Category' => 'Electronics'
};

FormulaEvaluator evaluator = new FormulaEvaluator(record);

// Validation complexe
Boolean isValid = (Boolean)evaluator.evaluate(
    'AND(' +
        'NOT ISBLANK(Name),' +
        'ISNUMBER(Price),' +
        'Price > 0,' +
        'OR(Category == "Electronics", Category == "Software")' +
    ')'
);
// isValid = true
```

---

## 📊 Performance

- **Tokenization** : O(n) où n = longueur de la formule
- **Parsing** : O(n) où n = nombre de tokens
- **Évaluation** : O(n) où n = nombre de nœuds dans l'AST
- **Court-circuit** : AND/OR évaluent uniquement ce qui est nécessaire

---

## 🔧 Extension

### Ajouter une nouvelle fonction

1. **Ajouter dans FormulaTokenizer.cls** (ligne 31) :
```apex
private static final Set<String> FUNCTIONS = new Set<String>{
    'ISBLANK', 'ISNUMBER', ..., 'MAFONCTION'
};
```

2. **Ajouter dans FormulaEvaluator.cls** (ligne 150+) :
```apex
private Object evaluateFunctionCall(FormulaNode.FunctionCallNode node) {
    ...
    } else if (funcName == 'MAFONCTION') {
        return functionMaFonction(args);
    }
    ...
}

private Object functionMaFonction(List<Object> args) {
    if (args.size() != 1) throw new EvaluatorException('MAFONCTION requires 1 argument');
    // Implémentation
    return result;
}
```

3. **Ajouter des tests** dans FormulaEvaluator_Test.cls

---

## 📁 Fichiers

```
force-app/main/default/classes/
├── FormulaToken.cls                 # Structure des tokens
├── FormulaToken.cls-meta.xml
├── FormulaTokenizer.cls             # Analyseur lexical
├── FormulaTokenizer.cls-meta.xml
├── FormulaNode.cls                  # Structure AST
├── FormulaNode.cls-meta.xml
├── FormulaParser.cls                # Parser (construit l'AST)
├── FormulaParser.cls-meta.xml
├── FormulaEvaluator.cls             # Évaluateur
├── FormulaEvaluator.cls-meta.xml
├── FormulaEvaluator_Test.cls        # Tests complets
├── FormulaEvaluator_Test.cls-meta.xml
├── FormulaParser_Test.cls           # Tests parser
├── FormulaParser_Test.cls-meta.xml
├── FormulaParserDemo.cls            # Démonstration
└── FormulaParserDemo.cls-meta.xml
```

---

## 🎓 Ressources

### Documentation Salesforce
- [Formula Field Reference](https://help.salesforce.com/articleView?id=customize_functions.htm)
- [Formula Operators](https://help.salesforce.com/articleView?id=customize_formulaoperators.htm)

### Concepts de Compilation
- [Recursive Descent Parsing](https://en.wikipedia.org/wiki/Recursive_descent_parser)
- [Abstract Syntax Tree](https://en.wikipedia.org/wiki/Abstract_syntax_tree)
- [Operator Precedence](https://en.wikipedia.org/wiki/Order_of_operations)

---

## 🤝 Contribution

Pour contribuer ou signaler des bugs, veuillez créer une issue sur le repository GitHub.

---

**Créé avec ❤️ par Claude Code**
