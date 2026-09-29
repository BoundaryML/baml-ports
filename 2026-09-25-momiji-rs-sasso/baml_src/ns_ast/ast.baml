// Ported from sasso `src/ast.rs` (namespace `root.ast`).
//
// The parsed syntax tree.
//
// Selectors and property names are templates ([`TplPiece`]) because they
// may contain `#{...}` interpolation that is only resolved at eval time.

/// A parsed stylesheet: an ordered list of top-level statements.
class Stylesheet {
    stmts: Stmt[],
}

/// 1-based source-line metadata for the serializer's trailing-comment rule
/// (dart `_isTrailingComment`). `file` is an evaluator-interned source id
/// (0 = unknown, never trailing).
class SrcLines {
    file: int,
    /// A comment's `/*` line; a block's opening-brace line.
    start: int,
    /// The construct's last line (closing delimiter / end of value).
    end: int,
    /// A comment's 1-based `/*` column (0 elsewhere): two comments with the
    /// same file/lines/column are span-identical CLONES (the same file
    /// imported twice), which dart's span-containment branch rejects as
    /// trailing — distinct same-line comments differ in column and still join.
    col: int,
    /// The 0-based source COLUMN of the mapped token's start (a selector's
    /// first character, a declaration/at-rule keyword, a comment's `/*`), used
    /// ONLY by source-map generation — never by the serializer. Default 0 when
    /// unknown. Distinct from [`Self::col`], which is overloaded for the
    /// trailing-comment / custom-property-reindent heuristics; this field is a
    /// pure additive carrier and changes no CSS output.
    start_col: int,
    /// Source-map-only OVERRIDE for the mapped source file id (0 = fall back to
    /// [`Self::file`]). A bubbled `@media`/`@at-root` wrapper re-uses the
    /// enclosing rule's selector position for its mapping while keeping
    /// `file`/`start`/`end` at 0 so the trailing-comment heuristic stays
    /// disabled (dart maps the duplicated parent selector to the ORIGINAL rule's
    /// span). Like [`Self::start_col`] this changes no CSS output.
    map_file: int,
    /// Source-map-only OVERRIDE for the mapped 1-based source line (0 = fall
    /// back to [`Self::start`]). Set together with [`Self::map_file`] on a
    /// bubbled-selector wrapper; see that field.
    map_line: int,

    /// derive(Default)
    function default() -> SrcLines {
        SrcLines { file: 0, start: 0, end: 0, col: 0, start_col: 0, map_file: 0, map_line: 0 }
    }

    /// The 1-based source line a mapping for this construct points at:
    /// [`Self::map_line`] when set (a rule maps its selector's first line,
    /// which is not its brace line), else [`Self::start`].
    function mapped_line(self) -> int {
        if (self.map_line != 0) {
            self.map_line
        } else {
            self.start
        }
    }
}

/// A statement, valid at the top level or inside a rule body.
interface Stmt {}

/// `$name: value [!default] [!global];`
class Stmt_VarDecl {
    _0: VarDecl,
    implements Stmt {}
}

/// `selector { ... }`
class Stmt_Rule {
    _0: Rule,
    implements Stmt {}
}

/// `property: value [!important];`
class Stmt_Decl {
    _0: Declaration,
    implements Stmt {}
}

/// A nested property set: `property: [value] { children }`. The optional
/// value is emitted as `property: value;` first, then each child
/// declaration is namespaced as `property-<child>` and emitted in source
/// order (dart-sass property-set / namespaced-declaration form).
class Stmt_PropertySet {
    _0: PropertySet,
    implements Stmt {}
}

/// A custom-property declaration (`--name: value`) whose name *literally*
/// begins with `--`. Its value is captured verbatim (a template) — only
/// `#{…}` interpolation is resolved, never SassScript — matching dart-sass
/// `_interpolatedDeclarationValue`.
class Stmt_CustomDecl {
    _0: CustomDecl,
    implements Stmt {}
}

/// `@import "a", "b";` — each entry is either a Sass path to inline or a
/// plain CSS import emitted verbatim.
/// `@import <args>;` — `pos`/`length` span the rule up to its `;`
/// (`@import "x"`, trailing whitespace included), the caret dart uses when
/// the rule is misplaced.
class Stmt_Import {
    args: ImportArg[],
    pos: root.scanner.Pos,
    length: int,
    implements Stmt {}
}

