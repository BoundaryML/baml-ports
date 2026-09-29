// Port of src/options.ts
//
// The original declares six option-bag types (ParseOptions, DocumentOptions,
// SchemaOptions, CreateNodeOptions, ToJSOptions, ToStringOptions) which the
// public API accepts as intersections (`ParseOptions & DocumentOptions & …`).
// BAML has no intersection/object-literal types, so a single `Options` class
// carries every option (all optional, `null` = not set) and the six names
// are aliases of it.

type ParseOptions = Options
type DocumentOptions = Options
type SchemaOptions = Options
type CreateNodeOptions = Options
type ToJSOptions = Options
type ToStringOptions = Options

/// `Tags = Array<ScalarTag | CollectionTag | TagId>`
type TagRef = Tag | string

/// `(key, value, context) => unknown` with `this` bound to the holder object.
/// BAML functions have no `this`, so the holder is passed as a 4th argument.
type Reviver = (unknown, unknown, ReviverContext, unknown) -> unknown throws unknown

/// `(key, value) => unknown` with `this` bound to the holder object (passed
/// as a 3rd argument here).
type ReplacerFn = (unknown, unknown, unknown) -> unknown throws unknown

/// `Replacer = any[] | ((key: any, value: any) => unknown)`
type Replacer = unknown[] | ReplacerFn

class ReviverContext {
  source: string?
}

class Options {
  // ─── ParseOptions ─────────────────────────────────────────────────────────
  /// Whether integers should be parsed into BigInt rather than number values.
  ///
  /// Default: `false`
  intAsBigInt: bool?
  /// Include a `srcToken` value on each parsed `Node`, containing the CST
  /// token that was composed into this node.
  ///
  /// Default: `false`
  keepSourceTokens: bool?
  /// If set, newlines will be tracked, to allow for `lineCounter.linePos(offset)`
  /// to provide the `{ line, col }` positions within the input.
  lineCounter: LineCounter?
  /// Include line/col position & node type directly in parse errors.
  ///
  /// Default: `true`
  prettyErrors: bool?
  /// When parsing, do not ignore errors required by the YAML 1.2 spec, but
  /// caused by unambiguous content.
  ///
  /// Default: `true`
  strict: bool?
  /// Parse all mapping keys as strings. Treat all non-scalar keys as errors.
  ///
  /// Default: `false`
  stringKeys: bool?

  // ─── DocumentOptions ──────────────────────────────────────────────────────
  /// @internal
  /// Used internally by Composer. If set and includes an explicit version,
  /// that overrides the `version` option.
  _directives: Directives?
  /// Control the logging level during parsing
  ///
  /// Default: `'warn'`
  logLevel: string?
  /// The YAML version used by documents without a `%YAML` directive.
  ///
  /// Default: `"1.2"`
  version: string?

  // ─── SchemaOptions ────────────────────────────────────────────────────────
  /// When parsing, warn about compatibility issues with the given schema.
  /// When stringifying, use scalar styles that are parsed correctly
  /// by the `compat` schema as well as the actual schema.
  ///
  /// Default: `null`
  compat: (string | TagRef[])?
  /// Array of additional tags to include in the schema, or a function that
  /// may modify the schema's base tag array.
  customTags: (TagRef[] | ((TagRef[]) -> TagRef[] throws unknown))?
  /// Customize the key used for Map/Set values.
  mapKey: ((unknown) -> unknown throws unknown)?
  /// Enable support for `<<` merge keys.
  ///
  /// Default: `false` for YAML 1.2, `true` for earlier versions
  merge: bool?
  /// When using the `'core'` schema, support parsing values with these
  /// explicit YAML 1.1 tags:
  ///
  /// `!!binary`, `!!omap`, `!!pairs`, `!!set`, `!!timestamp`.
  ///
  /// Default `true`
  resolveKnownTags: bool?
  /// The base schema to use.
  ///
  /// The core library has built-in support for the following:
  /// - `'failsafe'`: A minimal schema that parses all scalars as strings
  /// - `'core'`: The YAML 1.2 core schema
  /// - `'json'`: The YAML 1.2 JSON schema, with minimal rules for JSON compatibility
  /// - `'yaml-1.1'`: The YAML 1.1 schema
  ///
  /// If using another (custom) schema, the `customTags` array needs to
  /// fully define the schema's tags.
  ///
  /// Default: `'core'` for YAML 1.2, `'yaml-1.1'` for earlier versions
  schema: (string | Schema)?
  /// Override default values for `toString()` options.
  toStringDefaults: Options?

