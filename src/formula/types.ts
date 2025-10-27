/**
 * Types pour le tokenizer et le parser de formules Salesforce
 */

// ==================== TOKENIZER TYPES ====================

export enum TokenType {
  // Literals
  NUMBER = 'NUMBER',
  STRING = 'STRING',
  BOOLEAN = 'BOOLEAN',
  NULL = 'NULL',

  // Identifiers et Fields
  IDENTIFIER = 'IDENTIFIER',
  FIELD_REFERENCE = 'FIELD_REFERENCE',

  // Operators
  PLUS = 'PLUS',
  MINUS = 'MINUS',
  MULTIPLY = 'MULTIPLY',
  DIVIDE = 'DIVIDE',
  POWER = 'POWER',
  MODULO = 'MODULO',

  // Comparison
  EQUALS = 'EQUALS',
  NOT_EQUALS = 'NOT_EQUALS',
  LESS_THAN = 'LESS_THAN',
  LESS_THAN_OR_EQUAL = 'LESS_THAN_OR_EQUAL',
  GREATER_THAN = 'GREATER_THAN',
  GREATER_THAN_OR_EQUAL = 'GREATER_THAN_OR_EQUAL',

  // Logical
  AND = 'AND',
  OR = 'OR',
  NOT = 'NOT',

  // String operators
  AMPERSAND = 'AMPERSAND', // & pour concat

  // Punctuation
  LPAREN = 'LPAREN',
  RPAREN = 'RPAREN',
  COMMA = 'COMMA',
  DOT = 'DOT',

  // Special
  EOF = 'EOF',
}

export interface Token {
  type: TokenType;
  value: string;
  position: number;
  line: number;
  column: number;
}

// ==================== AST NODE TYPES ====================

export enum ASTNodeType {
  BINARY_OP = 'BINARY_OP',
  UNARY_OP = 'UNARY_OP',
  FUNCTION_CALL = 'FUNCTION_CALL',
  LITERAL = 'LITERAL',
  FIELD_REFERENCE = 'FIELD_REFERENCE',
}

export interface ASTNode {
  type: ASTNodeType;
  position: number;
}

export interface BinaryOpNode extends ASTNode {
  type: ASTNodeType.BINARY_OP;
  operator: TokenType;
  left: ASTNode;
  right: ASTNode;
}

export interface UnaryOpNode extends ASTNode {
  type: ASTNodeType.UNARY_OP;
  operator: TokenType;
  operand: ASTNode;
}

export interface FunctionCallNode extends ASTNode {
  type: ASTNodeType.FUNCTION_CALL;
  functionName: string;
  arguments: ASTNode[];
}

export enum LiteralType {
  NUMBER = 'NUMBER',
  STRING = 'STRING',
  BOOLEAN = 'BOOLEAN',
  NULL = 'NULL',
}

export interface LiteralNode extends ASTNode {
  type: ASTNodeType.LITERAL;
  literalType: LiteralType;
  value: string | number | boolean | null;
}

export interface FieldReferenceNode extends ASTNode {
  type: ASTNodeType.FIELD_REFERENCE;
  fieldPath: string[];
}

// ==================== ERROR TYPES ====================

export class FormulaError extends Error {
  constructor(
    message: string,
    public position?: number,
    public line?: number,
    public column?: number
  ) {
    super(message);
    this.name = 'FormulaError';
  }
}

export class TokenizerError extends FormulaError {
  constructor(message: string, position?: number, line?: number, column?: number) {
    super(message, position, line, column);
    this.name = 'TokenizerError';
  }
}

export class ParserError extends FormulaError {
  constructor(message: string, position?: number, line?: number, column?: number) {
    super(message, position, line, column);
    this.name = 'ParserError';
  }
}