/// `@use "<url>" [as <namespace>|as *] [with (...)];`. Built-in `sass:*`
/// modules and user stylesheets are both supported: the namespace defaults
/// to the final URL segment (or the part after `sass:`), `as ns` overrides
/// it, and `as *` exposes the members unprefixed. `with (...)` overrides the
/// loaded module's `!default` variables before it is evaluated.
/// Byte length of the rule (`@use "x" as y`, excluding the `;`) — the
/// span dart reports a load failure or a misplaced rule against.
class Stmt_Use {
    url: string,
    namespace: string?,
    star: bool,
    config: ConfigEntry[],
    pos: root.scanner.Pos,
    length: int,
    implements Stmt {}
}

/// `@forward "<url>" [as <prefix>-*] [show ...|hide ...] [with (...)];` —
/// re-export another module's members from the current module.
/// Byte length of the rule, as for [`Stmt::Use`].
class Stmt_Forward {
    url: string,
    prefix: string?,
    show: ForwardMember[]?,
    hide: ForwardMember[]?,
    config: ConfigEntry[],
    length: int,
    pos: root.scanner.Pos,
    implements Stmt {}
}

/// `/* ... */` loud comment (inner text, without the delimiters). The body
/// is a template so `#{…}` interpolation is resolved at eval time. The
/// [`SrcLines`] carry the comment's source lines (parser fills start/end,
/// `file` stays 0 until the evaluator stamps it).
class Stmt_Comment {
    _0: TplPiece[],
    _1: SrcLines,
    implements Stmt {}
}

/// `@if`/`@else if`/`@else` — evaluated top to bottom, first match wins.
class Stmt_If {
    _0: IfBranch[],
    implements Stmt {}
}

/// `@for $i from A through|to B { … }`.
/// 1-based start of `from`'s text. Source-map only: the loop variable's
/// definition node is `_expressionNode(node.from)` (evaluate.dart:1666).
class Stmt_For {
    var: string,
    from: Expr,
    to: Expr,
    inclusive: bool,
    body: Stmt[],
    from_pos: root.scanner.Pos,
    implements Stmt {}
}

/// `@each $v[, $k…] in <list> { … }`.
/// 1-based start of `list`'s text. Source-map only: every `@each`
/// variable's definition node is `_expressionNode(node.list)`
/// (evaluate.dart:1441).
class Stmt_Each {
    vars: string[],
    list: Expr,
    body: Stmt[],
    list_pos: root.scanner.Pos,
    implements Stmt {}
}

/// `@while <cond> { … }`.
class Stmt_While {
    cond: Expr,
    body: Stmt[],
    implements Stmt {}
}

/// `@function name(params) { … @return … }`. Shared in an `Rc` so the
/// definition survives in the environment after its source drops.
class Stmt_FunctionDef {
    _0: Callable,
    implements Stmt {}
}

/// `@return <expr>;`
class Stmt_Return {
    _0: Expr,
    implements Stmt {}
}

/// `@mixin name(params) { … }`.
class Stmt_MixinDef {
    _0: Callable,
    implements Stmt {}
}

/// `@include name(args) [{ content }];`. `module` is the namespace of a
/// `@include ns.mixin(...)` reference; `None` for an unqualified include.
/// The `using (params)` clause's parameters, if any — the content block
/// declares these and they're bound from the `@content(args)` call.
/// 1-based position of the `@include` keyword (the `@`), used as the
/// call-site span for diagnostic stack frames.
/// Byte length of the CALL (`@include name(args)`, excluding the
/// trailing `;`, a `using` clause and a content block) — dart's
/// `spanWithoutContent`, which sizes the caret of an error about the
/// call itself: a content block the mixin does not take, a missing
/// argument.
/// Byte length of the WHOLE statement, `using` clause and content block
/// included — dart's `span`, which sizes the caret of an error about
/// the rule: an undefined mixin, a namespace that is not there.
class Stmt_Include {
    name: string,
    args: CallArg[],
    content: Stmt[]?,
    content_params: ParamList?,
    module: string?,
    pos: root.scanner.Pos,
    length: int,
    full_length: int,
    implements Stmt {}
}

/// `@content;` or `@content(args)` — runs the `@include`'s content block,
/// passing any arguments to its `using (params)`.
class Stmt_Content {
    args: CallArg[],
    pos: root.scanner.Pos,
    implements Stmt {}
}