  // ─── CreateNodeOptions ────────────────────────────────────────────────────
  /// During node construction, use anchors and aliases to keep strictly
  /// equal non-null objects as equivalent in YAML.
  ///
  /// Default: `true`
  aliasDuplicateObjects: bool?
  /// Default prefix for anchors.
  ///
  /// Default: `'a'`, resulting in anchors `a1`, `a2`, etc.
  anchorPrefix: string?
  /// Force the top-level collection node to use flow style.
  ///
  /// Default: `false`
  flow: bool?
  /// Keep `undefined` object values when creating mappings, rather than
  /// discarding them.
  ///
  /// Default: `false`
  keepUndefined: bool?
  /// @internal
  onTagObj: ((Tag) -> void throws unknown)?
  /// Specify the top-level collection type, e.g. `"!!omap"`. Note that this
  /// requires the corresponding tag to be available in this document's schema.
  tag: string?

  // ─── ToJSOptions ──────────────────────────────────────────────────────────
  /// Use Map rather than Object to represent mappings.
  ///
  /// Default: `false`
  mapAsMap: bool?
  /// Prevent exponential entity expansion attacks by limiting data aliasing
  /// count; set to `-1` to disable checks; `0` disallows all alias nodes.
  ///
  /// Default: `100`
  maxAliasCount: int?
  /// If defined, called with the resolved `value` and reference `count` for
  /// each anchor in the document.
  onAnchor: ((unknown, int) -> void throws unknown)?
  /// Optional function that may filter or modify the output JS value,
  /// based on the one available in `JSON.parse`.
  reviver: Reviver?

  // ─── ToStringOptions ──────────────────────────────────────────────────────
  /// Use block quote styles for scalar values where applicable.
  /// Set to `false` to disable block quotes completely.
  ///
  /// Default: `true`
  blockQuote: (bool | "folded" | "literal")?
  /// Enforce `'block'` or `'flow'` style on maps and sequences.
  /// Empty collections will always be stringified as `{}` or `[]`.
  ///
  /// Default: `'any'`
  collectionStyle: string?
  /// Comment stringifier.
  /// Output should be valid for the current schema.
  ///
  /// By default, empty comment lines are left empty,
  /// lines consisting of a single space are replaced by `#`,
  /// and all other lines are prefixed with a `#`.
  commentString: ((string) -> string throws unknown)?
  /// The default type of string literal used to stringify implicit key values.
  /// Output may use other types if required to fully represent the value.
  ///
  /// If `null`, the value of `defaultStringType` is used.
  ///
  /// Default: `null`
  defaultKeyType: string?
  /// The default type of string literal used to stringify values in general.
  /// Output may use other types if required to fully represent the value.
  ///
  /// Default: `'PLAIN'`
  defaultStringType: string?
  /// Include directives in the output.
  ///
  /// - If `true`, at least the document-start marker `---` is always included.
  ///   This does not force the `%YAML` directive to be included. To do that,
  ///   set `doc.directives.yaml.explicit = true`.
  /// - If `false`, no directives or marker is ever included. If using the `%TAG`
  ///   directive, you are expected to include it manually in the stream before
  ///   its use.
  /// - If `null`, directives and marker may be included if required.
  ///
  /// Default: `null`
  directives: bool?
  /// Restrict double-quoted strings to use JSON-compatible syntax.
  ///
  /// Default: `false`
  doubleQuotedAsJSON: bool?
  /// Minimum length for double-quoted strings to use multiple lines to
  /// represent the value. Ignored if `doubleQuotedAsJSON` is set.
  ///
  /// Default: `40`
  doubleQuotedMinMultiLineLength: int?
  /// String representation for `false`.
  /// With the core schema, use `'false'`, `'False'`, or `'FALSE'`.
  ///
  /// Default: `'false'`
  falseStr: string?
  /// When true, a single space of padding will be added inside the delimiters
  /// of non-empty single-line flow collections.
  ///
  /// Default: `true`
  flowCollectionPadding: bool?
  /// The number of spaces to use when indenting code.
  ///
  /// Default: `2`
  indent: int?
  /// Whether block sequences should be indented.
  ///
  /// Default: `true`
  indentSeq: bool?
  /// Maximum line width (leading indentation included) for flow scalars and
  /// comments. Set to `0` to disable line width limits.
  ///
  /// Default: `80`
  lineWidth: int?
  /// Minimum line width for highly-indented content.
  ///
  /// Default: `20`
  minContentWidth: int?
  /// String representation for `null`.
  /// With the core schema, use `'null'`, `'Null'`, `'NULL'`, `'~'`, or an empty
  /// string `''`.
  ///
  /// Default: `'null'`
  nullStr: string?
  /// Require keys to be scalars and to use implicit rather than explicit notation.
  ///
  /// Default: `false`
  simpleKeys: bool?
  /// Use 'single quote' rather than "double quote" where applicable.
  /// Set to `false` to disable single quotes completely.
  ///
  /// Default: `null`
  singleQuote: bool?
  /// Sort mapping entries by key, or with a custom comparator.
  ///
  /// Default: `false`
  sortMapEntries: (bool | ((Pair, Pair) -> int throws unknown))?
  /// Add a trailing comma after the last entry in a flow map or flow sequence
  /// that's split across multiple lines.
  ///
  /// Default: `false`
  trailingComma: bool?
  /// String representation for `true`.
  /// With the core schema, use `'true'`, `'True'`, or `'TRUE'`.
  ///
  /// Default: `'true'`
  trueStr: string?
  /// The anchor used by an alias must be defined before the alias node. As it's
  /// possible for the document to be modified manually, the order may be
  /// verified during stringification.
  ///
  /// Default: `'true'`
  verifyAliasOrder: bool?
}

