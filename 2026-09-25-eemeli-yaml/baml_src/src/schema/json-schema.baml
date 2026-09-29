// Port of src/schema/json-schema.ts
//
// The original file contains only TypeScript type declarations for JSON
// Schema (draft 2020-12) and no runtime code. It is not used by any other
// module of the library. BAML equivalents of the declared shapes follow, as
// data types only.

type JsonType = "array" | "object" | "string" | "number" | "integer" | "boolean" | "null"

type JsonSchema = bool | JsonSchemaObject

/// Merged `CommonSchema & ArraySchema & ObjectSchema & StringSchema & NumberSchema`
class JsonSchemaObject {
  type_: (JsonType | JsonType[])?
  const_: unknown?
  enum_: unknown[]?
  format: string?

  // logic/conditionals
  allOf: JsonSchema[]?
  anyOf: JsonSchema[]?
  oneOf: JsonSchema[]?
  not_: JsonSchema?
  if_: JsonSchema?
  then_: JsonSchema?
  else_: JsonSchema?

  // references
  id: string?
  defs: map<string, JsonSchema>?
  anchor: string?
  dynamicAnchor: string?
  ref: string?
  dynamicRef: string?

  // meta
  schema: string?
  vocabulary: map<string, bool>?
  comment: string?

  // annotations
  default_: unknown?
  deprecated: bool?
  readOnly: bool?
  writeOnly: bool?
  title: string?
  description: string?
  examples: unknown[]?

  // ArraySchema
  prefixItems: JsonSchema[]?
  items: JsonSchema?
  contains: JsonSchema?
  unevaluatedItems: JsonSchema?
  maxItems: int?
  minItems: int?
  uniqueItems: bool?
  maxContains: int?
  minContains: int?

  // ObjectSchema
  properties: map<string, JsonSchema>?
  patternProperties: map<string, JsonSchema>?
  additionalProperties: JsonSchema?
  propertyNames: JsonSchema?
  unevaluatedProperties: JsonSchema?
  maxProperties: int?
  minProperties: int?
  required: string[]?
  dependentRequired: map<string, string[]>?
  dependentSchemas: map<string, JsonSchema>?

  // StringSchema
  maxLength: int?
  minLength: int?
  patter: string?
  contentEncoding: string?
  contentMediaType: string?
  contentSchema: JsonSchema?

  // NumberSchema
  multipleOf: float?
  maximum: float?
  exclusiveMaximum: float?
  minimum: float?
  exclusiveMinimum: float?
}