/// A generic at-rule: `@name <prelude> { body }` or `@name <prelude>;`.
/// `body == None` is the statement (`;`) form. Used for `@font-face`,
/// `@page`, `@charset`, `@supports`, vendor `@foo`, and unknown
/// directives alike.
/// Source lines: `start` = the `{` line (or the rule's own line for the
/// `;` form), `end` = the `}` line (or the same line).
class Stmt_AtRule {
    name: string,
    prelude: TplPiece[],
    body: Stmt[]?,
    lines: SrcLines,
    implements Stmt {}
}

/// A generic at-rule whose NAME contains interpolation
/// (`@#{"media"} … {}`): always treated as unknown — no Sass parse-time
/// behavior — except `@keyframes`, whose frame handling happens at eval
/// time once the name resolves.
/// Source lines, as for [`Stmt::AtRule`]: `start` = the `{` line (or
/// the rule's own line for the `;` form), `end` = the `}` line.
class Stmt_InterpAtRule {
    name: TplPiece[],
    prelude: TplPiece[],
    body: Stmt[]?,
    lines: SrcLines,
    implements Stmt {}
}

/// A plain-CSS custom `@function`/`@mixin` whose name begins with `--`.
/// dart-sass does not treat these as Sass definitions: the whole construct
/// is emitted verbatim as a generic at-rule. `name` is the keyword exactly
/// as written (`function`/`FUNCTION`/`mixin`). The prelude (`--a(...)
/// [returns ...]`) and each body declaration value are preserved literally;
/// only `#{...}` interpolation is resolved.
class Stmt_CssCustomAtRule {
    name: string,
    prelude: TplPiece[],
    body: CssCustomItem[],
    implements Stmt {}
}

/// `@media <media-query-list> { body }`. The query is parsed into a
/// structured form so SassScript inside feature values is resolved and the
/// query is re-serialized (and bubbled/merged) exactly like dart-sass.
/// `{`/`}` source lines for the serializer's trailing-comment rule.
class Stmt_Media {
    query: MediaQueryList,
    body: Stmt[],
    lines: SrcLines,
    implements Stmt {}
}

/// `@supports <condition> { body }`. The condition is parsed into a
/// structured form (`SupportsCondition`) so it serializes canonically and
/// malformed conditions are rejected; the body bubbles like any at-rule.
/// `{`/`}` source lines (+ the `@` keyword column in `start_col`) for
/// the serializer's trailing-comment rule and source-map output.
class Stmt_Supports {
    condition: SupportsCondition,
    body: Stmt[],
    lines: SrcLines,
    implements Stmt {}
}

/// `@at-root [query] { body }` — runs the body with the parent selector
/// reset to the document root.
class Stmt_AtRoot {
    query: TplPiece[]?,
    body: Stmt[],
    implements Stmt {}
}

/// `@keyframes <name> { from {…} 50% {…} … }`. The inner block selectors
/// are keyframe selectors, not CSS selectors (no `&`/parent resolution),
/// so the body is run with the parent context reset to root.
/// Source lines: `start` = the `{` line, `end` = the `}` line.
class Stmt_Keyframes {
    name: string,
    prelude: TplPiece[],
    body: Stmt[],
    lines: SrcLines,
    implements Stmt {}
}

/// `@extend <selector> [!optional];` — registers an extension of the
/// enclosing rule onto the target selector. The selector is a template
/// so `#{...}` interpolation resolves at eval time.
class Stmt_Extend {
    selector: TplPiece[],
    optional: bool,
    pos: root.scanner.Pos,
    implements Stmt {}
}

/// `@warn <expr>;` — writes to stderr, emits no CSS. `pos` is the 1-based
/// position of the `@warn` keyword (the innermost stack frame).
class Stmt_Warn {
    value: Expr,
    pos: root.scanner.Pos,
    implements Stmt {}
}

/// `@debug <expr>;` — writes to stderr, emits no CSS. `pos` is the 1-based
/// position of the `@debug` keyword (only its line is reported).
class Stmt_Debug {
    value: Expr,
    pos: root.scanner.Pos,
    implements Stmt {}
}

/// `@error <expr>;` — aborts compilation with the message. `pos` is the
/// 1-based position of the `@error` keyword and `length` the byte length of
/// the `@error <expr>` span (used as the snippet span only at the document
/// root; inside a call the innermost call site is used instead).
class Stmt_Error {
    value: Expr,
    pos: root.scanner.Pos,
    length: int,
    implements Stmt {}
}