/// `Object.assign({}, a, b)` for option bags: fields set in `b` override `a`.
function options_assign(a: Options?, b: Options?) -> Options {
  let base = if (a == null) { Options {} } else { Options { ...a } };
  if (b == null) {
    return base;
  }
  Options {
    intAsBigInt: b.intAsBigInt ?? base.intAsBigInt,
    keepSourceTokens: b.keepSourceTokens ?? base.keepSourceTokens,
    lineCounter: b.lineCounter ?? base.lineCounter,
    prettyErrors: b.prettyErrors ?? base.prettyErrors,
    strict: b.strict ?? base.strict,
    stringKeys: b.stringKeys ?? base.stringKeys,
    _directives: b._directives ?? base._directives,
    logLevel: b.logLevel ?? base.logLevel,
    version: b.version ?? base.version,
    compat: b.compat ?? base.compat,
    customTags: b.customTags ?? base.customTags,
    mapKey: b.mapKey ?? base.mapKey,
    merge: b.merge ?? base.merge,
    resolveKnownTags: b.resolveKnownTags ?? base.resolveKnownTags,
    schema: b.schema ?? base.schema,
    toStringDefaults: b.toStringDefaults ?? base.toStringDefaults,
    aliasDuplicateObjects: b.aliasDuplicateObjects ?? base.aliasDuplicateObjects,
    anchorPrefix: b.anchorPrefix ?? base.anchorPrefix,
    flow: b.flow ?? base.flow,
    keepUndefined: b.keepUndefined ?? base.keepUndefined,
    onTagObj: b.onTagObj ?? base.onTagObj,
    tag: b.tag ?? base.tag,
    mapAsMap: b.mapAsMap ?? base.mapAsMap,
    maxAliasCount: b.maxAliasCount ?? base.maxAliasCount,
    onAnchor: b.onAnchor ?? base.onAnchor,
    reviver: b.reviver ?? base.reviver,
    blockQuote: b.blockQuote ?? base.blockQuote,
    collectionStyle: b.collectionStyle ?? base.collectionStyle,
    commentString: b.commentString ?? base.commentString,
    defaultKeyType: b.defaultKeyType ?? base.defaultKeyType,
    defaultStringType: b.defaultStringType ?? base.defaultStringType,
    directives: b.directives ?? base.directives,
    doubleQuotedAsJSON: b.doubleQuotedAsJSON ?? base.doubleQuotedAsJSON,
    doubleQuotedMinMultiLineLength: b.doubleQuotedMinMultiLineLength ?? base.doubleQuotedMinMultiLineLength,
    falseStr: b.falseStr ?? base.falseStr,
    flowCollectionPadding: b.flowCollectionPadding ?? base.flowCollectionPadding,
    indent: b.indent ?? base.indent,
    indentSeq: b.indentSeq ?? base.indentSeq,
    lineWidth: b.lineWidth ?? base.lineWidth,
    minContentWidth: b.minContentWidth ?? base.minContentWidth,
    nullStr: b.nullStr ?? base.nullStr,
    simpleKeys: b.simpleKeys ?? base.simpleKeys,
    singleQuote: b.singleQuote ?? base.singleQuote,
    sortMapEntries: b.sortMapEntries ?? base.sortMapEntries,
    trailingComma: b.trailingComma ?? base.trailingComma,
    trueStr: b.trueStr ?? base.trueStr,
    verifyAliasOrder: b.verifyAliasOrder ?? base.verifyAliasOrder,
  }
}