/// One `$name: value [!default]` entry in a `@use`/`@forward` `with (...)`
/// configuration clause.
class ConfigEntry {
    name: string,
    value: Expr,
    /// `!default` on a `@forward ... with` entry: the override only applies if
    /// the downstream module does not configure the variable itself.
    is_default: bool,
}

/// A member name in a `@forward ... show/hide` clause. Variables keep their
/// leading `$`; functions/mixins are bare identifiers.
interface ForwardMember {}

/// A `$variable` name (stored without the `$`).
class ForwardMember_Var {
    _0: string,
    implements ForwardMember {}
}

/// A function or mixin name.
class ForwardMember_Name {
    _0: string,
    implements ForwardMember {}
}

/// One entry in an `@import` statement.
interface ImportArg {}

/// A Sass import: the (unquoted) path of a partial to resolve and inline,
/// plus the 1-based position and byte length of the quoted URL token (for
/// the `[import]` deprecation snippet).
class ImportArg_Sass {
    path: string,
    pos: root.scanner.Pos,
    length: int,
    implements ImportArg {}
}

/// A plain CSS `@import`: emitted as `@import <url> <modifiers>;`. The URL
/// is a template (only `#{…}` interpolation resolves); the modifiers are
/// parsed structurally so `supports(...)` and media queries re-serialize
/// canonically (dart-sass `tryImportModifiers`). `pos` is the 1-based
/// position of the URL token (`url(` or the opening quote): a source map
/// maps the emitted rule there, as dart's `visitCssImport` does.
class ImportArg_Css {
    url: TplPiece[],
    modifiers: ImportModifier[],
    pos: root.scanner.Pos,
    implements ImportArg {}
}

/// One parsed `@import` modifier (dart-sass `tryImportModifiers`).
interface ImportModifier {}

/// A run of bare identifiers and unknown functions (`b`, `c(d)`), joined
/// by single spaces; captured as a template (only `#{…}` resolves).
class ImportModifier_Raw {
    _0: TplPiece[],
    implements ImportModifier {}
}

/// `supports(<query>)`. `declaration` is true for a bare `supports(a: b)`
/// query, whose `Declaration` serialization already carries its own parens
/// (`supports((a: b))` also unwraps to this); every other condition gets
/// wrapped in one explicit pair.
class ImportModifier_Supports {
    condition: SupportsCondition,
    declaration: bool,
    implements ImportModifier {}
}

/// The trailing media query list (always the final modifier).
/// `comma_before` distinguishes `b, (c: d)` (a list continued after a
/// bare-identifier query) from `b (c: d)` (a space-joined list start).
class ImportModifier_Media {
    list: MediaQueryList,
    comma_before: bool,
    implements ImportModifier {}
}

/// One arm of an `@if` chain. `cond == None` is the trailing `@else`.
class IfBranch {
    cond: Expr?,
    body: Stmt[],
}

/// A `@function` or `@mixin` definition (same shape).
class Callable {
    name: string,
    params: ParamList,
    body: Stmt[],
    /// 1-based start of the declaration's `name(params)` text, and its byte
    /// length. dart underlines exactly that as the `declaration` half of an
    /// argument-binding error — `m($x)` for `@mixin m($x)`, and just `m` when
    /// there is no parameter list at all.
    decl_pos: root.scanner.Pos,
    decl_length: int,
}

/// A declared parameter list: positional/defaulted params plus an optional
/// trailing rest parameter (`$args...`).
class ParamList {
    params: Param[],
    rest: string?,
}

/// One declared parameter, with an optional default expression.
class Param {
    name: string,
    default: Expr?,
    /// 1-based position where `default`'s text starts ([`Pos::NONE`] when there
    /// is no default). Source-map only: a parameter bound from its declared
    /// default takes that default's span as its definition node, exactly like
    /// a `$x: <value>` declaration (dart `_expressionNode(parameter
    /// .defaultValue!)`, evaluate.dart:3588).
    default_pos: root.scanner.Pos,
}

class VarDecl {
    name: string,
    value: Expr,
    is_default: bool,
    is_global: bool,
    /// `Some(ns)` for a namespaced assignment `ns.$name: value`, which updates
    /// the variable in the `@use`d module bound to `ns`.
    namespace: string?,
    /// 1-based position where `value`'s text starts. Source-map only: this is
    /// the span dart records as the variable's *definition node* so a later
    /// bare `$name` reference in a declaration maps back here (dart
    /// `Environment._variableNodes`, environment.dart:93).
    value_pos: root.scanner.Pos,
}

class Rule {
    selector: TplPiece[],
    body: Stmt[],
    /// 1-based position where the selector text starts, for mapping a
    /// resolved-selector error column back to the source.
    selector_pos: root.scanner.Pos,
    /// Expression spans (line, start col, col of `}`) of the selector's
    /// top-level `#{…}` interpolations, parallel to its `Interp` pieces —
    /// for the dual-span "error in interpolated output" diagnostic.
    selector_interp_spans: root.std.Tuple3<int, int, int>[],
    /// 1-based line of the rule's opening `{` (0 when unavailable), for the
    /// serializer's trailing-comment rule.
    brace_line: int,
    /// 1-based line of the rule's closing `}` (0 when unavailable).
    end_line: int,
}

/// One top-level item in a plain-CSS custom `@function`/`@mixin` body. The
/// value is captured as a template (preserving arbitrary CSS characters
/// verbatim, resolving only `#{...}`) when the property is a plain literal,
/// or as a SassScript expression when the property contains interpolation —
/// matching dart-sass's declaration parsing inside these constructs.
class CssCustomItem {
    property: TplPiece[],
    /// `Err` holds the verbatim value template; `Ok` holds a SassScript value.
    value: CssCustomValue,
}

interface CssCustomValue {}

/// Verbatim value template (literal property): whitespace runs collapse to
/// single spaces and `#{...}` resolves, otherwise emitted exactly.
class CssCustomValue_Raw {
    _0: TplPiece[],
    implements CssCustomValue {}
}

/// SassScript value (interpolated property): evaluated normally.
class CssCustomValue_Script {
    _0: Expr,
    implements CssCustomValue {}
}

/// A nested property set on an interpolated property (`#{re}sult: {b: c}`):
/// each `(suffix, value)` child emits as `property-suffix: value`.
class CssCustomValue_Set {
    _0: root.std.Tuple2<TplPiece[], Expr>[],
    implements CssCustomValue {}
}

class Declaration {
    property: TplPiece[],
    value: Expr,
    important: bool,
    pos: root.scanner.Pos,
    /// 1-based line where the declaration's value ends (0 when unavailable),
    /// for the serializer's trailing-comment rule.
    end_line: int,
    /// 1-based position where `value`'s text starts. Source-map only: dart
    /// wraps the serialized value in `forSpan(valueSpanForMap)`
    /// (serialize.dart:389), which defaults to the value expression's own span
    /// and becomes the *variable definition's* span when the value is a bare
    /// `$name` (evaluate.dart:1414 -> `_expressionNode`, evaluate.dart:4538).
    value_pos: root.scanner.Pos,
}

/// A custom-property declaration (`--name: value`). The name and the value
/// are both templates so `#{…}` interpolation resolves at eval time; the value
/// is otherwise emitted verbatim (no SassScript evaluation).
class CustomDecl {
    property: TplPiece[],
    value: TplPiece[],
    pos: root.scanner.Pos,
    /// 1-based line where the declaration's value ends (0 when unavailable),
    /// for the serializer's trailing-comment rule.
    end_line: int,
    /// 1-based position where the verbatim value text starts. Source-map only:
    /// a custom property is serialized inside `_for(node.value, …)`
    /// (serialize.dart:379), i.e. always the value's OWN span — a custom
    /// property never routes through `_expressionNode`, so `--x: $c` maps to
    /// the `$c` text, not to `$c`'s definition.
    value_pos: root.scanner.Pos,
}

/// A nested property set: a declaration whose value (which may be empty) is
/// followed by a `{ … }` block whose children are namespaced with the parent
/// property name joined by `-`.
class PropertySet {
    property: TplPiece[],
    /// The optional leading value (`b: c { … }` keeps `c`; `b: { … }` is
    /// `None`). When present it is emitted as `<property>: <value>;` first.
    value: Expr?,
    important: bool,
    body: Stmt[],
    pos: root.scanner.Pos,
}

/// One piece of an interpolated template: literal text or an embedded
/// expression (`#{...}`).
interface TplPiece {}

/// Literal text, held as `Rc<str>` because a template that is a single
/// literal — which is what nearly every property name and unquoted value
/// keyword is — hands this buffer straight to the string it evaluates to
/// rather than copying it. The parser builds it once and never edits it.
class TplPiece_Lit {
    _0: string,
    implements TplPiece {}
}

class TplPiece_Interp {
    _0: Expr,
    implements TplPiece {}
}

/// A value expression.
interface Expr {}

/// Numeric literal: value + unit (`""` for unitless). The unit is spelled
/// out once, here, and every evaluation of the literal shares it — a
/// `1px` inside a loop body allocates no unit at all.
class Expr_Number {
    _0: float,
    _1: string,
    implements Expr {}
}

/// Color literal (hex or named), parsed eagerly.
class Expr_Color {
    _0: root.value.Color,
    implements Expr {}
}

/// Quoted string, possibly with interpolation.
class Expr_QuotedString {
    _0: TplPiece[],
    implements Expr {}
}

/// Unquoted identifier/string, possibly with interpolation
/// (e.g. `solid`, `sans-serif`, `col-#{$n}`).
class Expr_Ident {
    _0: TplPiece[],
    implements Expr {}
}

/// `true` / `false`.
class Expr_Bool {
    _0: bool,
    implements Expr {}
}

/// `null`.
class Expr_Null {
    implements Expr {}
}

/// `$name` variable reference.
class Expr_Var {
    name: string,
    pos: root.scanner.Pos,
    implements Expr {}
}

/// `ns.$name` — a module variable reference (e.g. `math.$pi`). Resolved by
/// the evaluator against the used module bound to `module`.
/// The `ns` identifier's position, and the byte length of the whole
/// `ns.$name` reference — the span dart reports against.
class Expr_NsVar {
    module: string,
    name: string,
    pos: root.scanner.Pos,
    length: int,
    implements Expr {}
}

/// The parent selector `&` used in value position. Resolves to the current
/// resolved selector as a comma-separated list of space-separated
/// compound-selector strings, or `null` at the document root.
class Expr_Parent {
    implements Expr {}
}

/// Binary arithmetic / string concatenation.
class Expr_Binary {
    op: BinOp,
    lhs: Expr,
    rhs: Expr,
    pos: root.scanner.Pos,
    implements Expr {}
}

/// The `a / b` slash operator. When `slash` is true (both operands are
/// number literals or themselves slash divisions), it produces a
/// slash-separated value that serializes as `a/b`; otherwise it performs
/// real division.
class Expr_Div {
    lhs: Expr,
    rhs: Expr,
    slash: bool,
    pos: root.scanner.Pos,
    implements Expr {}
}

/// A `calc()` calculation whose interior is the wrapped expression.
/// Evaluated with calc simplification rules (numeric subtrees fold,
/// everything else is preserved verbatim).
class Expr_Calc {
    inner: Expr,
    implements Expr {}
}

/// Unary negation.
class Expr_Unary {
    op: UnOp,
    operand: Expr,
    implements Expr {}
}

/// Function call. `module` is the namespace of a `ns.fn(...)` call (the
/// part before the dot); `None` for an ordinary unqualified call.
/// 1-based position of the function-name start (the call's primary span
/// origin for diagnostics — `rgb(…)` points at `rgb`).
/// Byte length of the whole call `name(args)`, for the diagnostic caret.
class Expr_Func {
    name: string,
    args: CallArg[],
    pos: root.scanner.Pos,
    length: int,
    module: string?,
    implements Expr {}
}

/// A function call whose name contains interpolation (`qu#{o}te(arg)`).
/// dart-sass treats these as *plain CSS* calls: the name resolves at
/// eval time, the arguments are evaluated, and the call serializes
/// verbatim — never dispatched to a built-in or user function.
class Expr_InterpFunc {
    name: TplPiece[],
    args: CallArg[],
    pos: root.scanner.Pos,
    implements Expr {}
}

/// A space- or comma-separated list. `bracketed` marks `[a b]`/`[a, b]`
/// literals, which serialize wrapped in square brackets.
class Expr_List {
    items: Expr[],
    sep: root.value.ListSep,
    bracketed: bool,
    implements Expr {}
}

/// `( expr )`.
class Expr_Paren {
    _0: Expr,
    implements Expr {}
}

/// A map literal `(k1: v1, k2: v2)`. Disambiguated from a parenthesised
/// expression / list by the `:` after the first key. An empty map is
/// written `()` but parses as the empty list; only a non-empty
/// `(k: v, …)` produces this node.
class Expr_Map {
    _0: root.std.Tuple2<Expr, Expr>[],
    implements Expr {}
}

/// `#{ expr }` used in value position — always yields an unquoted
/// string.
class Expr_Interp {
    _0: Expr,
    implements Expr {}
}

/// The modern CSS `if()` conditional: a `;`-separated list of clauses,
/// each `<condition>: <value>` (or `else: <value>`). Conditions mix
/// `sass(<expr>)` (evaluated) and `css(...)`/other "arbitrary
/// substitution" pieces (kept verbatim). Distinct from the legacy
/// `if($cond, $t, $f)` builtin, which routes through [`Expr::Func`].
class Expr_ModernIf {
    _0: IfClause[],
    implements Expr {}
}

/// One clause of a modern `if()`: an optional condition (absent for the
/// trailing `else` clause) and its value expression.
class IfClause {
    /// `None` for the `else` clause; otherwise the parsed condition tree.
    condition: IfCond?,
    value: Expr,
}

/// A modern `if()` condition tree. Atoms are either an evaluated
/// `sass(<expr>)` or a verbatim "raw" CSS sequence (`css(...)`, `var(...)`,
/// nested `if(...)`, interpolation, ...); combined with `not`/`and`/`or`
/// and parentheses.
interface IfCond {}

/// `sass(<expr>)` — evaluated for truthiness.
class IfCond_Sass {
    _0: Expr,
    implements IfCond {}
}

/// One or more space-separated raw substitution tokens forming a single
/// non-evaluable CSS condition (each token is a template so embedded
/// `#{...}` resolves at eval time). `multi` is true when the sequence has
/// more than one token (an "arbitrary substitution", which may not
/// coexist with `sass()` in the same condition).
class IfCond_Raw {
    pieces: TplPiece[],
    multi: bool,
    implements IfCond {}
}

/// `not <cond>`.
class IfCond_Not {
    _0: IfCond,
    implements IfCond {}
}

/// `<cond> and <cond>` (one or more, left-associative chain).
class IfCond_And {
    _0: IfCond[],
    implements IfCond {}
}

/// `<cond> or <cond>` (one or more, left-associative chain).
class IfCond_Or {
    _0: IfCond[],
    implements IfCond {}
}

/// `( <cond> )`.
class IfCond_Paren {
    _0: IfCond,
    implements IfCond {}
}

/// A call argument, optionally named (`$name: value`).
///
/// A `splat` argument (`$list...`) is expanded at call time: a list spreads
/// into positional arguments and a map spreads into keyword arguments. A
/// splat argument never carries a `name`.
class CallArg {
    name: string?,
    value: Expr,
    splat: bool,
    /// 1-based position where `value`'s text starts. Source-map only: binding a
    /// parameter to this argument records the argument's span as the
    /// parameter's definition node, so `@mixin m($p) { pad: $p }` invoked as
    /// `@include m(4px)` maps the emitted `4px` back to the CALL SITE (dart
    /// `evaluated.positionalNodes` / `namedNodes`, evaluate.dart:3572-3592).
    value_pos: root.scanner.Pos,
}

enum BinOp {
    Add,
    Sub,
    Mul,
    Mod,
    Eq,
    Neq,
    Lt,
    Gt,
    Le,
    Ge,
    And,
    Or,
    /// The single-`=` Microsoft-filter operator, valid only inside a function
    /// argument list (`alpha(opacity=80)`). It is the lowest-precedence value
    /// operator: both sides are evaluated and joined with `=` (no spaces) as an
    /// unquoted string.
    SingleEq,
}

enum UnOp {
    Neg,
    /// Unary `+`: numeric identity (`+5` -> `5`); on any other operand an
    /// unquoted string prefixed with `+` (`+foo` -> `+foo`), matching
    /// dart-sass's `unaryPlus`.
    Plus,
    Not,
}

// ---- media queries -----------------------------------------------------
/// A `@media` prelude: a comma-separated list of media queries.
class MediaQueryList {
    queries: MediaQuery[],
}

/// One media query: either a media-type form (`[not|only]? <type> [and
/// <cond>]*`) or a condition-only form (`<cond> [<and|or> <cond>]*`).
interface MediaQuery {}

/// `[modifier]? <type> [and <cond>]*`. The modifier (`not`/`only`,
/// already lowercased) and type may contain interpolation.
class MediaQuery_Type {
    modifier: TplPiece[]?,
    mtype: TplPiece[],
    conditions: MediaInParens[],
    implements MediaQuery {}
}

/// `<cond> [<and|or> <cond>]*`.
class MediaQuery_Condition {
    conditions: MediaInParens[],
    conjunction: Conjunction,
    implements MediaQuery {}
}

/// `and` / `or`, the conjunction joining media conditions.
enum Conjunction {
    And,
    Or,
}

/// A single "media in parens": one operand of a media condition.
interface MediaInParens {}

/// `(<feature>)` — serialized wrapped in parentheses. Boxed because a
/// [`MediaFeature`] is large relative to the other variants.
class MediaInParens_Feature {
    _0: MediaFeature,
    implements MediaInParens {}
}

/// `not <media-in-parens>` — serialized without wrapping parentheses.
class MediaInParens_Not {
    _0: MediaInParens,
    implements MediaInParens {}
}

/// `(<cond> <and|or> <cond>…)` — a parenthesised sub-condition group,
/// serialized keeping its parentheses.
class MediaInParens_Group {
    conditions: MediaInParens[],
    conjunction: Conjunction,
    implements MediaInParens {}
}

/// Raw interpolation spliced into the query verbatim, e.g.
/// `(a) and #{"(b) and (c)"}`.
class MediaInParens_Interp {
    _0: Expr,
    implements MediaInParens {}
}

/// The interior of a single `(...)` media feature.
interface MediaFeature {}

/// `(<name>)` or `(<name>: <value>)`.
class MediaFeature_Decl {
    name: Expr,
    value: Expr?,
    implements MediaFeature {}
}

/// A range feature: `<first> <op1> <second> [<op2> <third>]`.
class MediaFeature_Range {
    first: Expr,
    op1: string,
    second: Expr,
    rest: root.std.Tuple2<string, Expr>?,
    implements MediaFeature {}
}

// ---- @supports conditions ----------------------------------------------
/// A parsed `@supports` condition (dart-sass `SupportsCondition`). The
/// condition is re-serialized canonically at eval time: `(a: b)` declaration
/// spacing, stripped trivia comments, normalized whitespace.
interface SupportsCondition {}

/// `(<name>: <value>)`. `custom` is true when the name is a literal
/// unquoted identifier starting with `--`; its value is then captured
/// verbatim (a template) and serialized with no space after the colon.
class SupportsCondition_Declaration {
    name: Expr,
    value: SupportsValue,
    custom: bool,
    implements SupportsCondition {}
}

/// `not <condition-in-parens>`.
class SupportsCondition_Negation {
    _0: SupportsCondition,
    implements SupportsCondition {}
}

/// `<left> <and|or> <right>`.
class SupportsCondition_Operation {
    left: SupportsCondition,
    right: SupportsCondition,
    op: Conjunction,
    implements SupportsCondition {}
}

/// A lone `#{…}` interpolation spliced in verbatim (unquoted).
class SupportsCondition_Interpolation {
    _0: Expr,
    implements SupportsCondition {}
}

/// `<name>(<arguments>)` — a `supports()`-style function call. Both the
/// name and the arguments are templates captured verbatim.
class SupportsCondition_Function {
    name: TplPiece[],
    arguments: TplPiece[],
    implements SupportsCondition {}
}

/// `(<anything>)` — an arbitrary parenthesised value captured verbatim
/// (the declaration grammar didn't match, e.g. `(a b)` or `(a !&$)`).
class SupportsCondition_Anything {
    _0: TplPiece[],
    implements SupportsCondition {}
}

/// The right-hand side of a `@supports` declaration condition.
interface SupportsValue {}

/// A normal SassScript expression value (`(a: 1 + 1)` -> `(a: 2)`).
class SupportsValue_Expr {
    _0: Expr,
    implements SupportsValue {}
}

/// A custom-property value captured verbatim as a template (only `#{…}`
/// interpolation resolves); serialized with no space after the colon.
class SupportsValue_Raw {
    _0: TplPiece[],
    implements SupportsValue {}
}
