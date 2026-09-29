// Ported from sasso `src/eval/mod.rs` (namespace `root.eval`).
//
// The evaluator: walks the AST, resolving variables, nesting (`&` and
// the parent×child selector product), interpolation and arithmetic, and
// flattens the result into a list of output rules.
//
// Like dart-sass (and unlike grass), a rule's own declarations are
// gathered into a single block emitted *before* its nested rules bubble
// out after it.

// mod at_rules → namespace `root.eval.at_rules`

// mod binop → namespace `root.eval.binop`

// mod calc → namespace `root.eval.calc`

// mod control_flow → namespace `root.eval.control_flow`

// mod expr → namespace `root.eval.expr`

// mod meta → namespace `root.eval.meta`

// mod modules → namespace `root.eval.modules`

// mod plain_css → namespace `root.eval.plain_css`

// mod scope → namespace `root.eval.scope`

/// One cached `@import` resolution: (resolved canonical key, syntax, parsed
/// sheet, source text, the importer's `source_map_url`), shared across
/// repeated imports within a single compile. The source rides along so
/// re-executions can swap it in as the current diagnostics/stamp context.
type CachedImport = root.std.Tuple5<string, root.Syntax, root.ast.Stylesheet, string, string?>;

/// Parse imported/`@use`d source with the front-end matching its file syntax.
function parse_with_syntax(src: string, syntax: root.Syntax) -> root.ast.Stylesheet {
    match (syntax) {
        root.Syntax.Scss => root.parser.parse(src),
        root.Syntax.Css => root.parser.parse_plain_css(src),
        root.Syntax.Sass => root.sass_parser.parse(src),
    }
}

/// A call's evaluated arguments, split into positional values and named
/// `(name, value)` keyword pairs (after splat expansion), plus the rest-
/// argument list separator (a splatted list's separator survives into the
/// callee's arglist; comma otherwise).
type EvaledArgs = root.std.Tuple3<
    root.value.Value[],
    root.std.Tuple2<string, root.value.Value>[],
    root.value.ListSep
>;

/// Definition spans for the values in an [`EvaledArgs`], parallel to its
/// positional and keyword vectors (dart `ArgumentResults.positionalNodes` /
/// `namedNodes`). Binding a parameter to an argument copies the matching span
/// so `@mixin m($p) { pad: $p }` + `@include m(4px)` maps the emitted `4px`
/// back to the CALL SITE. Source-map only.
class ArgSpans {
    positional: VarSpan[],
    named: root.std.Tuple2<string, VarSpan>[],

    /// derive(Default)
    function default() -> ArgSpans {
        ArgSpans { positional: [], named: [] }
    }

    /// The span recorded for positional argument `i`, if any.
    function positional_(self, i: int) -> VarSpan {
        self.positional.at(i) ?? VarSpan.default()
    }

    /// The span recorded for the keyword argument spelled `name` (compared
    /// hyphen/underscore-insensitively, like the value lookup).
    function named_(self, name: string) -> VarSpan {
        let key = normalize_arg_name(name);
        let found = self.named.find((p) -> {
            normalize_arg_name(p._0) == key
        });
        if (found != null) {
            found._1
        } else {
            VarSpan.default()
        }
    }
}

/// One variable scope. Lexical scoping shares frames between the active
/// chain and callable closures (dart's Environment maps), so a scope is a
/// shared, interior-mutable map.
type Scope = map<string, root.value.Value>;

function new_scope() -> Scope {
    let scope: Scope = {};
    scope
}

/// How many popped scope tables to keep for reuse. Blocks nest, so the pool
/// only has to cover a sheet's nesting depth plus the churn of its siblings;
/// past that, freeing a table is cheaper than holding its buckets.
function SCOPE_POOL_MAX() -> int {
    32
}

/// A table wider than this came from a block with an unusual number of
/// bindings. Parking it would keep those buckets alive for the whole compile,
/// which is the one thing the pool must not trade for its allocations.
function SCOPE_POOL_MAX_CAPACITY() -> int {
    64
}

/// Park a popped scope table for reuse, or let it go.
///
/// The table returns to the pool only when this is the LAST reference to it: a
/// closure that captured the chain — a `@function` or `@mixin` body, a
/// `@content` block — holds an `Rc` of its own, and the bindings it can still
/// read must stay exactly where they are. `Rc::strong_count` answers precisely
/// that question, and a `Weak` (none exist today) would be one more holder, so
/// it is checked too.
function recycle_scope<T>(pool: map<string, T>[], scope: map<string, T>) -> void {
    // PORT: `Rc::strong_count(&scope) != 1 || Rc::weak_count(&scope) != 0` is
    // unobservable in BAML (no reference counts), so this table can never be
    // PROVEN to be the last reference: a closure that captured the chain may
    // still read it, and clearing it would erase those bindings. The pool is an
    // allocation optimization only, so every table is treated as shared and let
    // go; the pool simply stays empty.
    let shared = true;
    if (pool.length() >= SCOPE_POOL_MAX() || shared) {
        return;
    }
    {
        let vars = scope;
        // PORT: `capacity()` -> `length()` (maps expose no capacity).
        if (vars.length() > SCOPE_POOL_MAX_CAPACITY()) {
            return;
        }
        // `clear` keeps the buckets: the next block to take this table finds an
        // empty map that no longer has to build its own.
        vars.clear();
    };
    pool.push(scope);
}

/// Where a variable was DEFINED: the interned source file id plus the 0-based
/// line/column of the defining expression's first character.
///
/// This is sasso's equivalent of the `AstNode` dart stores in
/// `Environment._variableNodes` (environment.dart:93) — a map kept in lockstep
/// with `_variables`, holding, for each binding, the node whose span should be
/// blamed for the value. It exists purely for source maps and diagnostics
/// alignment: no CSS byte depends on it.
///
/// `file == 0` means "unknown" (a synthesized binding with no source text, e.g.
/// a built-in module variable or a host-function argument); the source map
/// drops such entries.
class VarSpan {
    file: int,
    /// 0-based source line.
    line: int,
    /// 0-based source column.
    col: int,

    /// derive(Default)
    function default() -> VarSpan {
        VarSpan { file: 0, line: 0, col: 0 }
    }
}

/// One frame of the variable-definition-span chain, parallel to [`Scope`]
/// (dart's `Environment._variableNodes` is a `List<Map<String, AstNode>>`
/// pushed and popped in lockstep with `_variables`). Shared by `Rc` so a
/// callable's captured closure sees later writes to the frames it closed over,
/// exactly like the value chain.
type SpanScope = map<string, VarSpan>;

function new_span_scope() -> SpanScope {
    let scope: SpanScope = {};
    scope
}

/// One function/mixin scope frame, parallel to the variable chain (dart's
/// `Environment._functions`/`_mixins` are lists of maps pushed and popped in
/// lockstep with `_variables`).
type FnScope = map<string, UserCallable>;

function new_fn_scope() -> FnScope {
    let scope: FnScope = {};
    scope
}

/// One frame of the function or mixin chain, EMPTY until something is defined
/// in it. Nearly every block is empty: a `@function` or `@mixin` is written at
/// the top level of a file or a mixin body, while the blocks that push a frame
/// are style rules and control flow, which almost never declare one. `None`
/// says "no definitions here" without paying for a table to hold them.
///
/// The frame is materialized on the two events that can make it observable
/// beyond the current block — a definition landing in it
/// ([`Evaluator::define_function`]) and the chain being closed over by a
/// callable or a `@content` block — so a materialized frame is always the
/// SHARED `Rc` the chain and every closure over it see, exactly as an eagerly
/// allocated one was (see [`materialize_fn_frames`]).
type FnFrame = FnScope?;

/// Give every frame of a function or mixin chain a table, so the chain can be
/// cloned into a lexical closure.
///
/// A closure over the chain (a callable's capture, a `@content` block's call-site
/// snapshot) does not copy the frames — it shares them, so a definition written
/// into a frame afterwards is visible through both. A cloned `None` would share
/// nothing: each side would materialize its own table on its next definition and
/// the other would never see it. Materializing first keeps the sharing that an
/// eagerly allocated frame had, and costs an allocation only for frames that
/// went unused up to this point.
function materialize_fn_frames(chain: FnFrame[]) -> void {
    // PORT: `for frame in chain { frame.get_or_insert_with(new_fn_scope) }` —
    // an index loop, since the slot itself is replaced.
    let i = 0;
    while (i < chain.length()) {
        if (chain[i] == null) {
            chain[i] = new_fn_scope();
        }
        i += 1;
    }
}

/// The `@use` namespace tables visible at a callable's definition site.
/// dart's `Environment.closure()` carries them with the rest of the lexical
/// environment: a callable inlined by `@import` must resolve `list.length()`
/// against ITS file's `@use "sass:list"`, not whatever the caller has bound
/// (uswds `units()`, quasar `str-fe()`).
class EnvModules {
    used_modules: map<string, string>,
    star_modules: string[],
    used_user_modules: map<string, Module>,
    star_user_modules: Module[],
}

/// A user `@function`/`@mixin` with its LEXICAL environment: the variable and
/// function/mixin scope chains captured at the definition site (shared
/// frames, dart's `Environment.closure()`). The body runs against these
/// chains, not the caller's stack.
/// What an argument-binding failure points back at: the callable's name for
/// the message, and the `name(params)` span in the file it was DECLARED in,
/// which dart draws as the error's second span.
class Declared {
    pos: root.scanner.Pos,
    length: int,
    /// The file the declaration is in. `None` means the current one.
    origin: root.value.MixinOrigin?,
}

class UserCallable {
    def: root.ast.Callable,
    /// The file that defined the callable. Its body runs against that file
    /// (dart evaluates a mixin or function where it was written): output maps
    /// to it, and diagnostics show its name and source — whether it was
    /// reached through `@use`, a textual `@import`, or a first-class
    /// reference. Always present: `capture_callable` is the only way a
    /// callable is built, and it records the file every time, so there is no
    /// "ask the module it came from" fallback to get wrong.
    origin: root.value.MixinOrigin,
    env: Scope[],
    /// The variable-definition-span chain captured alongside `env`, frame for
    /// frame (dart closes over `_variableNodes` with the rest of the
    /// environment).
    env_spans: SpanScope[],
    env_semi: bool[],
    env_fns: FnFrame[],
    env_mixins: FnFrame[],
    env_modules: EnvModules,
}

/// A style rule's selector list, carried through the output tree either as the
/// raw resolved strings (the common case — no `@extend` rewrote it, so it is
/// never parsed) or as the typed `Complex` list the `@extend` engine produced
/// (Phase 1d: the engine works on the typed model directly — no `join(", ")` +
/// `parse_list` round trip — and emit renders it via `Complex::render()`, which
/// is byte-identical to the strings the engine used to materialize).
interface RuleSelectors {
    /// The selector list as rendered strings: the `Raw` slice borrowed
    /// directly, or each `Parsed` `Complex` rendered (byte-identical to the
    /// strings the extend engine used to produce). Used by emit and by the
    /// pre-extend passes (reparent, plain-CSS at-body lowering) and the
    /// cross-media probe.
    function to_strings(self) -> string[] throws never {
        match (self) {
            // PORT: `Cow::Borrowed` -> the shared list itself (callers only read it).
            let v: RuleSelectors_Raw => v._0,
            let v: RuleSelectors_Parsed => {
                v._0.map((c) -> {
                    c.render()
                })
            },
            _ => root.std.unreachable(),
        }
    }

    /// Consume into rendered strings (owned), for the pre-extend lowering paths
    /// that move a rule's selectors into an `OutItem`/joined parent shell.
    function into_strings(self) -> string[] throws never {
        match (self) {
            // The one owner is the common case (a rule flushes a single
            // block); a shared list is copied here rather than at every flush.
            // PORT: `Rc::try_unwrap` cannot tell a unique list from a shared one in
            // BAML, so the (owned, possibly mutated) result is always a copy.
            let v: RuleSelectors_Raw => root.std.clone_vec(v._0),
            let v: RuleSelectors_Parsed => {
                v._0.map((c) -> {
                    c.render()
                })
            },
            _ => root.std.unreachable(),
        }
    }
}

/// The already-resolved selector strings (`&`/interpolation substituted).
/// Untouched by the extend pass — emit writes them verbatim. This is the
/// zero-parse fast path: an extend-free stylesheet never leaves this form.
///
/// Shared: a style rule resolves its list once, and the same list reaches
/// `current_selector`, every nested rule's `parents` and every block this
/// rule flushes. Nothing mutates it in place.
class RuleSelectors_Raw {
    _0: string[],
    implements RuleSelectors {}
}

/// The typed selector list a rewrite produced. Rendered only at emit, via
/// the same `Complex::render()` the engine used to materialize its strings.
class RuleSelectors_Parsed {
    _0: root.selector.Complex[],
    implements RuleSelectors {}
}

/// Which dart-sass node class an at-rule came from — a fact its NAME cannot
/// answer, because the PARSER decides the class and the evaluator is only where
/// an interpolated name finally reads `media`. `@#{"media"} (a: 1) {…}` is a
/// generic at-rule in dart, spelled `@media (a: 1)`; only a parsed `@media` is a
/// conditional group rule.
///
/// The difference is observable twice, both times making a conditional rule LESS
/// visible than a generic one: it is the only kind that omits the compressed
/// space before a `(` prelude (`visitCssMediaRule`/`visitCssSupportsRule`), and
/// the only kind that goes away when its block writes nothing (`_isInvisible`
/// short-circuits on `CssAtRule` — "an unknown at-rule is never invisible …
/// we can't guarantee that (for example) `@foo {}` isn't meaningful").
enum AtRuleKind {
    /// dart `CssMediaRule` or `CssSupportsRule`.
    Conditional,
    /// dart `CssAtRule`: an unknown at-rule, `@font-face`, `@page`,
    /// `@keyframes`, a plain-CSS custom `@function`/`@mixin` — and any at-rule
    /// whose name arrived through interpolation, whatever that name spells.
    Generic,
}

interface AtRuleKindMethods {
    /// Whether this is one of the two conditional group rules.
    function is_conditional(self) -> bool throws unknown;
}

implements AtRuleKindMethods for AtRuleKind {
    /// Whether this is one of the two conditional group rules.
    function is_conditional(self) -> bool {
        self == AtRuleKind.Conditional
    }

}

/// A flattened output node.
interface OutNode {
    /// A control-only marker that never serializes: `GroupEnd`, `MediaHoist`,
    /// `AtRootHoist` and `AtRootPackTight`. Such markers may sit between two
    /// nodes without separating them for blank-line purposes.
    function is_inert_marker(self) -> bool throws never {
        (
            self is OutNode_GroupEnd
                || self is OutNode_MediaHoist
                || self is OutNode_AtRootHoist
                || self is OutNode_AtRootPackTight
        )
    }
}

/// Per-complex "line break before" flags from the source selector list
/// (`a,\nb` keeps the newline). Empty means none (all comma-joined with
/// a space); otherwise parallel to `selectors`.
/// Source lines (`start` = the `{` line, `end` = the `}` line) for the
/// serializer's trailing-comment rule; default = disabled.
/// The number of `@extend`s already registered when this rule's selector
/// was established (dart-sass `addSelector` timing). When the rule was
/// registered AFTER every applicable `@extend` (`extend_base >=`
/// visible-extension count), dart extends the fresh selector by the whole
/// store at ONCE — `_extendComplex`'s `paths` unification order (last
/// choice slowest) — rather than re-extending it incrementally
/// (registration-order fold). `usize::MAX` marks a non-evaluated rule
/// (plain-CSS import, `@at-root` graft, reparent shell) for which the
/// sequential default always applies.
class OutNode_Rule {
    selectors: RuleSelectors,
    linebreaks: bool[],
    items: OutItem[],
    lines: root.ast.SrcLines,
    extend_base: int,
    implements OutNode {}
}

class OutNode_Comment {
    _0: string,
    _1: root.ast.SrcLines,
    implements OutNode {}
}

/// A verbatim line (e.g. a passed-through CSS `@import`). The `SrcLines`
/// carry a source-map position in the map-override fields only — a
/// passed-through `@import` maps to its URL token, as in dart's
/// `visitCssImport` — and take no part in the trailing-comment rule.
class OutNode_Raw {
    _0: string,
    _1: root.ast.SrcLines,
    implements OutNode {}
}

/// A blank-line separator between top-level groups (expanded only).
class OutNode_Blank {
    implements OutNode {}
}

/// An at-rule: `@name prelude { body }` (when `has_block`) or
/// `@name prelude;` (when not). The body holds the bubbled-out child
/// nodes; bare declarations appear as [`OutNode::AtDecl`].
/// Which dart node class this is (see [`AtRuleKind`]), which `name`
/// cannot be asked: an interpolated `@#{"media"}` arrives here spelling
/// `media` and is generic.
/// Source lines (`start` = the `{` line or the statement's own line
/// for the `;` form, `end` = the `}` line or the same) for the
/// serializer's trailing-comment rule; default = disabled.
class OutNode_AtRule {
    name: string,
    prelude: string,
    body: OutNode[],
    has_block: bool,
    kind: AtRuleKind,
    lines: root.ast.SrcLines,
    implements OutNode {}
}

/// A module's spliced CSS, tagged with its canonical key so the extend
/// pass can scope extensions (dart-sass: an `@extend` affects the module's
/// own CSS and its transitive upstreams, never siblings or downstream).
/// Emits transparently as its contents.
class OutNode_ModuleScope {
    key: string,
    nodes: OutNode[],
    implements OutNode {}
}

/// A bare declaration emitted directly inside an at-rule body (e.g.
/// `@font-face { font-family: x; }`).
/// Shared, like [`OutItem::Decl`]'s — this node is repacked from one.
/// A custom property (`--x`) whose value is emitted verbatim after the
/// colon (no inserted space); its leading whitespace is part of `value`.
/// Source lines (only `file` and `end` are meaningful) for the
/// serializer's trailing-comment rule; default = disabled.
/// Where the emitted VALUE maps back to (dart `valueSpanForMap`,
/// serialize.dart:390). Source-map only.
class OutNode_AtDecl {
    prop: string,
    value: string,
    important: bool,
    custom: bool,
    lines: root.ast.SrcLines,
    value_span: VarSpan,
    implements OutNode {}
}

/// Control-only marker (never serialized): the end of a completed top-level
/// style rule's output group (dart-sass `isGroupEnd`). The next group gets a
/// blank line even when the group ended in a bubbled at-rule. Consumed by the
/// next `push_group`; any survivor is skipped by the emitters.
class OutNode_GroupEnd {
    implements OutNode {}
}

/// Control-only marker (never serialized): left in an enclosing `@media` body
/// where a merged nested media rule bubbled out; the outer rule splits its own
/// children around it.
class OutNode_MediaHoist {
    implements OutNode {}
}

/// Control-only marker (never serialized): left where an `@at-root` hoisted a
/// batch out of one or more enclosing at-rules. `target` is the batch's graft
/// target (the index of the topmost EXCLUDED at-rule layer — dart
/// `_trimIncluded`). Each enclosing layer below the target splits around the
/// marker and passes it outward; the layer whose body sits at the target depth
/// consumes it — target 0 means the batch re-enters at the document root,
/// between the outermost layer's segments, while a deeper target grafts INTO
/// that layer's own body.
class OutNode_AtRootHoist {
    target: int,
    implements OutNode {}
}

/// Control-only marker (never serialized): trailing sentinel after a placed
/// at-root batch — the next top-level group packs tight against it (no blank
/// line), and the emitters skip it.
class OutNode_AtRootPackTight {
    implements OutNode {}
}

/// A non-evaluated style rule — a plain-CSS passthrough, an `@at-root`
/// graft, a reparent shell, etc. It carries no per-complex line breaks and
/// `extend_base` `usize::MAX`, so the `@extend` pass always applies the
/// sequential default. Only `selectors`, `items` and `lines` vary across
/// the call sites; the rest is shared boilerplate.
function OutNode_plain_rule(
    selectors: string[],
    items: OutItem[],
    lines: root.ast.SrcLines,
) -> OutNode {
    OutNode_Rule {
        selectors: RuleSelectors_Raw { _0: selectors },
        linebreaks: [],
        items: items,
        lines: lines,
        extend_base: root.std.INT_MAX(),
    }
}

/// A childless at-rule (`@name prelude;`) — no body, no block.
function OutNode_childless_at_rule(
    name: string,
    prelude: string,
    lines: root.ast.SrcLines,
) -> OutNode {
    OutNode_AtRule {
        name: name,
        prelude: prelude,
        body: [],
        has_block: false,
        // A conditional group rule always has a block, so a childless
        // at-rule is generic whatever it is called: `@#{"media"} (a: 1);`
        // keeps the compressed space a real `@media` would drop.
        kind: AtRuleKind.Generic,
        lines: lines,
    }
}

/// A media query resolved to its final string components, ready to serialize
/// and to merge with nested queries (dart-sass `CssMediaQuery`).
class ResolvedQuery {
    /// `not`/`only`, already lowercased; `None` for a condition-only query.
    modifier: string?,
    /// The media type (e.g. `screen`); `None` for a condition-only query.
    mtype: string?,
    /// Serialized condition strings (e.g. `(a)`, `not (b)`, `((a) or (b))`).
    conditions: string[],
    /// Whether the conditions are joined by `and` (true) or `or` (false).
    conjunction_and: bool,
    /// Serialize one query (dart-sass `CssMediaQuery.toString`). `compressed`
    /// tightens the `and`/`or` separators per dart's compressed serializer.
    function render(self, compressed: bool) -> string {
        // PORT: the `String` handed to `push_media_sep` as `&mut` → a `StrBuf`.
        let s = root.std.StrBuf.new();
        let m = self.modifier;
        if (m != null) {
            s.push_str(m);
            s.push(" ");
        }
        let t = self.mtype;
        if (t != null) {
            s.push_str(t);
            if (self.conditions.length() > 0) {
                // A media type is an identifier, so the space is kept
                // (`screen and (a)`) — the `ends_with(')')` rule yields that.
                push_media_sep(s, true, compressed);
            }
        }
        let i = 0;
        for (let c in self.conditions) {
            if (i > 0) {
                push_media_sep(s, self.conjunction_and, compressed);
            }
            s.push_str(c);
            i += 1;
        }
        s.as_str()
    }
}

/// The result of merging two media queries (dart-sass `MediaQueryMergeResult`).
interface MergeResult {}

/// Mutually exclusive — the merged query selects nothing.
class MergeResult_Empty {
    implements MergeResult {}
}

/// The merge can't be represented as a single query; keep them nested.
class MergeResult_Unrepresentable {
    implements MergeResult {}
}

/// A single merged query.
class MergeResult_Query {
    _0: ResolvedQuery,
    implements MergeResult {}
}

/// An item inside a rule block.
interface OutItem {}

/// The property name. Shared rather than owned, because a plain
/// property name (which is nearly all of them) is a single literal in
/// the AST and this is that literal.
/// A custom property (`--x`) whose value is emitted verbatim after the
/// colon (no inserted space); its leading whitespace is part of `value`.
/// Source lines (only `file` and `end` are meaningful) for the
/// serializer's trailing-comment rule; default = disabled.
/// Where the emitted VALUE maps back to. dart wraps the serialized
/// value in `_buffer.forSpan(node.valueSpanForMap, …)`
/// (serialize.dart:389): normally the value expression's own start, but
/// the variable's DEFINITION when the value is a bare `$name`
/// (evaluate.dart:1414 -> `_expressionNode`). Source-map only — this
/// field can never change a CSS byte.
class OutItem_Decl {
    prop: string,
    value: string,
    important: bool,
    custom: bool,
    lines: root.ast.SrcLines,
    value_span: VarSpan,
    implements OutItem {}
}

class OutItem_Comment {
    _0: string,
    _1: root.ast.SrcLines,
    implements OutItem {}
}

/// A childless at-rule (`@e f;`) that appears directly inside a style rule:
/// dart-sass keeps it in the parent block (interleaved with declarations),
/// unlike a block at-rule which bubbles out to the document root.
/// Whether this is a plain-CSS `@import` written as one — dart's
/// `CssImport`, which compressed output spells `@import"x.css"` with no
/// gap. An at-rule that merely RESOLVES to that name (`@#{"import"}`)
/// is generic in dart and keeps its gap, so this cannot be recovered
/// from `name`.
/// Source lines (only `file` and `end` are meaningful) for the
/// serializer's trailing-comment rule; default = disabled.
class OutItem_ChildlessAtRule {
    name: string,
    prelude: string,
    css_import: bool,
    lines: root.ast.SrcLines,
    implements OutItem {}
}

/// A style rule nested directly inside another, kept verbatim instead of
/// flattened. Only produced in plain-CSS mode (a loaded `.css` file).
/// Per selector, whether it started on its own line in the source:
/// dart keeps a nested plain-CSS rule's selector list as written
/// (`e,\n  f {`), like a top-level rule's (`OutNode::Rule`).
/// Source-map position of the selector's first character (dart maps
/// `node.selector.span.start`), in the map-override fields only.
class OutItem_NestedRule {
    selectors: string[],
    linebreaks: bool[],
    items: OutItem[],
    lines: root.ast.SrcLines,
    implements OutItem {}
}

/// A block at-rule (`@media`, `@supports`, unknown) nested inside an
/// already-nested plain-CSS rule, kept in place instead of bubbled —
/// dart-sass `_hasCssNesting`: once the user opts into native CSS nesting,
/// at-rules stay where they are. Produced in plain-CSS mode, and for a
/// `@media` inside a keyframe block, which nests verbatim because a frame is
/// not a style rule.
/// Which dart node class this is, as for [`OutNode::AtRule`].
/// Source lines of the at-rule, as for [`OutNode::AtRule`]: its `@`
/// keyword's line and column drive the source-map entry.
class OutItem_NestedAtRule {
    name: string,
    prelude: string,
    items: OutItem[],
    kind: AtRuleKind,
    lines: root.ast.SrcLines,
    implements OutItem {}
}

/// Which kind of module member an existence predicate (`function-exists`,
/// `mixin-exists`, `global-variable-exists` with a `$module`) queries.
enum MemberKind {
    Function,
    Mixin,
    Variable,
}

/// Where evaluated statements deposit their output. At the top level each
/// statement forms its own blank-separated group; inside a style rule,
/// declarations join the rule's block and nested rules bubble out after it.
/// This is the seam that lets one block executor serve the top level, rule
/// bodies, and every nested-block construct (conditionals, loops, mixins).
/// The enclosing rule's selector list as a sink sees it. A style rule owns a
/// shared handle it can hand to every block it flushes for the price of a
/// refcount; a sink that only has the enclosing selectors as a slice copies
/// them once per block instead.
interface SinkSelectors {
    function as_slice(self) -> string[] throws never {
        match (self) {
            let v: SinkSelectors_Shared => v._0,
            let v: SinkSelectors_Borrowed => v._0,
            _ => root.std.unreachable(),
        }
    }

    function is_empty(self) -> bool throws never {
        self.as_slice().length() == 0
    }

    /// A handle to hand to an output node: free for a shared list, one copy for
    /// a borrowed one.
    function to_shared(self) -> string[] throws never {
        match (self) {
            let v: SinkSelectors_Shared => v._0,
            let v: SinkSelectors_Borrowed => root.std.clone_vec(v._0),
            _ => root.std.unreachable(),
        }
    }
}

class SinkSelectors_Shared {
    _0: string[],
    implements SinkSelectors {}
}

class SinkSelectors_Borrowed {
    _0: string[],
    implements SinkSelectors {}
}

interface Sink {
    function is_top(self) -> bool throws never {
        self is Sink_Top
    }

    function is_rule(self) -> bool throws never {
        self is Sink_Rule
    }

    /// Deposit a childless at-rule (`@e f;`). Inside a style rule it joins the
    /// parent's block (interleaved with declarations, in source order); at the
    /// top level or inside an at-rule body it is a bubbled-out `OutNode`.
    function push_childless_at_rule(
        self,
        name: string,
        prelude: string,
        lines: root.ast.SrcLines,
    ) -> void throws never {
        match (self) {
            let r: Sink_Rule => {
                r.items.push(
                    OutItem_ChildlessAtRule {
                        name: name,
                        prelude: prelude,
                        css_import: false,
                        lines: lines,
                    },
                )
            },
            _ => self.push_at_rule(OutNode_childless_at_rule(name, prelude, lines)),
        }
    }

    function push_comment(self, text: string, lines: root.ast.SrcLines) -> void throws never {
        // dart-sass strips a `/*# sourceMappingURL=… */` / `/*# sourceURL=… */`
        // loud comment (it generates its own); the `# ` space is required, so
        // `/*#sourceMappingURL…*/`, `/*! … */`, and other names are kept.
        if (text.starts_with("# sourceMappingURL=") || text.starts_with("# sourceURL=")) {
            // The comment emits nothing, but the statement it occupied still
            // ends a top-level group (dart's serializer writes a blank line
            // before the following node — and, when the stripped comment leads
            // the document, a leading blank). Leave a group-end sentinel so the
            // next top-level group blank-separates; inside a block (or at-root
            // body) the comment vanishes with no separator, as dart does.
            if let t: Sink_Top = self {
                t._0.push(OutNode_GroupEnd {  });
            }
            return;
        }
        match (self) {
            let t: Sink_Top => {
                let out = t._0;
                push_group(out, [OutNode_Comment { _0: text, _1: lines }]);
            },
            let r: Sink_Rule => r.items.push(OutItem_Comment { _0: text, _1: lines }),
            let a: Sink_AtRoot => a.body.push(OutNode_Comment { _0: text, _1: lines }),
            _ => root.std.unreachable(),
        }
    }

    function push_item(self, item: OutItem) -> void throws never {
        match (self) {
            let r: Sink_Rule => r.items.push(item),
            let a: Sink_AtRoot => match (item) {
                let d: OutItem_Decl => {
                    a.body.push(
                        OutNode_AtDecl {
                            prop: d.prop,
                            value: d.value,
                            important: d.important,
                            custom: d.custom,
                            lines: d.lines,
                            value_span: d.value_span,
                        },
                    )
                },
                let c: OutItem_Comment => a.body.push(OutNode_Comment { _0: c._0, _1: c._1 }),
                let c: OutItem_ChildlessAtRule => {
                    a.body.push(OutNode_childless_at_rule(c.name, c.prelude, c.lines))
                },
                // A plain-CSS nested rule reaching an at-root sink becomes a
                // top-level rule carrying its items.
                let n: OutItem_NestedRule => {
                    a.body.push(
                        OutNode_Rule {
                            selectors: RuleSelectors_Raw { _0: n.selectors },
                            linebreaks: n.linebreaks,
                            items: n.items,
                            lines: n.lines,
                            extend_base: root.std.INT_MAX(),
                        },
                    )
                },
                // Likewise a plain-CSS nested at-rule becomes a top-level one,
                // its items wrapped as bare at-rule children.
                let n: OutItem_NestedAtRule => {
                    a.body.push(
                        OutNode_AtRule {
                            name: n.name,
                            prelude: n.prelude,
                            body: n.items.map((it: OutItem) -> OutNode {
                                match (it) {
                                    let d: OutItem_Decl => {
                                        OutNode_AtDecl {
                                            prop: d.prop,
                                            value: d.value,
                                            important: d.important,
                                            custom: d.custom,
                                            lines: d.lines,
                                            value_span: d.value_span,
                                        }
                                    },
                                    let c: OutItem_Comment => OutNode_Comment { _0: c._0, _1: c._1 },
                                    let r: OutItem_NestedRule => {
                                        OutNode_Rule {
                                            selectors: RuleSelectors_Raw { _0: r.selectors },
                                            linebreaks: r.linebreaks,
                                            items: r.items,
                                            lines: r.lines,
                                            extend_base: root.std.INT_MAX(),
                                        }
                                    },
                                    let c: OutItem_ChildlessAtRule => {
                                        OutNode_childless_at_rule(c.name, c.prelude, c.lines)
                                    },
                                    let na: OutItem_NestedAtRule => {
                                        OutNode_AtRule {
                                            name: na.name,
                                            prelude: na.prelude,
                                            body: [
                                                OutNode_plain_rule([], na.items, root.ast.SrcLines.default()),
                                            ],
                                            has_block: true,
                                            kind: na.kind,
                                            lines: na.lines,
                                        }
                                    },
                                    _ => root.std.unreachable(),
                                }
                            }),
                            has_block: true,
                            kind: n.kind,
                            lines: n.lines,
                        },
                    )
                },
                _ => root.std.unreachable(),
            },
            let _t: Sink_Top => {},
            _ => root.std.unreachable(),
        }
    }

    /// Flush the parent rule's accumulated declarations/loud-comments into a
    /// block node, in source order, before a nested rule or at-rule is emitted.
    /// dart-sass splits the parent block around each bubbled child so that a
    /// declaration (or loud comment) following a nested rule appears AFTER that
    /// rule in the output. No-op for non-`Rule` sinks (which never accumulate a
    /// block) and when there are no pending items.
    function flush_rule_block(self) -> bool throws never {
        if let r: Sink_Rule = self {
            let selectors = r.selectors;
            let linebreaks = r.linebreaks;
            let lines = r.lines;
            let items = r.items;
            let nested = r.nested;
            let at_depth = r.at_depth;
            let extend_base = r.extend_base;
            if (items.length() != 0) {
                // A rule whose every complex selector was a dropped bogus
                // combinator has no selectors left, so it emits no block.
                if (selectors.is_empty()) {
                    items.clear();
                } else {
                    // The rule's block precedes any hoist markers that
                    // accumulated while it was open (the bubbled rules leave
                    // the style rule entirely and follow it in the output);
                    // an `@at-root` graft INTO this body (target == depth) is
                    // a real sibling, so the block stays after it.
                    let insert_at = nested.find_index((n) -> {
                        is_escaping_marker(n, at_depth)
                    })
                        ?? nested.length();
                    // Both declaration runs target the same style-rule copy
                    // when only escaped batches landed between them (dart's
                    // entry copy has no following sibling inside this node).
                    if (insert_at > 0 && r.flushed == insert_at - 1) {
                        if let prev: OutNode_Rule = nested.at(insert_at - 1) {
                            // PORT: `prev.append(*items)` -> extend + clear.
                            root.std.extend(prev.items, items);
                            items.clear();
                            return true;
                        }
                        // (a non-Rule at that index can't happen: `flushed`
                        // only ever records a flushed block fragment)
                    }
                    let rule = OutNode_Rule {
                        selectors: RuleSelectors_Raw { _0: selectors.to_shared() },
                        linebreaks: root.std.clone_vec(linebreaks),
                        items: root.std.take_all(items),
                        lines: lines,
                        extend_base: extend_base,
                    };
                    nested.insert(rule, insert_at) catch (e) {
                        baml.errors.InvalidArgument => {
                            root.std.panic("insertion index out of bounds")
                        }
                    };
                    r.flushed = insert_at;
                    return true;
                }
            }
        }
        false
    }

    /// Emit a produced style rule's fully interleaved output (its own block
    /// fragments plus the rules that bubbled out of it, in source order).
    function emit_style_rule(self, output: OutNode[], allow_group_end: bool) -> void throws never {
        match (self) {
            let t: Sink_Top => {
                let out = t._0;
                // An `@at-root` chunk hoisted in-place leaves an INTERIOR
                // group-end marker before the resumed parent rule; materialize it
                // into the one blank line dart emits there. A TRAILING marker
                // (nothing resumes) is left untouched — it's the rule's own
                // isGroupEnd, consumed by the next group's `push_group`.
                let output = materialize_interior_group_ends(output);
                // dart-sass isGroupEnd is set only by visitStyleRule, and an
                // INVISIBLE rule (e.g. `@extend`-only, no declarations) never
                // becomes `previous` in _visitChildren — it must not leave a
                // group-end behind, or the next sibling gains a phantom blank
                // line (bootstrap: two @media from consecutive @each rounds).
                let produced = output.some((n) -> {
                    !(n is OutNode_Blank || n is OutNode_AtRootPackTight || n is OutNode_GroupEnd)
                });
                push_group(out, output);
                // A completed top-level style rule marks its LAST produced
                // node (which may be a bubbled at-rule) as a group end: the
                // next group gets a blank line even after an at-rule —
                // UNLESS the rule's own last child was an invisible empty
                // rule, which owns the group end in dart and never renders;
                // then the next group packs TIGHT (the pack-tight sentinel
                // also suppresses push_group's default blank-after-rule).
                if (produced && out.length() != 0) {
                    let marker: OutNode = if (allow_group_end) {
                        OutNode_GroupEnd {  }
                    } else {
                        OutNode_AtRootPackTight {  }
                    };
                    out.push(marker);
                }
            },
            let _r: Sink_Rule => {
                // Split the enclosing rule's own block around this nested rule.
                let _ = self.flush_rule_block();
                if let r: Sink_Rule = self {
                    root.std.extend(r.nested, output);
                }
            },
            let a: Sink_AtRoot => {
                // For a true `@at-root` body: a completed style rule at the
                // body's own level marks a group end (dart sets isGroupEnd
                // only when `_styleRule == null` — rules flattened out of a
                // wrapper rule arrive inside ONE batch and pack tight); an
                // invisible trailing child packs the next group tight.
                let produced = a.group_ends
                    && output.some((n) -> {
                        !(
                            n is OutNode_Blank
                                || n is OutNode_AtRootPackTight
                                || n is OutNode_GroupEnd
                        )
                    });
                root.std.extend(a.body, output);
                if (produced) {
                    let marker: OutNode = if (allow_group_end) {
                        OutNode_GroupEnd {  }
                    } else {
                        OutNode_AtRootPackTight {  }
                    };
                    a.body.push(marker);
                }
            },
            _ => root.std.unreachable(),
        }
    }

    /// Deposit a produced at-rule (or `@at-root` output). At the top level it
    /// forms its own group; inside a style rule it joins the rules that bubble
    /// out to the document root (splitting the parent's own block around it);
    /// inside another at-rule's body it nests.
    function push_at_rule(self, node: OutNode) -> void throws never {
        match (self) {
            let t: Sink_Top => {
                let out = t._0;
                push_group(out, [node]);
            },
            let _r: Sink_Rule => {
                // A hoist marker whose batch ESCAPES this body only matters to
                // an OUTER at-rule's segmenting: the batch leaves this style
                // rule entirely, so its own block is NOT split around it. An
                // `@at-root` graft INTO this body is a real sibling and splits
                // the block like any other bubbled child.
                // PORT: the Rust `_ => 0` arm is unreachable here (`self` is
                // already narrowed to `Sink_Rule`), and BAML rejects it.
                let depth = match (self) {
                    let r: Sink_Rule => r.at_depth,
                };
                if (!is_escaping_marker(node, depth)) {
                    let _ = self.flush_rule_block();
                }
                if let r: Sink_Rule = self {
                    r.nested.push(node);
                }
            },
            let a: Sink_AtRoot => a.body.push(node),
            _ => root.std.unreachable(),
        }
    }
}

class Sink_Top {
    _0: OutNode[],
    implements Sink {}
}

/// Root-hoisted buffer. `group_ends` is set only for a true `@at-root`
/// body deposit — a completed style rule then leaves a group-end
/// sentinel (dart marks isGroupEnd when `_styleRule == null`); generic
/// at-rule bodies (@media/@supports) keep their own separator logic.
/// The enclosing rule's resolved selector list, used to build a block
/// node when the accumulated `items` must be flushed (i.e. when a nested
/// rule or at-rule interrupts the parent's own declarations).
/// Per-complex source line-break flags (parallel to `selectors`).
/// The source rule's brace/end lines, stamped onto every flushed block
/// fragment (dart keeps the original rule's span on each copy).
/// The at-rule nesting depth of this rule's body (`at_rule_ctx.len()`
/// at construction): an `@at-root` hoist marker whose batch escapes
/// this body (target < depth) is transparent to block anchoring, while
/// one grafting INTO this body (target == depth) is a solid sibling.
/// Index in `nested` of the most recently flushed block fragment, so a
/// later fragment can JOIN it when only escaping hoist markers landed
/// in between (dart adds both declaration runs to the same style-rule
/// copy because the escaped batches aren't siblings inside this node).
/// The `@extend` registration count when this rule's selector was
/// established (dart `addSelector` timing), carried onto each flushed
/// [`OutNode::Rule`]. See [`OutNode::Rule::extend_base`].
class Sink_Rule {
    selectors: SinkSelectors,
    linebreaks: bool[],
    lines: root.ast.SrcLines,
    items: OutItem[],
    nested: OutNode[],
    at_depth: int,
    flushed: int?,
    extend_base: int,
    implements Sink {}
}

/// The body of a top-level at-rule (no enclosing selector): bare
/// declarations land here directly as [`OutNode::AtDecl`], interleaved
/// in source order with bubbled child rules and nested at-rules.
class Sink_AtRoot {
    body: OutNode[],
    group_ends: bool,
    implements Sink {}
}

/// Options visible to the evaluator (subset of the public `Options`).
class EvalOptions {
    style: root.OutputStyle,
    importer: root.importer.Importer?,
    /// Host-defined custom functions (dart-sass `functions`), matched by name.
    functions: root.host_fn.HostFn[],
    /// The entrypoint's source text, for rendering byte-exact diagnostic
    /// snippets. Empty when the embedder does not supply it (diagnostics then
    /// fall back to the legacy one-liner).
    source: string,
    /// The entrypoint's file path/URL as it should appear in diagnostics
    /// (e.g. `input.scss`).
    url: string,
    /// The directory diagnostic paths are relative to, or `None` to ask the
    /// operating system (see [`crate::Options::cwd`]).
    cwd: string?,
    /// The glyph set for snippet/gutter decoration (ASCII under `--no-unicode`).
    glyphs: root.diag.GlyphSet,
    /// Diagnostic handler (dart-sass `logger`). When set, `@warn`/`@debug`/
    /// deprecation warnings are delivered here instead of printed to stderr.
    warn: root.WarnHandler?,
    /// Deprecation ids to drop (dart-sass `silenceDeprecations`), applied
    /// beside `quiet_deps` so they never reach the per-id cap.
    silenced_deprecations: string[],
    /// dart-sass `quietDeps`: deprecations raised inside a file this set marks
    /// as a dependency are dropped before they are counted or delivered.
    quiet_deps: root.importer.DependencySet?,
    /// The entry was parsed as plain CSS (`Syntax::Css`): it is emitted as
    /// plain CSS — nesting preserved, `@import "theme"` passed through, no
    /// Sass evaluation — like a `.css` file reached through `@use`.
    plain_css: bool,
    /// Whether this compile produces a source map. Gates the variable
    /// definition-span bookkeeping (`var_spans` et al.), which only source-map
    /// emission reads: when false the span chain stays empty and every
    /// span lookup short-circuits to "unknown", so the plain [`crate::compile`]
    /// path pays nothing for it.
    source_map: bool,
}

class Evaluator {
    scopes: Scope[],
    /// Definition spans for the bindings in `scopes`, one frame per scope
    /// (dart `Environment._variableNodes`). Pushed/popped in lockstep. Purely
    /// additive: nothing here can change a CSS byte.
    var_spans: SpanScope[],
    /// Whether each scope in `scopes` is "semi-global" (dart-sass): a control
    /// flow scope (`@for`/`@each`/`@while`/`@if`) that lets a fresh assignment
    /// reach the global scope, but only when every enclosing scope up to the
    /// root is itself semi-global. Rule/mixin/function scopes are not.
    scope_semi_global: bool[],
    /// Popped scope tables, kept for the next block to use. A block's scope
    /// lives exactly as long as the block unless a closure captured the chain,
    /// so [`pop_scope`](Evaluator::pop_scope) usually holds the only reference
    /// to a table it is about to free — and entering the next block would
    /// immediately allocate another. Bounded by [`SCOPE_POOL_MAX`].
    scope_pool: Scope[],
    /// The same for the definition-span frames, which are pushed in lockstep
    /// with `scopes` when a source map is being built.
    span_pool: SpanScope[],
    /// Scratch buffer for serializing one declaration value. Serializing into
    /// a fresh `String` starts at the allocator's minimum block and regrows
    /// once or twice for a value as ordinary as `0 1px 2px rgba(0, 0, 0, .2)`;
    /// this buffer keeps whatever capacity the widest value so far needed, so
    /// the out item's own exactly-sized copy is the only allocation left. One
    /// buffer suffices because serializing a value never re-enters the
    /// evaluator; the values it does NOT serve are the ones that build an owned
    /// string anyway — see [`Evaluator::declared_css`].
    /// PORT: a `StrBuf` (it is passed to `Value::write_css` as `&mut String`).
    css_buf: root.std.StrBuf,
    options: EvalOptions,
    /// Import paths currently being loaded, deepest last. Re-entering one is a
    /// load cycle (dart-sass "This file is already being loaded."); a path that
    /// has finished loading may be imported again (`@import` re-evaluates).
    loading: string[],
    /// Per-compile `@import` cache (dart-sass ImportCache analogue): keyed by
    /// (url, importing dir), holding (resolved key, syntax, parsed sheet).
    import_cache: map<string, CachedImport>,
    /// The current file's interned diagnostic id for [`Self::stamp`], or 0
    /// when not yet interned. Every `current_url` assignment resets it.
    current_url_stamp: int,
    /// User function/mixin scope chains, parallel to `scopes` (dart's
    /// `Environment._functions`/`_mixins`): a definition always lands in the
    /// innermost frame, so a nested `@function`/`@mixin` shadows an outer one
    /// only within its block. A frame holds no table until it has something to
    /// put in it ([`FnFrame`]).
    functions: FnFrame[],
    mixins: FnFrame[],
    /// Stack of `@content` blocks, one per active `@include`.
    content_stack: (ContentBlock?)[],
    /// Whether we are *directly* executing a mixin body (dart-sass `_inMixin`).
    /// `true` is pushed while a mixin body runs; running a `@content` block or a
    /// function body pushes `false` (those execute in the caller's context), so
    /// `meta.content-exists()` errors there. Empty at the document root.
    in_mixin: bool[],
    /// The resolved query list of the enclosing `@media` context (empty at the
    /// document root). Used to merge nested `@media` queries.
    media_queries: ResolvedQuery[],
    /// The resolved selector list of the enclosing style rule, used to resolve
    /// `&` in value position. `None` at the document root (where `&` is `null`).
    /// Each element is one resolved complex selector (space-joined).
    ///
    /// Shared rather than owned: the same list is also the `parents` of every
    /// nested rule and the extender list of every `@extend` in the body, and a
    /// rule resolves its selectors once. Handing out an `Rc` keeps that one list
    /// instead of deep-copying it per reader.
    current_selector: string[]?,
    /// Source line-break flags parallel to `current_selector` (whether each
    /// resolved complex selector started on a fresh source line). A nested
    /// rule's complex inherits its parent's flag OR its own part's flag.
    current_linebreaks: bool[],
    /// Collected `@extend` directives, applied in a post-eval extension pass.
    extends_: PendingExtend[],
    /// The current nested-property-set name prefix (e.g. `font` then `font-x`).
    /// Empty at the document root and inside ordinary rules; a child declaration
    /// emitted while this is non-empty is namespaced as `<prefix>-<name>`.
    decl_prefix: string?,
    /// Whether we are evaluating the value of a `@supports` declaration. When
    /// set, `calc()` interiors are NOT simplified (dart-sass keeps
    /// `calc(1 + 2)` literal in `@supports (a: calc(1 + 2))`), matching
    /// dart-sass `_inSupportsDeclaration`.
    in_supports_declaration: bool,
    /// True while evaluating a plain-CSS (`.css`) module's statements: no
    /// function — user-defined or built-in — is invoked there (dart-sass
    /// `plainCss`); calls re-serialize verbatim. CSS calculations still
    /// simplify.
    in_plain_css: bool,
    /// True while the pending configuration is the *implicit* one built from
    /// an `@import`'s visible variables (dart `Configuration.implicit`): an
    /// already-loaded module is then reused silently instead of erroring with
    /// "can't be configured using with".
    config_is_implicit: bool,
    /// The canonical key of the module currently being evaluated (empty for
    /// the root stylesheet) — stamped onto each registered `@extend`.
    current_module: string,
    /// Module dependency edges: user key -> the canonical keys it loads
    /// (via `@use`/`@forward`/`meta.load-css`). An extension whose origin can
    /// reach a module along these edges may rewrite that module's CSS.
    module_deps: map<string, map<string, bool>>,
    /// The same load edges in *load order* (for `meta.load-css` subtree
    /// re-emission, which walks dependencies upstream-first).
    module_dep_order: map<string, string[]>,
    /// `meta.load-css` copy scopes: (copy key, base module key). An origin
    /// inside the base's subtree also sees the copy (its extensions apply to
    /// the clone), in addition to the caller-edge reachability.
    load_css_copies: root.std.Tuple2<string, string>[],
    /// Monotonic counter for unique load-css copy keys.
    copy_counter: int,
    /// Queue of merged nested `@media` nodes bubbling out of an enclosing
    /// media rule, taken in order at the [`OutNode::MediaHoist`] markers the
    /// inner rule leaves in the outer body.
    media_hoist: OutNode[][],
    /// Batches hoisted by `@at-root` queries, taken in order at the
    /// [`OutNode::AtRootHoist`] markers; each batch is already re-wrapped in the
    /// kept at-rule layers BELOW its graft target and travels outward to it.
    at_root_hoist: AtRootBatch[],
    /// The enclosing at-rule layers (outermost first), so `@at-root` queries
    /// can re-wrap their body in the layers the query keeps.
    at_rule_ctx: AtCtx[],
    /// Source-map position of the innermost enclosing style rule's selector
    /// (its `rule_lines`). A bubbled `@media`/`@at-root` wrapper re-uses this so
    /// the duplicated parent selector maps to the ORIGINAL rule's span (dart
    /// parity); `SrcLines::default()` when not inside a style rule. Used ONLY
    /// for source maps — never affects CSS bytes.
    cur_rule_lines: root.ast.SrcLines,
    /// The enclosing style rule's `extend_base` (how many `@extend`s were
    /// registered when it was created), inherited by the wrap that re-emits
    /// its selectors inside a nested at-rule — the @media copy of a rule is
    /// created "at the same time" as the rule for dart's addSelector timing.
    cur_rule_extend_base: int,
    /// Bogus-combinator selectors omitted from the CSS (`.a > + x`): they
    /// still satisfy `@extend` target matching like dart's extend graph.
    bogus_selectors: string[],
    /// Placeholder-rule selectors seen during eval (module key, selector).
    /// An empty placeholder rule is pruned from the output tree but still
    /// counts as an `@extend` target within the modules the extension sees.
    placeholder_rules: root.std.Tuple2<string, string>[],
    /// Set while module loads run inside a module-loading `@import`: dart
    /// clones the whole import subtree's CSS at the import site (the same
    /// `_combineCss(clone: true)` as meta.load-css). All loads in the chain
    /// share ONE copy scope key and ONE visited set (a diamond emits its
    /// shared upstream once per import, not once per use edge), and record no
    /// main-tree edge.
    import_clone: root.std.Tuple2<string, map<string, bool>>?,
    /// The directory of the file currently being evaluated, used to resolve
    /// relative `@use`/`@forward`/`@import` URLs against the containing file
    /// first (dart-sass resolution order).
    current_file_dir: string?,
    /// The canonical URL of the file currently being evaluated, passed to the
    /// importer as `CanonicalizeContext::containing_url`.
    ///
    /// INVARIANT: tracked in **lockstep** with [`Self::current_file_dir`] — every
    /// site that swaps `current_file_dir` must swap this too, or a relative
    /// `@use`/`@import`/`meta.load-css` resolves against the wrong file. The four
    /// sites: entry init (`Evaluator::new`), `eval_module`, the `@import` enter,
    /// and `enter_origin_file`. (The two are kept separate rather than derived
    /// because `current_file_dir` is also the `@import` cache key.)
    current_canonical: root.importer.CanonicalUrl?,
    /// The current directory diagnostics are spelled against, resolved at
    /// most once per compile. Only the frame-naming rule in `modules.rs`
    /// reads it, and only to build a display string, but `getcwd` is a real
    /// syscall -- ~10-19 us on macOS against ~0.5 us on Linux -- and it was
    /// being made once per module loaded. `None` means nobody knows one:
    /// either the call failed, or this is a target without `getcwd` and the
    /// host passed nothing.
    /// PORT: `OnceCell<Option<PathBuf>>` -> `Some<string?>?`: `null` is the
    /// uninitialized cell, `Some { value: null }` the resolved "nobody knows".
    cwd_cache: root.std.Some<string?>?,
    /// Whether evaluation is inside a `@keyframes` body: frame blocks are not
    /// style rules in dart-sass, so nested at-rules do not bubble out of them
    /// and frame selectors get keyframe normalization (`E` -> `e`).
    in_keyframes: bool,
    /// dart `_inUnknownAtRule`: inside the body of a generic/unknown at-rule
    /// (`@utility`, `@layer`, `@font-face`, vendor `@foo`, …). Bare
    /// declarations are legal there even without an enclosing style rule —
    /// including directly inside a nested `@media` (Tailwind v4's
    /// `@utility x { @media (…) { max-width: …; } }`).
    in_unknown_at_rule: bool,
    /// Whether the most recent CSS-NODE-CREATING statement in the current
    /// body was an EMPTY style rule (extend-only / no declarations). dart
    /// creates a CssStyleRule node even then; being invisible it still OWNS
    /// its group end, which the serializer never sees — so a rule whose LAST
    /// child was such a statement emits no blank-line separator
    /// (`.brand` stays tight after `.nav { %p {…} > .c { @extend %p; } }`).
    /// Statements that create no node (variables, @extend, loads, control
    /// flow shells) leave it untouched.
    last_child_invisible: bool,
    /// dart `_atRootExcludingStyleRule`: inside `@at-root` (before the first
    /// nested style rule) the implicit parent join is disabled — `&` still
    /// resolves against the enclosing rule, but a plain selector stays at the
    /// root instead of nesting under it.
    at_root_excluding_style_rule: bool,
    /// Global variables that were written by an `@import`ed `@forward` merge,
    /// with the source module each came from (by pointer). In dart-sass such
    /// a variable stays bound to its module: re-importing the SAME forwards
    /// must not clobber an intervening assignment (`@import "f"; $a: changed;
    /// @import "f"` keeps `changed`), while a user-defined global IS
    /// overwritten by the first merge — and a forward of the same name from a
    /// DIFFERENT module overrides the previous binding (sass/dart-sass#888).
    /// PORT: the pointer (`usize`, 0 = none) is the module's `_id` (`""` = none).
    forwarded_globals: map<string, string>,
    /// Built-in modules made available via `@use "sass:<mod>"`, keyed by the
    /// in-scope namespace (default = the part after `sass:`, or the `as ns`
    /// override). The value is the canonical built-in module name (e.g.
    /// `math`) — one of a closed set, so it is borrowed, not owned.
    used_modules: map<string, string>,
    /// Built-in modules brought into scope unprefixed via `@use "sass:<mod>"
    /// as *`. Their members resolve as bare calls/variables.
    star_modules: string[],
    /// User stylesheet modules brought into scope via `@use "<file>" [as ns]`,
    /// keyed by the in-scope namespace.
    used_user_modules: map<string, Module>,
    /// User modules brought into scope unprefixed via `@use "<file>" as *`.
    star_user_modules: Module[],
    /// All user modules loaded so far, keyed by the importer's canonical key so
    /// each file is evaluated once and shared between every `@use`/`@forward`.
    /// Shared so a module's own forwarded sub-modules see the same cache.
    module_cache: map<string, Module>,
    /// Members re-exported from the module currently being evaluated, collected
    /// from its `@forward` rules. Empty when not evaluating a module.
    forwarded: Forwarded,
    /// Configuration (`@use/@forward ... with`) supplied for the module
    /// currently being evaluated, consumed by its `!default` declarations.
    /// Maps variable name -> (value, is_default_override).
    pending_config: map<string, root.std.Tuple2<root.value.Value, bool>>,
    /// The opaque identity of the ORIGINAL explicit configuration the pending
    /// config derives from (0 = none/implicit). dart-sass allows re-loading
    /// an already-loaded module with a configuration that shares the same
    /// original (a `with (...)` distributed through several forwards).
    pending_config_id: int,
    /// Counter for fresh explicit-configuration identities.
    config_id_counter: int,
    /// Config keys actually consumed by a `!default` declaration in the module
    /// currently being evaluated (used to reject unused configuration).
    consumed_config: string[],
    /// The name of the member whose body is currently executing, as it appears
    /// in a diagnostic stack frame: `root stylesheet` at the entrypoint, or
    /// `<name>()` inside a user mixin/function. dart-sass `_member`.
    member: string,
    /// The diagnostic call stack: one entry per active user callable/import,
    /// recording the call site and the *caller's* member name. dart-sass
    /// `_stack`. Used to render byte-exact stack traces under errors/warnings.
    call_stack: DiagFrame[],
    /// The file path/URL the statements currently being evaluated came from
    /// (the entrypoint URL, or an imported/used partial's path).
    current_url: string,
    /// The source text of [`Self::current_url`], for rendering snippets that
    /// point into the currently-executing file.
    current_source: string,
    /// Per-id count of deprecation warnings already *printed* (capped at 5 each,
    /// dart-sass). Keyed by the deprecation `[id]`.
    deprecations_shown: map<string, int>,
    /// Total deprecation warnings *omitted* by the per-id cap, summed across
    /// ids; rendered into the aggregate footer at the end of the compile.
    deprecations_omitted: int,
    /// Per-location dedup: a `(id, url, line, col)` already warned about is not
    /// warned about again (dart-sass collapses identical repeated warnings).
    /// Keyed `(id, message, url, line, col)`. The MESSAGE is part of the
    /// identity because one span can carry two different warnings of the same
    /// id: `call(get-function("percentage"))` is `[global-builtin]` twice, once
    /// naming `meta.call` and once `math.percentage`, and dart prints both.
    deprecations_seen: map<string, bool>,
    /// Memo over deprecation PROBES: the material a call site would build a
    /// `Deprecation` from, so a repeat can skip the whole path. Sound only
    /// because the dedup insert at [`Self::emit_deprecation`] precedes the
    /// per-id cap: a repeat of an already-seen key is a TOTAL no-op there (it
    /// does not even increment `deprecations_omitted`), so skipping it early
    /// cannot change stderr. Keyed by a fingerprint; the stored material is
    /// compared with `==` on a hit, so a 64-bit collision only costs the slow
    /// path.
    ///
    /// Bounded in BOTH directions, because it retains what it was asked about:
    /// [`Self::DEP_MEMO_MAX`] caps how many entries there can be, and
    /// [`Self::probe_arg_memoizable`] caps what one entry can hold. No `Value`
    /// graph ever enters it.
    dep_memo: map<string, DepProbe>,
    /// Small interned ids for source files, stamped into [`SrcLines`] so the
    /// serializer's trailing-comment rule can require same-file adjacency and
    /// the source map can name the file. Keyed by the file's CANONICAL URL —
    /// the resolved path for the filesystem importer, the entry's `url` as
    /// given — not its display URL, so two partials that share a basename stay
    /// two sources (dart's `sources` are canonical URLs too).
    file_ids: map<string, int>,
    /// Source text per canonical URL, for the map's `sourcesContent`.
    file_texts: map<string, string>,
    /// Source-map URL OVERRIDES: a loaded file's canonical URL -> the URL an
    /// importer asked the source map to record for it (`ImporterResult
    /// .source_map_url`). Empty for the filesystem importer / entry file, so the
    /// generated source map is byte-identical unless a custom importer sets it.
    file_map_urls: map<string, string>,
    function new(options: EvalOptions) -> Evaluator {
        let url = options.url;
        let entry_canonical = root.importer.CanonicalUrl.new(options.url);
        let entry_dir = dirname_of(options.url) ?? "";
        let source: string = options.source;
        let file_texts: map<string, string> = {};
        let _ = file_texts.set(url, source);
        Evaluator {
            member: "root stylesheet",
            call_stack: [],
            current_url: url,
            current_source: source,
            deprecations_shown: {},
            deprecations_omitted: 0,
            deprecations_seen: {},
            dep_memo: {},
            file_ids: {},
            file_texts: file_texts,
            file_map_urls: {},
            scopes: [new_scope()],
            // Empty (not one empty frame) when spans aren't tracked: every
            // push/insert/lookup site is guarded, so an empty chain makes the
            // whole bookkeeping a no-op. See `EvalOptions::source_map`.
            var_spans: if (options.source_map) {
                [new_span_scope()]
            } else {
                []
            },
            // The global scope is treated as semi-global so a top-level control
            // flow scope (its child) becomes semi-global too.
            scope_semi_global: [true],
            scope_pool: [],
            span_pool: [],
            css_buf: root.std.StrBuf.new(),
            options: options,
            loading: [],
            import_cache: {},
            current_url_stamp: 0,
            functions: [null],
            mixins: [null],
            content_stack: [],
            in_mixin: [],
            media_queries: [],
            current_selector: null,
            current_linebreaks: [],
            extends_: [],
            decl_prefix: null,
            in_supports_declaration: false,
            in_plain_css: false,
            config_is_implicit: false,
            forwarded_globals: {},
            current_module: "",
            module_deps: {},
            module_dep_order: {},
            load_css_copies: [],
            copy_counter: 0,
            in_keyframes: false,
            in_unknown_at_rule: false,
            last_child_invisible: false,
            at_root_excluding_style_rule: false,
            import_clone: null,
            // The entry file's containing directory (possibly "" = the
            // CWD-relative root): relative imports resolve against it first,
            // like dart — NOT via an implicit load path.
            current_file_dir: entry_dir,
            // The entry file's canonical URL = its display URL; the FsImporter
            // derives the same search base from its dirname (a bare name like
            // `input.scss` -> "" = CWD, matching `entry_dir`).
            current_canonical: entry_canonical,
            cwd_cache: null,
            media_hoist: [],
            at_root_hoist: [],
            at_rule_ctx: [],
            cur_rule_lines: root.ast.SrcLines.default(),
            cur_rule_extend_base: root.std.INT_MAX(),
            bogus_selectors: [],
            placeholder_rules: [],
            used_modules: {},
            star_modules: [],
            used_user_modules: {},
            star_user_modules: [],
            module_cache: {},
            forwarded: Forwarded.default(),
            pending_config: {},
            pending_config_id: 0,
            config_id_counter: 0,
            consumed_config: [],
        }
    }

    /// Intern the current file's diagnostics URL as a small id for SrcLines.
    /// Parser-produced lines (`file == 0`) become "this file"; a default
    /// (all-zero) value stays disabled.
    function stamp(self, lines: root.ast.SrcLines) -> root.ast.SrcLines {
        if (lines == root.ast.SrcLines.default()) {
            return lines;
        }
        // PORT: `mut lines` is a by-value copy of a Copy struct; copy before mutating.
        let lines = root.ast.SrcLines { ...lines };
        lines.file = self.intern_current_file();
        lines
    }

    /// Source-map-only position for a construct that takes no part in the
    /// trailing-comment rule: `file`/`start`/`end` stay 0 and only the map
    /// override fields are set. A passed-through plain-CSS `@import` maps to
    /// its URL token (dart `visitCssImport` spans `node.url`); a nested
    /// plain-CSS rule maps to its selector's first character.
    function map_only_lines(self, pos: root.scanner.Pos) -> root.ast.SrcLines {
        root.ast.SrcLines {
            ...root.ast.SrcLines.default(),
            map_file: self.intern_current_file(),
            map_line: pos.line,
            start_col: root.std.saturating_sub_u(pos.col, 1),
        }
    }

    /// The interned diagnostic/source-map file id of the file being evaluated,
    /// assigning one on first use. Interned once per file entry (every
    /// `current_url` assignment resets `current_url_stamp`), so the steady-state
    /// cost is a `u32` check.
    function intern_current_file(self) -> int {
        if (self.current_url_stamp != 0) {
            return self.current_url_stamp;
        }
        let next = self.file_ids.length() + 1;
        let key = self.current_path();
        let id = self.file_ids.get_or_insert(key, next);
        self.current_url_stamp = id;
        id
    }

    /// Emit the `[import]` deprecation for every Sass `@import` rule in a
    /// just-parsed stylesheet, in source order — dart-sass warns while PARSING
    /// a file, so a file's import deprecations all precede anything its body
    /// prints, and a file parsed once (the import cache) warns once however
    /// often it is imported. Plain-CSS imports (`.css`, `url(...)`, media
    /// queries) are not deprecated. Called with the file's context current
    /// (its url, source, and loader frames), before its statements run.
    function warn_import_rules(self, stmts: root.ast.Stmt[]) -> void {
        if (!self.diag_enabled()) {
            return;
        }
        for (let d in root.ast_writer.collect_parse_time_deprecations(stmts)) {
            // PORT: `let (dep, pos, length) = match &d { … }` -> a Tuple3.
            let t = match (d) {
                let i: root.ast_writer.ParseTimeDeprecation_Import => {
                    root.std.Tuple3 {
                        _0: root.deprecation.Deprecation.import(),
                        _1: i.pos,
                        _2: i.length,
                    }
                },
                let l: root.ast_writer.ParseTimeDeprecation_LegacyIf => {
                    root.std.Tuple3 {
                        _0: root.deprecation.Deprecation.if_function(l.suggestion),
                        _1: l.pos,
                        _2: l.length,
                    }
                },
                _ => root.std.unreachable(),
            };
            let dep = t._0;
            let pos = t._1;
            let length = t._2;
            self.emit_deprecation(dep, pos, length);
        }
    }

    function eval_sheet(self, sheet: root.ast.Stylesheet, out: OutNode[]) -> void {
        let plain_css = self.options.plain_css;
        if (!plain_css) {
            self.warn_import_rules(sheet.stmts);
        }
        {
            let top: Sink = Sink_Top { _0: out };
            let sink = root.std.Cell.new(top);
            // A plain-CSS entry (`.css`) is emitted as plain CSS, like a `.css`
            // module: its `@import "theme";` is a CSS import to pass through,
            // not a Sass file to load (dart-sass evaluates it the same way).
            // PORT: `let r = …; if let Err(e) = r { … }` -> the Err arm is a catch
            // around each branch (`r` itself is `()`).
            let failed: root.error.Error? = null;
            if (plain_css) {
                self.exec_css(sheet.stmts, [], sink) catch (e) {
                    let err: root.error.Error => {
                        failed = err;
                    }
                };
            } else {
                self.exec(sheet.stmts, [], sink) catch (e) {
                    let err: root.error.Error => {
                        failed = err;
                    }
                };
            }
            // At the outermost boundary, finalize any error into a rendered
            // diagnostic block (header + snippet + frames) if we have a span.
            if (failed != null) {
                let e = self.finalize_error(failed);
                self.emit_deprecation_footer();
                throw e;
            }
        };
        self.apply_extends(out);
        hoist_css_imports(out);
        self.emit_deprecation_footer();
    }

    /// The source-map `sources` table for the file ids in `order` — the ids the
    /// mappings reference, in order of first appearance (`Mappings::source_ids`).
    /// Only files that produced a mapping appear; a stylesheet with no output
    /// has an empty `sources`, as in dart-sass. Each entry is the file's
    /// canonical URL (an importer's `source_map_url` override wins). When
    /// `include_sources` is set, the parallel `sourcesContent` is built from
    /// the recorded file texts.
    function source_table(
        self,
        order: int[],
        include_sources: bool,
    ) -> root.std.Tuple2<string[], string[]?> {
        // Invert the id table once (ids are dense, assigned 1,2,3,…), then
        // index it per source.
        let key_of_id: string[] = baml.Array.filled(self.file_ids.length() + 1, "");
        for (let key in self.file_ids.keys()) {
            let id = self.file_ids[key];
            if (id >= 0 && id < key_of_id.length()) {
                key_of_id[id] = key;
            }
        }
        let keys: string[] = order.map((id) -> {
            key_of_id.at(id) ?? ""
        });
        let sources: string[] = keys.map((key) -> {
            self.file_map_urls.get(key) ?? key
        });
        let content: string[]? = if (include_sources) {
            keys.map((key) -> {
                self.file_texts.get(key) ?? ""
            })
        } else {
            null
        };
        root.std.Tuple2 { _0: sources, _1: content }
    }

    // ---- diagnostic rendering -------------------------------------------
    /// Whether the entrypoint supplied source text (so snippets can render).
    function diag_enabled(self) -> bool {
        self.options.source != ""
    }

    /// Build the diagnostic stack-frame list (innermost first) for a primary
    /// span located at `pos` in `self.current_url`, executed by `self.member`.
    /// This is `[(current file, pos, member)]` followed by the recorded call
    /// stack, outermost last — exactly dart-sass's `_stackTrace`.
    function frames_for(self, pos: root.scanner.Pos) -> DiagFrame[] {
        let frames: DiagFrame[] = [];
        frames.push(
            DiagFrame {
                url: self.current_url,
                pos: pos,
                member: self.member,
                length: 0,
                content: false,
                source: self.current_source,
            },
        );
        root.std.extend(
            frames,
            self.call_stack.reverse().map((f) -> {
                DiagFrame { ...f }
            }),
        );
        frames
    }

    /// Render the stack-frame list into the column-aligned block dart-sass
    /// appends under a snippet/warning. `indent` is 2 (errors) or 4
    /// (warnings/deprecations).
    function render_frame_block(self, frames: DiagFrame[], indent: int) -> string {
        // Column-align: pad each `<url> <line>:<col>` field to the longest.
        // The name goes through the frame-naming rule HERE, at the one place
        // a frame becomes text, rather than at each of the places a frame is
        // built: the entry's is whatever the host passed as `Options::url`,
        // which is a path from the binary and a `file://` URL from the JS
        // API, and both have to read as the path dart prints.
        let fields: string[] = frames.map((f) -> {
            `${self.frame_name(f.url)} ${f.pos.line}:${f.pos.col}`
        });
        // PORT: `String::len` is a byte count; the padding stays byte-based.
        let width = 0;
        for (let field in fields) {
            width = root.std.imax(width, field.byte_length());
        }
        let pad: string = " ".repeat(indent);
        let out = root.std.StrBuf.new();
        let i = 0;
        while (i < fields.length() && i < frames.length()) {
            let field = fields[i];
            let frame = frames[i];
            if (i > 0) {
                out.push("\n");
            }
            out.push_str(pad);
            out.push_str(field);
            for (let _ in baml.iter.Range.new(0, root.std.saturating_sub_u(width, field.byte_length()))) {
                out.push(" ");
            }
            out.push_str("  ");
            out.push_str(frame.member);
            i += 1;
        }
        out.as_str()
    }

    /// Convert an `Error` into a fully-rendered diagnostic block (header +
    /// snippet + 2-space frame trace), if diagnostics are enabled and the error
    /// carries a position. Idempotent: an already-rendered error is returned
    /// unchanged.
    function finalize_error(self, e: root.error.Error) -> root.error.Error {
        if (e.rendered != null || !self.diag_enabled() || !e.has_position()) {
            return e;
        }
        // PORT: `mut e: Error` is taken by value; mutate a copy so no other
        // holder of the thrown error observes the rewrite.
        let e = root.error.Error { ...e };
        // An empty span sitting in the file's trailing whitespace belongs at the
        // end of the last line with content, where dart reports it.
        let trimmed = root.diag.trim_empty_span_to_content(
            self.current_source,
            root.diag.Span { line: e.line, col: e.col, length: e.length },
        );
        e.line = trimmed.line;
        e.col = trimmed.col;
        let frames = self.frames_for(root.scanner.Pos { line: e.line, col: e.col });
        e.rendered = self.render_error_with_frames(e, frames);
        e
    }

    /// Build the "expected selector." error for a `@` in a resolved selector:
    /// when the offending column falls inside an interpolation's output the
    /// error renders dart's dual-span "error in interpolated output" block;
    /// when it maps to literal selector text the source column is recovered
    /// by shifting across the interpolations before it.
    function interp_selector_error(
        self,
        rule: root.ast.Rule,
        sel_str: string,
        interp_bounds: root.eval.expr.InterpBounds,
        at_idx: int,
    ) -> root.error.Error {
        // PORT: `const MSG: &str` inside the fn -> a local.
        let MSG = "expected selector.";
        let spans = rule.selector_interp_spans;
        let single_line = !sel_str.includes("\n");
        // Inside an interpolation's output -> dual-span rendering, positioned
        // at the interpolation expression's start.
        let interp_bounds = interp_bounds.as_slice();
        if (spans.length() == interp_bounds.length()) {
            let k = 0;
            for (let b in interp_bounds) {
                let start = b._0;
                let len = b._1;
                if (at_idx >= start && at_idx < start + len) {
                    let line = spans[k]._0;
                    let col_start = spans[k]._1;
                    let col_end = spans[k]._2;
                    let pos = root.scanner.Pos { line: line, col: col_start };
                    let e = root.error.Error.at(MSG, pos);
                    if (self.diag_enabled()) {
                        let source = self.current_source;
                        let frames = self.frames_for(pos);
                        let rendered = `Error: ${MSG}\n`;
                        rendered
                            = rendered
                                + root.diag.render_interp_error_snippet(
                                    source,
                                    line,
                                    col_start,
                                    col_end,
                                    sel_str,
                                    at_idx + 1,
                                    // This snippet prints the file in its own header,
                                    // so it is a second place a frame becomes text and
                                    // needs the same rule. Left out, one message
                                    // contradicted itself: a `file://` URL in the
                                    // header above the path in the trace below.
                                    self.frame_name(frames[0].url),
                                    self.options.glyphs,
                                );
                        rendered = rendered + "\n";
                        rendered = rendered + self.render_frame_block(frames, 2);
                        e.rendered = rendered;
                    }
                    return e;
                }
                k += 1;
            }
        }
        // Literal text: recover the source column by shifting across the
        // interpolations that precede the offending index.
        if (
            single_line
                && spans.length() == interp_bounds.length()
                && spans.every((s) -> {
                    s._0 == rule.selector_pos.line
                })
        ) {
            let shift = 0;
            let k = 0;
            for (let b in interp_bounds) {
                let start = b._0;
                let len = b._1;
                if (at_idx >= start + len) {
                    let col_start = spans[k]._1;
                    let col_end = spans[k]._2;
                    // The source text `#{ ... }` spans from 2 before the
                    // expression start through the closing brace.
                    let src_total = col_end + 1 - (col_start - 2);
                    shift += src_total - len;
                }
                k += 1;
            }
            let col = root.std.imax(rule.selector_pos.col + at_idx + shift, 1);
            return root.error.Error.at(MSG, root.scanner.Pos { line: rule.selector_pos.line, col: col });
        }
        root.error.Error.at(MSG, rule.selector_pos)
    }

    /// How a frame names its file: a path relative to the working directory,
    /// whether the host handed over a path or a `file://` URL. Anything that
    /// does not name a file — a `data:` URL, a custom importer's key — keeps
    /// the display string it already has.
    function frame_name(self, url: string) -> string {
        self.pretty_name(url) ?? url
    }

    /// Render `Error: <msg>` + the snippet pointing at the innermost frame +
    /// the 2-space-indented frame trace.
    function render_error_with_frames(self, e: root.error.Error, frames: DiagFrame[]) -> string {
        self.render_error_at(e, frames[0], frames)
    }

    /// Like [`Self::render_error_with_frames`], with the snippet drawn at
    /// `primary` rather than the innermost frame (an error in a content block
    /// points at the `@include` that supplied it, one frame out).
    function render_error_at(
        self,
        e: root.error.Error,
        primary: DiagFrame,
        frames: DiagFrame[],
    ) -> string {
        // The frame's own text, not a display-url lookup: two custom-importer
        // files may both display as `foo`.
        let source = primary.source;
        // Prefer the primary frame's own span length (set for `@error`'s call
        // site); otherwise the error's recorded length.
        let length = if (primary.length > 0) {
            primary.length
        } else {
            e.length
        };
        let span = root.diag.Span { line: primary.pos.line, col: primary.pos.col, length: length };
        let out = `Error: ${e.message}\n`;
        out = out + root.diag.render_snippet(source, span, [], self.options.glyphs);
        out = out + "\n";
        out = out + self.render_frame_block(frames, 2);
        out
    }

    /// dart's `quietDeps`: the second of the two side-effect-free rejections at
    /// the top of [`Self::emit_deprecation`], hoisted verbatim so a caller can
    /// skip building anything at all. Must stay byte-for-byte that check, and
    /// side-effect-free.
    ///
    /// The FIRST of the two, `diag_enabled`, is a field test and belongs at the
    /// top of a caller's gates. This one does not: with `quiet_deps` set it
    /// pauses the arena and takes a mutex (see
    /// [`crate::DependencySet::is_dependency`]), so it goes last among the
    /// cheap gates — after the name lookups that reject nearly every call — and
    /// a caller that asks it on every function call has made a compile with
    /// `--quiet-deps` measurably slower than one without.
    ///
    /// It must still be asked ABOVE [`Self::dep_memo`], not below it. `quietDeps`
    /// keys on the CANONICAL path, and the memo's key carries only the display
    /// URL, which two canonical files may share: a probe quieted in a dependency
    /// could otherwise answer for the same span in a file that is not one, and
    /// drop its warning.
    function deprecation_quieted(self) -> bool {
        let deps = self.options.quiet_deps;
        if (deps != null) {
            deps.is_dependency(self.current_path())
        } else {
            false
        }
    }

    /// Ceiling on [`Self::dep_memo`]. A sheet can probe one span with
    /// unboundedly many distinct VALUES, and such probes do not all leave a
    /// matching entry in `deprecations_seen` to bound them against: `@each $c
    /// in <n colours> { whiteness($c) }` records one probe per colour and emits
    /// nothing, because the bare spelling is rejected *below* the memo. Past
    /// the ceiling the memo simply stops learning — every further probe takes
    /// the same path it took before this memo existed, which is slower and
    /// byte-identical. The largest sheet in `bench/corpus` peaks at 70 entries
    /// (measured 2026-09-16), so this is ~58x observed usage.
    ///
    /// The count is only half a bound; [`Self::probe_arg_memoizable`] is the
    /// other half, and without it this number would mean nothing. With both, a
    /// full memo costs about 645 bytes an entry — measured 2026-09-16 on a
    /// generated sheet with 4000 distinct probe sites, +2.46 MB of peak RSS
    /// under the CLI's bump arena, which never reuses a freed block — so ~2.6
    /// MB at the ceiling, against a ~25 MB peak for the largest bench sheet.
    function DEP_MEMO_MAX() -> int {
        4096
    }

    /// Whether this exact deprecation probe has already run to completion at
    /// this exact place, making a second run a no-op (see [`Self::dep_memo`]).
    /// A miss records the material and returns `false`; a fingerprint collision
    /// whose stored material differs also returns `false`, so the exact path
    /// still runs.
    ///
    /// The `==` verify is UNCONDITIONAL, not a `debug_assert`: a hash collision
    /// would otherwise drop a warning, and a dropped warning is a parity break
    /// that no release build should be able to reach. The cost of being wrong
    /// is therefore only speed — a colliding probe takes the slow path, and is
    /// not re-memoised either, so it keeps taking it. The behaviour this
    /// protects is locked from the outside as well: one span reached with two
    /// different colours must warn twice, with a different suggestion each time
    /// (`tests/diagnostics.rs`, `a_legacy_color_function_suggests_its_replacement`).
    function probe_already_done(
        self,
        probe: DepProbePath,
        name: string,
        module: string?,
        pos: root.scanner.Pos,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
    ) -> bool {
        // A shape this memo must not retain is not memoised at all: no entry,
        // no fingerprint, straight down the path it took before the memo
        // existed. See [`Self::probe_arg_memoizable`].
        if (
            !pos_args.every((v) -> {
                Evaluator.probe_arg_memoizable(v)
            })
                || !named.every((nv) -> {
                    Evaluator.probe_arg_memoizable(nv._1)
                })
        ) {
            return false;
        }
        let h = root.fxhash.FxHasher.default();
        // The URL's CONTENTS, not merely its length. A key whose stored material
        // turns out to differ is answered `false` and NOT overwritten, so two
        // files whose display URLs are the same length — `src/_a.scss` and
        // `src/_b.scss` — would otherwise fight over one key at the same span,
        // and every repeat in whichever lost would pay the slow path for the
        // rest of the compile.
        h.write(self.current_url.to_utf8());
        h.write_u8(0xff);
        h.write(name.to_utf8());
        if (module != null) {
            h.write_u8(1);
            h.write(module.to_utf8());
        } else {
            h.write_u8(0);
        }
        h.write_u8(0xfe);
        for (let v in pos_args) {
            Evaluator.fingerprint_value(h, v);
        }
        h.write_u8(0xfd);
        for (let nv in named) {
            h.write(nv._0.to_utf8());
            Evaluator.fingerprint_value(h, nv._1);
        }
        // PORT: `probe as u32` — the C-like enum's discriminant, spelled out.
        let probe_u32 = match (probe) {
            DepProbePath.Call => 0,
            DepProbePath.ColorFunction => 1,
            DepProbePath.ColorModuleCompat => 2,
        };
        // key: the Rust `(u32, u32, u32, u64)` tuple joined with "\t".
        let key = `${probe_u32}\t${pos.line}\t${pos.col}\t${h.finish()}`;
        let prev = self.dep_memo.get(key);
        if (prev != null) {
            return prev.url == self.current_url
                && prev.name == name
                && prev.module == module
                && prev.pos_args == pos_args
                && prev.named == named;
        }
        if (self.dep_memo.length() < Evaluator.DEP_MEMO_MAX()) {
            let _ = self.dep_memo.set(
                key,
                DepProbe {
                    url: self.current_url,
                    name: name,
                    module: module,
                    pos_args: root.std.clone_vec(pos_args),
                    named: root.std.clone_vec(named),
                },
            );
        }
        false
    }

    /// Whether an argument of this shape may enter [`Self::dep_memo`] at all.
    ///
    /// The memo RETAINS its arguments, because that is what makes the `==`
    /// verify possible — so an entry count is only a bound if one entry is
    /// bounded too. `Calc`, `Slash`, `Function` and `Mixin` clone their whole
    /// tree, a `List` clones the keyword map of an argument list, and a `Number`
    /// clones its unit lists when they are complex. One large value reached from
    /// many call sites would then be retained once per site: measured
    /// 2026-09-16, a sheet with 4000 `saturate($c)` sites where `$c` is a
    /// 4000-term `calc()` cost the memo **1.19 GB** on top of the 1.80 GB that
    /// sheet already costs without it. `Str` and `Map` clone an `Rc` and so
    /// amplify nothing, but they are refused with the rest: admitting them buys
    /// no speed, and the rule is easier to keep true when it is "only what the
    /// suggestion tables read".
    ///
    /// Which is the reason refusing costs nothing. Every probe reaches here only
    /// after the call itself SUCCEEDED, and
    /// [`crate::builtins::color_function_suggestions`] reads exactly a `Color`
    /// and a `Number`: a channel getter (`red`, `whiteness`, …) has no plain-CSS
    /// overload, so a non-`Color` argument fails the call before this point, and
    /// a legacy adjuster (`saturate($c)`) that does pass through as CSS yields
    /// no suggestion. A refused probe is therefore one that had no warning to
    /// skip. The `[global-builtin]` probes, which are the bulk of the win, pass
    /// no arguments at all and are unaffected.
    ///
    /// The match is exhaustive ON PURPOSE: a new [`Value`] variant must not
    /// default into a memo that retains it, so adding one has to fail the build
    /// here.
    function probe_arg_memoizable(v: root.value.Value) -> bool {
        // PORT: the Rust match is exhaustive over `Value`; BAML's interface match
        // needs a `_` arm, which answers `false` like the refused variants.
        match (v) {
            // A simple unit is a shared `Rc<str>`, cloned by refcount.
            let n: root.value.Value_Number => !n._0.has_complex_units(),
            let _c: root.value.Value_Color => true,
            root.value.Value_Str {}
                | root.value.Value_List {}
                | root.value.Value_Map {}
                | root.value.Value_Bool {}
                | root.value.Value_Null {}
                | root.value.Value_Slash {}
                | root.value.Value_Calc {}
                | root.value.Value_Function {}
                | root.value.Value_Mixin {} =>
            {
                false
            },
            _ => false,
        }
    }

    /// Fold a value into a probe fingerprint. Deliberately COARSE for the
    /// composite variants: the `==` verify in [`Self::probe_already_done`] is
    /// what makes the memo exact, and a coarse fingerprint only ever costs a
    /// trip down the slow path. Numbers are hashed by `to_bits()` (not `==` on
    /// the float) WITH their unit, because `red(1px)`, `red(1)` and
    /// `red(1.0000000000000002)` render three different `Recommendation:` lines.
    ///
    /// Only `Number` and `Color` can reach it, since
    /// [`Self::probe_arg_memoizable`] refuses the rest before any hashing. The
    /// other arms stay because coarse-but-verified is the safe default: widening
    /// that gate would cost hash quality here, never correctness.
    function fingerprint_value(h: root.fxhash.FxHasher, v: root.value.Value) -> void {
        // PORT: `std::mem::discriminant(v).hash(h)` — the variant's index in
        // Rust's declaration order, hashed as a `usize`.
        let discriminant = match (v) {
            let _x: root.value.Value_Number => 0,
            let _x: root.value.Value_Color => 1,
            let _x: root.value.Value_Str => 2,
            let _x: root.value.Value_List => 3,
            let _x: root.value.Value_Map => 4,
            let _x: root.value.Value_Bool => 5,
            let _x: root.value.Value_Null => 6,
            let _x: root.value.Value_Slash => 7,
            let _x: root.value.Value_Calc => 8,
            let _x: root.value.Value_Function => 9,
            let _x: root.value.Value_Mixin => 10,
            _ => 11,
        };
        h.write_usize(discriminant);
        match (v) {
            let vn: root.value.Value_Number => {
                let n = vn._0;
                h.write_u64(root.std.f64_to_bits(n.value));
                h.write(n.unit().to_utf8());
            },
            let vc: root.value.Value_Color => {
                let c = vc._0;
                h.write_u64(root.std.f64_to_bits(c.r));
                h.write_u64(root.std.f64_to_bits(c.g));
                h.write_u64(root.std.f64_to_bits(c.b));
                h.write_u64(root.std.f64_to_bits(c.a));
                let modern = c.modern;
                if (modern == null) {
                    h.write_u8(0);
                } else {
                    let m = modern;
                    h.write_u8(1);
                    // PORT: `std::mem::discriminant(&m.space).hash(h)` — the
                    // C-like variant's name stands in for its discriminant.
                    h.write(m.space.to_string().to_utf8());
                    for (let ch in m.channels.concat([m.alpha])) {
                        if (ch != null) {
                            h.write_u64(root.std.f64_to_bits(ch));
                        } else {
                            h.write_u8(0);
                        }
                    }
                }
            },
            let vs: root.value.Value_Str => {
                let s = vs._0;
                h.write(s.text.to_utf8());
                h.write_u8(
                    if (s.quoted) {
                        1
                    } else {
                        0
                    },
                );
            },
            let vb: root.value.Value_Bool => {
                h.write_u8(
                    if (vb._0) {
                        1
                    } else {
                        0
                    },
                )
            },
            root.value.Value_Null {} => {},
            _ => {},
        }
    }

    /// Emit a deprecation warning at `pos` (caret length `len`): the header
    /// block + a snippet pointing at the deprecated construct + a 4-space stack
    /// trace + a trailing blank line. Honours dart-sass's per-location dedup and
    /// per-id cap of 5 (further occurrences are counted into the aggregate
    /// footer rendered by [`Self::emit_deprecation_footer`]). No-op when
    /// diagnostics are disabled.
    /// Emit whatever deprecations a call to `name` carries. `module` is the
    /// namespace it was written with, if any: a GLOBAL built-in with a `sass:*`
    /// equivalent is deprecated for being global, while `feature-exists` is
    /// deprecated whichever way it is spelled.
    function emit_call_deprecations(
        self,
        name: string,
        module: string?,
        pos: root.scanner.Pos,
        len: int,
    ) -> void {
        // Both registries are keyed by the canonical spelling: `_` and `-` are
        // one character in a Sass identifier, and dart deprecates `map_get(…)`
        // exactly as it deprecates `map-get(…)`.
        let canonical = if (name.includes("_")) {
            name.replace_all("_", "-")
        } else {
            name
        };
        let name = canonical;
        // Cheapest gate first: this runs on EVERY call, and all but a handful of
        // them deprecate nothing. `global_builtin_replacement` is still asked
        // about the already-canonicalised name, exactly as before (it
        // canonicalises internally too), and the emission ORDER below is
        // unchanged: global-builtin, then feature-exists.
        if (!self.diag_enabled()) {
            return;
        }
        let replacement: string? = if (module == null) {
            root.builtins.global_builtin_replacement(name)
        } else {
            null
        };
        let feature_exists = name == "feature-exists" && (module == null || module == "meta");
        if (replacement == null && !feature_exists) {
            return;
        }
        // Only now the gate that can take a lock: a name nothing deprecates has
        // already gone home, so `--quiet-deps` costs a mutex per WARNING, as it
        // did before this hoist, not one per call.
        if (self.deprecation_quieted()) {
            return;
        }
        if (self.probe_already_done(DepProbePath.Call, name, module, pos, [], [])) {
            return;
        }
        if (replacement != null) {
            let dep = root.deprecation.Deprecation.global_builtin(replacement);
            self.emit_deprecation(dep, pos, len);
        }
        if (feature_exists) {
            self.emit_deprecation(root.deprecation.Deprecation.feature_exists(), pos, len);
        }
    }

    /// Emit the `[color-functions]` deprecation for a call that has just
    /// SUCCEEDED. dart raises it from inside the function, after its arguments
    /// are validated and from their VALUES, so it belongs after the dispatch:
    /// `lighten(3, 10%)` errors and warns about nothing, and one `lighten($c,
    /// 10%)` in a mixin included with two colours warns twice, with a different
    /// suggestion each time.
    function emit_color_function_deprecation(
        self,
        name: string,
        module: string?,
        pos: root.scanner.Pos,
        len: int,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
    ) -> void {
        // Only `sass:color` has these members; every other module's call is
        // someone else's business.
        if (module != null && module != "color") {
            return;
        }
        // Cheap gates before any colour maths, cheapest first: nothing
        // downstream of here has a side effect, so a field test and two name
        // lookups can run ahead of it, and a probe already made at this span
        // with these VALUES is a no-op (see `dep_memo`). `deprecation_quieted`
        // sits after the name gate because it can take a lock, and above the
        // memo because it reads the canonical path the memo's key omits.
        if (!self.diag_enabled()) {
            return;
        }
        // `[color-module-compat]` shares this entry point because it shares the
        // precondition — a `sass:color` call that SUCCEEDED, judged by its
        // argument values — and because every dispatch site that can reach a
        // module member already calls here. The two ids never both fire: their
        // name sets are disjoint (`grayscale`/`invert`/`opacity`/`alpha` against
        // the channel getters and legacy adjusters).
        if (module != null) {
            self.emit_color_module_compat(name, module, pos, len, pos_args, named);
        }
        if (!root.builtins.color_function_deprecates(name)) {
            return;
        }
        if (self.deprecation_quieted()) {
            return;
        }
        if (self.probe_already_done(DepProbePath.ColorFunction, name, module, pos, pos_args, named)) {
            return;
        }
        // And a bare name that is no global built-in dispatched as a plain CSS
        // function, not as the member it shares a name with: `whiteness` and
        // `blackness` live ONLY on `sass:color`, so `whiteness(#abc)` is
        // nobody's call and deprecates nothing.
        if (module == null && !root.builtins.is_builtin(name)) {
            return;
        }
        let suggestions = root.builtins.color_function_suggestions(name, pos_args, named);
        if (suggestions == null) {
            return;
        }
        // dart names the function the way the call REACHED it: `color.red()`
        // through the module (under any namespace, star or forward), `red()`
        // as the global.
        let qualified = if (module != null) {
            `color.${name}`
        } else {
            name
        };
        let dep = root.deprecation.Deprecation.color_functions(qualified, suggestions);
        self.emit_deprecation(dep, pos, len);
    }

    /// Emit `[color-module-compat]` for a `sass:color` MEMBER call that has just
    /// succeeded by taking a plain-CSS filter path: `color.grayscale(1)` is
    /// `filter: grayscale(1)` written the long way, and dart is removing that
    /// spelling from the module. The global `grayscale(1)` is not deprecated at
    /// all — there the CSS filter is the whole meaning of the call (#122) — so
    /// the caller passes the module it was reached through, and `@use
    /// "sass:color" as *` counts: the member shadows the global, so the warning
    /// follows the member, not the syntax.
    ///
    /// Which calls took that path is not re-decided here: `module_filter_arg`
    /// and `ms_filter_args` are the dispatcher's own predicates. Keying on the
    /// RESULT would have been wrong in a way that is easy to miss —
    /// `color.ie-hex-str()` also returns an unquoted string and deprecates
    /// nothing.
    function emit_color_module_compat(
        self,
        name: string,
        module: string,
        pos: root.scanner.Pos,
        len: int,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
    ) -> void {
        if (
            module != "color"
                || !(name == "grayscale" || name == "invert" || name == "opacity" || name == "alpha")
        ) {
            return;
        }
        // The gates that can take a lock or hash the arguments, above the two
        // allocations a message costs and in the same order as the sibling's. A
        // call of one of these four names that turns out not to be a filter call
        // is memoised too, and says nothing either way.
        if (self.deprecation_quieted()) {
            return;
        }
        if (
            self.probe_already_done(
                DepProbePath.ColorModuleCompat,
                name,
                module,
                pos,
                pos_args,
                named,
            )
        ) {
            return;
        }
        let dep = if (name == "alpha") {
            let args = root.builtins.color.legacy.ms_filter_args(pos_args, named);
            if (args == null) {
                return;
            }
            root.deprecation.Deprecation.color_module_compat_ms_filter(
                root.builtins.color.legacy.ms_filter_text(args),
            )
        } else {
            let found = root.builtins.color_ext.module_filter_arg(name, pos_args, named);
            if (found == null) {
                return;
            }
            if (found._0 != root.builtins.color_ext.ModuleFilterArg.Filter) {
                return;
            }
            let arg = found._1;
            root.deprecation.Deprecation.color_module_compat_number(
                name,
                arg.to_css(false),
                root.builtins.color_ext.plain_filter_text(name, arg),
            )
        };
        self.emit_deprecation(dep, pos, len);
    }

    function emit_deprecation(
        self,
        dep: root.deprecation.Deprecation,
        pos: root.scanner.Pos,
        len: int,
    ) -> void {
        if (!self.diag_enabled()) {
            return;
        }
        // dart's `quietDeps`: a deprecation raised inside a dependency is
        // dropped HERE, before the per-id cap, so silenced warnings neither
        // consume the five visible slots nor count towards the "N repetitive
        // deprecation warnings omitted" footer.
        let deps = self.options.quiet_deps;
        if (deps != null) {
            if (deps.is_dependency(self.current_path())) {
                return;
            }
        }
        // `silenceDeprecations` drops by id, in the same place and for the
        // same reason: filtering further out silences the warnings but still
        // tallies them, so the footer reports omissions the caller asked not
        // to hear about. dart prints nothing at all.
        if (
            self.options.silenced_deprecations.some((id) -> {
                id == dep.id
            })
        ) {
            return;
        }
        // Per-location dedup: the SAME warning at the same place fires once.
        // What makes it the same one is everything it SAYS, not just its id:
        // `call(get-function("percentage"))` is two different
        // `[global-builtin]` warnings at one span (one naming `meta.call`, one
        // `math.percentage`), and `[call-string]` has a static message whose
        // `Recommendation:` line carries the name — so one `call($n)` invoked
        // with two names is two warnings. dart prints both, in both cases.
        // key: the Rust `(id, header, url, line, col)` tuple joined with "\0".
        let key = [dep.id, dep.render_header(), self.current_url, pos.line.to_string(), pos.col.to_string()]
            .join("\0");
        if (!root.std.set_insert(self.deprecations_seen, key)) {
            return;
        }
        let count = self.deprecations_shown.get(dep.id) ?? 0;
        if (count >= 5) {
            self.deprecations_omitted += 1;
            return;
        }
        let _ = self.deprecations_shown.set(dep.id, count + 1);

        let frames = self.frames_for(pos);
        let span = root.diag.Span { line: pos.line, col: pos.col, length: len };
        let source = self.current_source;
        let block = dep.render_header();
        block = block + root.diag.render_snippet(source, span, [], self.options.glyphs);
        block = block + "\n";
        block = block + self.render_frame_block(frames, 4);
        let formatted = `${block}\n`;
        self.emit_diag(
            root.WarnEvent {
                kind: root.WarnKind.Warn,
                deprecation: true,
                deprecation_id: dep.id,
                message: dep.message,
                formatted: formatted,
                url: self.current_url,
                line: pos.line,
                path: self.current_path(),
            },
        );
    }

    /// Emit the aggregate "N repetitive deprecation warnings omitted" footer at
    /// the end of the compile, if the per-id cap dropped any warnings.
    function emit_deprecation_footer(self) -> void {
        if (self.deprecations_omitted == 0) {
            return;
        }
        let msg = `${self.deprecations_omitted} repetitive deprecation warnings omitted.`;
        // The second line is dart's, copied verbatim, and it advertises a flag
        // sasso does not have. That is deliberate rather than an oversight: the
        // footer is part of the stderr parity contract (locked by
        // `tests/fixtures/diagnostics/deprecation-cap-{omitted,per-id}.stderr`),
        // so it says what dart says. In dart `--verbose` lifts the per-id cap
        // of 5 that produced this count, and drops this footer along with it --
        // on `deprecation-cap-omitted.scss`, dart-sass 1.103.1 prints 5
        // warnings plus this line without the flag and 8 warnings with no
        // footer under it (verified 2026-09-16). sasso implements only the
        // capped half, so the advice here is unreachable, not wrong. Adding the
        // flag is a CLI feature with fixtures of its own, not a fix to this
        // line.
        let formatted = `WARNING: ${msg}\nRun in verbose mode to see all warnings.\n`;
        self.emit_diag(
            root.WarnEvent {
                kind: root.WarnKind.Warn,
                deprecation: true,
                deprecation_id: "",
                message: msg,
                formatted: formatted,
                url: "",
                line: 0,
                // An aggregate over several files: no single origin (like `url`).
                path: "",
            },
        );
    }

    /// Enter a user callable (mixin/function) for diagnostics: record a stack
    /// frame at `call_pos` (caret length `call_len`) attributed to the *current*
    /// member, then make `new_member` the current member. Returns the previous
    /// member name, to be restored by [`Self::leave_call`].
    /// An error against the innermost CALL SITE — the frame a caller pushed
    /// before it bound arguments or ran a body. Unpositioned when there is no
    /// call in progress (a top-level statement raised it).
    ///
    /// The call site is in the CALLER's file, which by now may not be the
    /// current one (a cross-file call has already switched context), so the
    /// block is rendered here, against that frame's own text.
    /// An error about a construct that has a `declaration` to point back at,
    /// reported at `pos` with the frames as they stand — for a failure that
    /// happens BEFORE the callable is entered, so its own frame is not on the
    /// stack (dart shows only the caller's).
    function error_with_declaration_at(
        self,
        message: string,
        pos: root.scanner.Pos,
        length: int,
        decl: Declared,
    ) -> root.error.Error {
        // PORT: `message: impl Into<String>` is a plain `string`; `.into()` is a no-op.
        // The stack AS IT STANDS, without the synthetic frame naming the
        // member being entered: this error happens before the callable runs,
        // so dart's trace starts at the caller.
        let frames: DiagFrame[] = self.call_stack.reverse();
        let frames = if (frames.length() == 0) {
            self.frames_for(pos)
        } else {
            frames
        };
        let declared = self.declaration_block(message, pos, length, decl, frames);
        let rendered: string? = if (declared != null) {
            declared
        } else if (self.diag_enabled() && frames.length() != 0) {
            // The two spans cannot share a block. Draw the primary one HERE,
            // against the frames as they stand: leaving the error unrendered
            // would defer that until the `@include` arm has popped this call,
            // and the trace would be built from whatever is current then.
            let block = `Error: ${message}\n`;
            block
                = block
                    + root.diag.render_snippet(
                        frames[0].source,
                        root.diag.Span { line: pos.line, col: pos.col, length: length },
                        [],
                        self.options.glyphs,
                    );
            block = block + "\n";
            block = block + self.render_frame_block(frames, 2);
            block
        } else {
            null
        };
        let e = root.error.Error.at(message, pos).with_length(length);
        e.rendered = rendered;
        e
    }

    /// The rendered two-span block, or `None` when this diagnostic cannot have
    /// one: diagnostics off, no declaration position, or two spans the renderer
    /// cannot keep apart (see [`Self::spans_share_a_block`]).
    function declaration_block(
        self,
        message: string,
        pos: root.scanner.Pos,
        length: int,
        decl: Declared,
        frames: DiagFrame[],
    ) -> string? {
        if (!self.diag_enabled() || !decl.pos.is_known() || frames.length() == 0) {
            return null;
        }
        let origin = decl.origin;
        let decl_file: root.std.Tuple2<string, string> = if (origin != null) {
            root.std.Tuple2 { _0: origin.diag_url, _1: origin.source }
        } else {
            root.std.Tuple2 { _0: frames[0].url, _1: frames[0].source }
        };
        let decl_url = decl_file._0;
        let decl_source = decl_file._1;
        let decl_span = root.diag.Span { line: decl.pos.line, col: decl.pos.col, length: decl.length };
        let call_span = root.diag.Span { line: pos.line, col: pos.col, length: length };
        if (
            !Evaluator.spans_share_a_block(
                root.std.Tuple3 { _0: frames[0].url, _1: frames[0].source, _2: call_span },
                root.std.Tuple3 { _0: decl_url, _1: decl_source, _2: decl_span },
            )
        ) {
            return null;
        }
        let rendered = `Error: ${message}\n`;
        // A third and fourth place a frame becomes text: this snippet prints
        // a header per file group. The SOURCE stays part of the grouping key
        // (see `render_labelled_snippet`), so naming the groups for display
        // cannot draw one file's span against another's lines.
        let call_name = self.frame_name(frames[0].url);
        let decl_name = self.frame_name(decl_url);
        rendered
            = rendered
                + root.diag.render_labelled_snippet(
                    call_name,
                    frames[0].source,
                    call_span,
                    "invocation",
                    [
                        root.diag.Secondary {
                            url: decl_name,
                            source: decl_source,
                            span: decl_span,
                            label: "declaration",
                        },
                    ],
                    [],
                    self.options.glyphs,
                );
        rendered = rendered + "\n";
        rendered = rendered + self.render_frame_block(frames, 2);
        rendered
    }

    /// [`Self::error_at_call`] with dart's SECOND span: the `declaration` the
    /// failure is measured against, in the file it was written in.
    ///
    /// Falls back to the plain single-span block for the one pair of spans the
    /// renderer cannot keep apart (see [`Self::spans_share_a_block`]).
    function error_at_call_with_declaration(
        self,
        message: string,
        decl: Declared,
    ) -> root.error.Error {
        // PORT: `message: impl Into<String>` is a plain `string`; `.into()` is a no-op.
        let frame = root.std.last(self.call_stack);
        if (frame == null) {
            return root.error.Error.unpositioned(message);
        }
        if (!self.diag_enabled() || !decl.pos.is_known()) {
            return self.error_at_call(message);
        }
        let origin = decl.origin;
        let decl_file: root.std.Tuple2<string, string> = if (origin != null) {
            root.std.Tuple2 { _0: origin.diag_url, _1: origin.source }
        } else {
            root.std.Tuple2 { _0: frame.url, _1: frame.source }
        };
        let decl_url = decl_file._0;
        let decl_source = decl_file._1;
        let decl_span = root.diag.Span { line: decl.pos.line, col: decl.pos.col, length: decl.length };
        let call_span = root.diag.Span { line: frame.pos.line, col: frame.pos.col, length: frame.length };
        if (
            !Evaluator.spans_share_a_block(
                root.std.Tuple3 { _0: frame.url, _1: frame.source, _2: call_span },
                root.std.Tuple3 { _0: decl_url, _1: decl_source, _2: decl_span },
            )
        ) {
            return self.error_at_call(message);
        }
        let e = root.error.Error.at(message, frame.pos).with_length(frame.length);
        let frames: DiagFrame[] = [];
        frames.push(
            DiagFrame {
                url: frame.url,
                pos: frame.pos,
                member: self.member,
                length: frame.length,
                content: false,
                source: frame.source,
            },
        );
        root.std.extend(frames, self.call_stack.reverse());
        let rendered = `Error: ${message}\n`;
        let call_name = self.frame_name(frame.url);
        let decl_name = self.frame_name(decl_url);
        rendered
            = rendered
                + root.diag.render_labelled_snippet(
                    call_name,
                    frame.source,
                    call_span,
                    "invocation",
                    [
                        root.diag.Secondary {
                            url: decl_name,
                            source: decl_source,
                            span: decl_span,
                            label: "declaration",
                        },
                    ],
                    [],
                    self.options.glyphs,
                );
        rendered = rendered + "\n";
        rendered = rendered + self.render_frame_block(frames, 2);
        e.rendered = rendered;
        e
    }

    /// Whether the call and the declaration can be drawn in one rendered
    /// block. They can, unless they sit in the SAME file with OVERLAPPING
    /// lines AND both draw an ARM: dart nests a second arm column and crosses
    /// the two for that shape, which the renderer cannot do. Anything less
    /// overlapping is drawable — two spans on one line stack their underline
    /// rows, and a span that stays within its line sits inside an arm's range
    /// with the arm running down the column beside it. A file is identified by
    /// its text as well as its display url: two custom-importer files can
    /// share a display name.
    function spans_share_a_block(
        call: root.std.Tuple3<string, string, root.diag.Span>,
        decl: root.std.Tuple3<string, string, root.diag.Span>,
    ) -> bool {
        let call_url = call._0;
        let call_source = call._1;
        let call_span = call._2;
        let decl_url = decl._0;
        let decl_source = decl._1;
        let decl_span = decl._2;
        if (call_url != decl_url || call_source != decl_source) {
            return true;
        }
        let call_range = root.diag.span_line_range(call_source, call_span);
        let call_first = call_range._0;
        let call_last = call_range._1;
        let decl_range = root.diag.span_line_range(decl_source, decl_span);
        let decl_first = decl_range._0;
        let decl_last = decl_range._1;
        let overlapping = call_first <= decl_last && decl_first <= call_last;
        let both_arms = call_first != call_last && decl_first != decl_last;
        !(overlapping && both_arms)
    }

    function error_at_call(self, message: string) -> root.error.Error {
        let frame = root.std.last(self.call_stack);
        if (frame == null) {
            return root.error.Error.unpositioned(message);
        }
        let e = root.error.Error.at(message, frame.pos).with_length(frame.length);
        if (self.diag_enabled()) {
            // The innermost trace line names the CALLEE at the call's position
            // (dart: `file 2:9  f()`), and reads its snippet from the caller's
            // file; the frames under it are the stack as it stands.
            let frames: DiagFrame[] = [];
            frames.push(
                DiagFrame {
                    url: frame.url,
                    pos: frame.pos,
                    member: self.member,
                    length: frame.length,
                    content: false,
                    source: frame.source,
                },
            );
            root.std.extend(frames, self.call_stack.reverse());
            e.rendered = self.render_error_at(e, frames[0], frames);
        }
        e
    }

    function enter_call(
        self,
        call_pos: root.scanner.Pos,
        call_len: int,
        new_member: string,
    ) -> string {
        self.push_frame(call_pos, call_len, new_member, false)
    }

    /// [`Self::enter_call`] for a `@content;` invocation: the frame shows in
    /// the trace under the `@content` member but is never an `@error`
    /// boundary (see [`DiagFrame::content`]).
    function enter_content_call(self, call_pos: root.scanner.Pos) -> string {
        self.push_frame(call_pos, "@content".length(), "@content", true)
    }

    function push_frame(
        self,
        call_pos: root.scanner.Pos,
        call_len: int,
        new_member: string,
        content: bool,
    ) -> string {
        self.call_stack.push(
            DiagFrame {
                url: self.current_url,
                pos: call_pos,
                member: self.member,
                length: call_len,
                content: content,
                source: self.current_source,
            },
        );
        let old = self.member;
        self.member = new_member;
        old
    }

    /// Leave a user callable: pop its diagnostic frame and restore `member`.
    function leave_call(self, saved_member: string) -> void {
        let _ = self.call_stack.pop();
        self.member = saved_member;
    }

    /// The canonical URL of the stylesheet being evaluated (the resolved path
    /// for a filesystem file), for [`crate::WarnEvent::path`]; `""` if unknown.
    function current_path(self) -> string {
        let c = self.current_canonical;
        if (c != null) {
            c.as_str()
        } else {
            ""
        }
    }

    /// Deliver a diagnostic to the embedder's handler (dart-sass `logger`), or —
    /// when none is set — print its `formatted` block to stderr (preserving the
    /// exact native output, since the handler-less path mirrors the old
    /// `eprintln!`s byte-for-byte).
    function emit_diag(self, ev: root.WarnEvent) -> void {
        let handler = self.options.warn;
        if (handler != null) {
            // Run the embedder's handler outside the arena scope, so
            // whatever it retains from the event (a buffered log, a list
            // of warnings) is allocated by the system allocator and
            // outlives this compile's arena reset — the same reason
            // importer calls are paused. Inside the scope a `String` the
            // handler grows would land in the arena and dangle afterwards.
            let _paused = root.arena.pause();
            // PORT: the guard's `Drop` runs at scope exit.
            defer { _paused.drop() }
            handler(ev);
        } else {
            baml.io.eprintln(ev.formatted);
        }
    }

    /// Execute a `@warn`: emit `WARNING: <message>` + the 4-space-indented stack
    /// trace + a trailing blank line to stderr. The message is the string value
    /// unquoted; exit code is unaffected.
    function emit_warn(self, value: root.ast.Expr, pos: root.scanner.Pos) -> void {
        let v = self.eval_expr(value);
        let msg = v.to_message();
        let formatted = if (self.diag_enabled()) {
            let frames = self.frames_for(pos);
            `WARNING: ${msg}\n${self.render_frame_block(frames, 4)}\n`
        } else {
            `WARNING: ${msg}`
        };
        self.emit_diag(
            root.WarnEvent {
                kind: root.WarnKind.Warn,
                deprecation: false,
                deprecation_id: "",
                message: msg,
                formatted: formatted,
                url: self.current_url,
                line: pos.line,
                path: self.current_path(),
            },
        );
    }

    /// Execute a `@debug`: emit `<path>:<line> DEBUG: <value>` to stderr (the
    /// value serialized as in CSS, a string unquoted). No snippet, no frames.
    function emit_debug(self, value: root.ast.Expr, pos: root.scanner.Pos) -> void {
        let v = self.eval_expr(value);
        let msg = v.to_message();
        let url = self.current_url;
        let formatted = if (self.diag_enabled()) {
            `${url}:${pos.line} DEBUG: ${msg}`
        } else {
            `DEBUG: ${msg}`
        };
        self.emit_diag(
            root.WarnEvent {
                kind: root.WarnKind.Debug,
                deprecation: false,
                deprecation_id: "",
                message: msg,
                formatted: formatted,
                url: url,
                line: pos.line,
                path: self.current_path(),
            },
        );
    }

    /// Build the error for an `@error`: its message is the serialized argument
    /// (a string keeps its quotes). The snippet points at the innermost active
    /// call site (so an `@error` inside a mixin highlights the `@include`), or
    /// at the `@error` statement itself when there is no enclosing call. dart's
    /// "unspanned exception attaches at the boundary" rule.
    function build_error(
        self,
        value: root.ast.Expr,
        pos: root.scanner.Pos,
        length: int,
    ) -> root.error.Error {
        let v = self.eval_expr(value) catch (e) {
            let err: root.error.Error => {
                return err;
            }
        };
        let msg = v.to_inspect_message();
        if (!self.diag_enabled()) {
            return root.error.Error.unpositioned(msg);
        }
        // The @error throws unspanned; the nearest enclosing call boundary
        // attaches its span. With an active call stack, the snippet points at
        // the innermost call site and the trace is the callers only (the
        // @error's own frame is dropped). At the root, the @error span is used.
        let frames: DiagFrame[] = if (self.call_stack.length() == 0) {
            [
                DiagFrame {
                    url: self.current_url,
                    pos: pos,
                    member: self.member,
                    length: length,
                    content: false,
                    source: self.current_source,
                },
            ]
        } else {
            self.call_stack.reverse()
        };
        // dart attaches a spanless `@error` at the nearest mixin or function
        // call boundary: a `@content;` invocation is not one, so an error in a
        // content block — however many forwarding blocks deep — carets the
        // `@include` whose mixin is running, while the `@content` frames stay
        // in the trace.
        let boundary = frames.find((f) -> {
            !f.content
        })
            ?? frames[0];
        let e = root.error.Error.at(msg, boundary.pos);
        e.length = boundary.length;
        e.rendered = self.render_error_at(e, boundary, frames);
        e
    }

    function compressed(self) -> bool {
        self.options.style == root.OutputStyle.Compressed
    }

    // ---- callables ---------------------------------------------------
    // ---- statements --------------------------------------------------
    /// Execute a block of statements, routing each into `sink`. One executor
    /// serves the top level (each statement is its own group), rule bodies
    /// (declarations join the block, nested rules bubble out), and every
    /// nested-block construct that reuses it.
    function exec(
        self,
        stmts: root.ast.Stmt[],
        parents: string[],
        sink: root.std.Cell<Sink>,
    ) -> void {
        // PORT: a `Result` held across cleanup (`let r = …; cleanup; r?`) is caught
        // into a `root.error.Error?` local and re-thrown after the cleanup.
        for (let stmt in stmts) {
            match (stmt) {
                let s: root.ast.Stmt_VarDecl => {
                    self.apply_var(s._0);
                },
                let s: root.ast.Stmt_Comment => {
                    let text = self.eval_template(s._0);
                    let lines = self.stamp(s._1);
                    sink.value.push_comment(text, lines);
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_Decl => {
                    let d = s._0;
                    if (sink.value.is_top()) {
                        throw root.error.Error.at("top-level declarations aren't allowed", d.pos);
                    }
                    let oi = self.eval_decl(d);
                    if (oi != null) {
                        sink.value.push_item(oi);
                        self.last_child_invisible = false;
                    }
                },
                let s: root.ast.Stmt_PropertySet => {
                    let ps = s._0;
                    if (sink.value.is_top()) {
                        throw root.error.Error.at("top-level declarations aren't allowed", ps.pos);
                    }
                    self.eval_property_set(ps, parents, sink);
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_CustomDecl => {
                    let d = s._0;
                    if (sink.value.is_top()) {
                        throw root.error.Error.at("top-level declarations aren't allowed", d.pos);
                    }
                    // A literal `--` name may never be nested inside a property
                    // set (dart-sass parse-time error).
                    if (self.decl_prefix != null) {
                        throw root.error.Error.at(
                            "Declarations whose names begin with \"--\" may not be nested.",
                            d.pos,
                        );
                    }
                    let oi = self.eval_custom_decl(d);
                    if (oi != null) {
                        sink.value.push_item(oi);
                        self.last_child_invisible = false;
                    }
                },
                let s: root.ast.Stmt_Rule => {
                    self.eval_style_rule(s._0, parents, sink);
                },
                let s: root.ast.Stmt_If => {
                    // Evaluate conditions top to bottom; run the first match's
                    // body in a fresh semi-global scope so an assignment to an
                    // existing outer variable updates it (and can reach the
                    // global scope when every enclosing scope is semi-global),
                    // while a freshly declared variable stays local to the
                    // branch (dart-sass `visitIf`).
                    for (let branch in s._0) {
                        let cond = branch.cond;
                        let take = if (cond == null) {
                            true
                        } else {
                            self.eval_expr(cond).is_truthy()
                        };
                        if (take) {
                            self.push_scope(true);
                            let result: root.error.Error? = null;
                            self.exec(branch.body, parents, sink) catch (e) {
                                let err: root.error.Error => {
                                    result = err;
                                }
                            };
                            self.pop_scope();
                            if (result != null) {
                                throw result;
                            }
                            break;
                        }
                    }
                },
                let s: root.ast.Stmt_For => {
                    let bounds = self.for_bounds(s.from, s.to);
                    let start_i = bounds._0;
                    let end_i = bounds._1;
                    let unit = bounds._2;
                    // The loop body runs in its own semi-global scope: the loop
                    // variable and any fresh assignments live there and vanish
                    // when the loop ends (dart-sass `visitForRule`).
                    self.push_scope(true);
                    // Source-map: the loop variable is defined by `from`
                    // (evaluate.dart:1666); resolved inside the scope like dart.
                    let span = self.expression_node(s.from, s.from_pos);
                    let result: root.error.Error? = null;
                    for (let i in for_indices(start_i, end_i, s.inclusive)) {
                        self.set_local(
                            s.var,
                            root.value.Value_Number {
                                _0: root.value.Number.with_unit(i * 1.0, unit),
                            },
                            span,
                        );
                        self.exec(s.body, parents, sink) catch (e) {
                            let err: root.error.Error => {
                                result = err;
                            }
                        };
                        if (result != null) {
                            break;
                        }
                    }
                    self.pop_scope();
                    if (result != null) {
                        throw result;
                    }
                },
                let s: root.ast.Stmt_Each => {
                    let items = self.eval_each_items(s.list);
                    // Source-map: every bound variable is defined by the list
                    // expression, resolved before the scope is pushed
                    // (evaluate.dart:1441).
                    let span = self.expression_node(s.list, s.list_pos);
                    self.push_scope(true);
                    let result: root.error.Error? = null;
                    for (let i in baml.iter.Range.new(0, items.len())) {
                        self.bind_each(s.vars, items.get(i), span);
                        self.exec(s.body, parents, sink) catch (e) {
                            let err: root.error.Error => {
                                result = err;
                            }
                        };
                        if (result != null) {
                            break;
                        }
                    }
                    self.pop_scope();
                    if (result != null) {
                        throw result;
                    }
                },
                let s: root.ast.Stmt_While => {
                    self.push_scope(true);
                    let result: root.error.Error? = null;
                    let guard = 0;
                    while (true) {
                        // PORT: `match self.eval_expr(cond)` — an `Err` lands in
                        // `result` and leaves `v` null.
                        let v: root.value.Value? = self.eval_expr(s.cond) catch (e) {
                            let err: root.error.Error => {
                                result = err;
                                null
                            }
                        };
                        if (v == null) {
                            break;
                        }
                        if (!v.is_truthy()) {
                            break;
                        }
                        self.exec(s.body, parents, sink) catch (e) {
                            let err: root.error.Error => {
                                result = err;
                            }
                        };
                        if (result != null) {
                            break;
                        }
                        guard += 1;
                        if (guard >= 100000) {
                            result
                                = root.error.Error.unpositioned("@while exceeded 100000 iterations");
                            break;
                        }
                    }
                    self.pop_scope();
                    if (result != null) {
                        throw result;
                    }
                },
                let s: root.ast.Stmt_FunctionDef => {
                    let callable = s._0;
                    let captured = self.capture_callable(callable);
                    self.define_function(callable.name, captured);
                },
                let s: root.ast.Stmt_MixinDef => {
                    let callable = s._0;
                    let captured = self.capture_callable(callable);
                    self.define_mixin(callable.name, captured);
                },
                let _s: root.ast.Stmt_Return => {
                    throw root.error.Error.unpositioned("@return is only allowed inside a function.");
                },
                let s: root.ast.Stmt_Include => {
                    // Push a diagnostic call frame so an error/warning raised in
                    // the mixin body unwinds through this `@include` call site.
                    let saved = self.enter_call(s.pos, s.length, mixin_frame_name(s.name, s.module));
                    let r: root.error.Error? = null;
                    self.exec_include(
                        s.name,
                        s.args,
                        s.content,
                        s.content_params,
                        s.module,
                        s.pos,
                        s.length,
                        s.full_length,
                        parents,
                        sink,
                    ) catch (e) {
                        let err: root.error.Error => {
                            r = err;
                        }
                    };
                    self.leave_call(saved);
                    // An error the include itself reported AT this position —
                    // a content block the mixin does not take, a
                    // `meta.load-css` that found nothing — takes the call's
                    // span. An error from the mixin BODY keeps its own context
                    // (dart reports it against the failing construct), and an
                    // argument error is already anchored to this call by
                    // `error_at_call`.
                    if (r != null) {
                        throw r.with_length_at(s.pos, s.length);
                    }
                },
                let s: root.ast.Stmt_Use => {
                    self.exec_use(s.url, s.namespace, s.star, s.config, s.pos, parents, sink) catch (e) {
                        let err: root.error.Error => {
                            throw err.with_length_at(s.pos, s.length);
                        }
                    };
                },
                let s: root.ast.Stmt_Forward => {
                    self.exec_forward(
                        s.url,
                        s.prefix,
                        s.show,
                        s.hide,
                        s.config,
                        s.pos,
                        parents,
                        sink,
                    ) catch (e) {
                        let err: root.error.Error => {
                            throw err.with_length_at(s.pos, s.length);
                        }
                    };
                },
                let s: root.ast.Stmt_Content => {
                    // The content block runs in the caller's context, so it is no
                    // longer "directly in a mixin" (dart-sass): a
                    // `meta.content-exists()` inside it is an error.
                    self.in_mixin.push(false);
                    let result: root.error.Error? = null;
                    self.exec_content(s.args, s.pos, parents, sink) catch (e) {
                        let err: root.error.Error => {
                            result = err;
                        }
                    };
                    let _ = self.in_mixin.pop();
                    if (result != null) {
                        throw result;
                    }
                },
                let s: root.ast.Stmt_Import => {
                    self.eval_imports(s.args, parents, sink);
                },
                let s: root.ast.Stmt_AtRule => {
                    let lines = self.stamp(s.lines);
                    self.eval_at_rule(s.name, s.prelude, s.body, lines, parents, sink);
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_InterpAtRule => {
                    // The name resolves at eval time; `@keyframes` is the one
                    // rule whose special handling happens here (frame stops).
                    let resolved = self.eval_template(s.name);
                    // An interpolated name changes nothing about the RULE: it
                    // carries its own span, so it maps like any other at-rule
                    // and joins a trailing comment the same way (dart parity).
                    let stamped = self.stamp(s.lines);
                    let body = s.body;
                    if (is_keyframes_name(resolved) && body != null) {
                        // PORT: the inner `if let Some(b) = body` is already
                        // narrowed by the condition above.
                        self.eval_keyframes(resolved, s.prelude, body, stamped, sink);
                    } else {
                        self.eval_at_rule(resolved, s.prelude, body, stamped, parents, sink);
                    }
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_CssCustomAtRule => {
                    self.eval_css_custom_at_rule(s.name, s.prelude, s.body, sink);
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_Media => {
                    let stamped = self.stamp(s.lines);
                    self.eval_media(s.query, s.body, stamped, parents, sink);
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_Supports => {
                    let stamped = self.stamp(s.lines);
                    self.eval_supports(s.condition, s.body, stamped, parents, sink);
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_AtRoot => {
                    self.eval_at_root(s.query, s.body, parents, sink);
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_Keyframes => {
                    let lines = self.stamp(s.lines);
                    self.eval_keyframes(s.name, s.prelude, s.body, lines, sink);
                    self.last_child_invisible = false;
                },
                let s: root.ast.Stmt_Extend => {
                    self.register_extend(s.selector, s.optional, s.pos, parents);
                },
                let s: root.ast.Stmt_Warn => {
                    self.emit_warn(s.value, s.pos);
                },
                let s: root.ast.Stmt_Debug => {
                    self.emit_debug(s.value, s.pos);
                },
                let s: root.ast.Stmt_Error => {
                    throw self.build_error(s.value, s.pos, s.length);
                },
                // PORT: the Rust match is exhaustive over `Stmt`.
                _ => root.std.unreachable(),
            }
        }
    }

    /// Evaluate a style rule: resolve its selector against `parents`, run its
    /// body into a fresh rule sink, then hand the produced block and the
    /// rules that bubbled out of it to the enclosing `sink`.
    /// A placeholder rule stays an `@extend` target even when its body produces
    /// nothing (`%bam { bam: null }` is "found", dart keeps every rule in the
    /// extend graph; we prune empty rules from the output tree, so the selector
    /// is recorded with its module scope).
    function note_placeholder_rule(self, s: string) -> void {
        if (s.includes("%")) {
            self.placeholder_rules.push(root.std.Tuple2 { _0: self.current_module, _1: s });
        }
    }

    function eval_style_rule(
        self,
        rule: root.ast.Rule,
        parents: string[],
        sink: root.std.Cell<Sink>,
    ) -> void {
        let bounds = self.eval_template_bounds(rule.selector);
        let sel_str = bounds._0;
        let interp_bounds = bounds._1;
        // A selector that resolves to nothing (e.g. `#{&}` at the document root,
        // where `&` is null) is rejected by dart-sass with "expected selector".
        if (root.std.trim(sel_str) == "") {
            throw root.error.Error.unpositioned("expected selector.");
        }
        validate_selector(sel_str, parents.length() != 0);
        // A `@` has no legal position in a CSS selector: dart's selector
        // parser fails with "expected selector." — pointed at the source when
        // the offending character maps to literal text, or rendered as the
        // dual-span "error in interpolated output" diagnostic when it came
        // from an interpolation (todo_single_escape).
        if (!self.in_keyframes) {
            let at_idx = find_unquoted_at(sel_str);
            if (at_idx != null) {
                throw self.interp_selector_error(rule, sel_str, interp_bounds, at_idx);
            }
        }
        // A selector starting with a digit is dart's "expected selector."
        // (`1a {}`, issue_2023) — except keyframe stops (`50%`, `13E2%`).
        if (!self.in_keyframes) {
            for (let part in split_commas(sel_str).deref()) {
                if (root.std.is_ascii_digit(root.std.first_char(root.std.trim_start(part)))) {
                    throw root.error.Error.unpositioned("expected selector.");
                }
            }
        }
        // A keyframe selector list is stops (`from`, `to`, `13E+1%`), not CSS
        // selectors: no combinator normalization or parent resolution.
        // Fast path for the line-break flags: no newline anywhere in the source
        // list and no inherited parent breaks means every flag is false — an
        // EMPTY vec, which all consumers read as all-false. Keyframe selector
        // lists always take it (dart re-serializes stops joined with ", ").
        let lbs_fast = self.in_keyframes || (self.current_linebreaks.length() == 0 && !sel_str.includes("\n"));
        let part_lbs: bool[] = if (lbs_fast) {
            []
        } else {
            comma_linebreaks(sel_str, false)
        };
        let parent_lbs: bool[] = if (self.current_linebreaks.length() == parents.length()) {
            self.current_linebreaks
        } else {
            []
        };
        // Per-complex source line-breaks (`a,\nb`), on the same fast path as
        // `part_lbs`: when every flag would be false the resolver is told not to
        // derive them, and hands back the empty vec all consumers read as
        // all-false. Keyframe selector lists always take it (dart re-serializes
        // the stops joined with ", ", dropping author line breaks that
        // style-rule selectors preserve).
        // `maybe_bogus` / `any_percent` are the resolver's aggregate answers to
        // the two questions the block below would otherwise ask per selector, one
        // full byte scan each. A keyframe list is resolved here rather than by
        // `resolve_selectors_opt`, so it gets the conservative answer — and a
        // keyframe stop really does carry a `%`.
        let resolved_all: root.std.Tuple4<string[], bool[], bool, bool> = if (self.in_keyframes) {
            root.std.Tuple4 {
                _0: split_commas(sel_str).deref()
                    .map((p) -> {
                        root.std.trim(p)
                    })
                    .filter((p) -> {
                        p != ""
                    }),
                _1: [],
                _2: true,
                _3: true,
            }
        } else {
            let resolved = resolve_selectors_opt(sel_str, parents, !self.at_root_excluding_style_rule, part_lbs, parent_lbs, !lbs_fast);
            let maybe_bogus = resolved.maybe_bogus;
            let any_percent = resolved.any_percent;
            root.std.Tuple4 {
                _0: resolved.sels,
                _1: resolved.lbs,
                _2: maybe_bogus,
                _3: any_percent,
            }
        };
        let current = resolved_all._0;
        let full_lbs = resolved_all._1;
        let maybe_bogus = resolved_all._2;
        let any_percent = resolved_all._3;
        // Drop "bogus combinator" complex selectors from the emitted block;
        // dart-sass omits them from the generated CSS. A top-level TRAILING
        // combinator (`a >`) is bogus as a leaf (its own declaration block is
        // dropped) but valid for NESTING, so the full `current` list — including
        // such selectors — is still used for `&` resolution and as the `parents`
        // for nested rules (`a >` + `b` -> `a > b`). A nested rule that inherits
        // a genuinely bogus combinator (double, or leading/trailing in a pseudo)
        // is dropped in turn.
        // `current` is `parents × parts` (or just `parts` at the root), so
        // complex `i` came from part `i % parts.len()`; `full_lbs` carries that
        // part's "newline before" flag, and is filtered below in step with the
        // dropped bogus selectors.
        // PORT: `Rc::new(current)` — the array is already shared by reference.
        // Nothing bogus to drop, no keyframe stop to normalize and no per-complex
        // line-break flags to filter in step: the emitted list is `current`
        // itself, and copying every string to say so is pure waste on the shape
        // almost every rule has. The placeholder bookkeeping below still runs.
        // `complex_selector_block_is_bogus` opens by looking for `> + ~ (`, so on
        // the no-trigger shape it is one full byte scan per selector with no early
        // exit. `!maybe_bogus` already proves no selector holds one of those
        // bytes, so the whole probe is skipped rather than run to a foregone
        // conclusion; when the proof is unavailable it runs exactly as before.
        let share_current = !self.in_keyframes
            && full_lbs.length() == 0
            && (
                !maybe_bogus
                    || !current.some((s) -> {
                        complex_selector_block_is_bogus(s)
                    })
            );
        let emit_selectors: string[] = [];
        let emit_linebreaks: bool[] = [];
        // Bogus-combinator warnings are raised AFTER this rule's body, because
        // that is dart's order: on lila's `.#{$name} > + lines { & interrupt
        // {…} }` dart reports the nested `… interrupt` first and the rule that
        // contains it second. Emitting where the selector is dropped gets the
        // set right and the order backwards.
        let pending_bogus: root.std.Tuple3<root.scanner.Pos, int, string>[] = [];
        // Both of these are read ONLY inside the bogus branch below, which
        // almost no rule takes, and `eval_style_rule` is the hottest function
        // in the compiler. Taking the `Rc` unconditionally put a clone+drop on
        // every style rule in every stylesheet to serve a branch that fires on
        // a handful; it is taken on first need instead.
        let src_text: string? = null;
        if (share_current) {
            // Only a `%`-bearing selector can be a placeholder rule, and the
            // resolver's scan already answered that for the whole list.
            if (any_percent) {
                for (let s in current) {
                    self.note_placeholder_rule(s);
                }
            }
        } else {
            // PORT: `reserve(current.len())` capacity hints dropped.
            let own_parts: int? = null;
            for (let i in baml.iter.Range.new(0, current.length())) {
                let s = current[i];
                if (complex_selector_block_is_bogus(s)) {
                    // dart WARNS as it drops this rule, and the warning is the
                    // only sign the CSS lost it (#119). Only the "invalid CSS"
                    // shape is reported: a bare TRAILING combinator is dart's
                    // other message, which carries a second span labelling the
                    // offending child that this renderer cannot draw yet.
                    //
                    // `current` is `parents x parts`, so complex `i` was
                    // produced by part `i % own_parts` — the entry dart points
                    // at, while the message names the RESOLVED selector.
                    if (complex_selector_is_bogus(s, false, false)) {
                        let parts = own_parts ?? root.std.imax(split_commas(sel_str).deref().length(), 1);
                        own_parts = parts;
                        let src = src_text ?? self.current_source;
                        src_text = src;
                        let span = selector_part_span(src, rule, sel_str, interp_bounds, i % parts);
                        let pos = span._0;
                        let len = span._1;
                        pending_bogus.push(root.std.Tuple3 { _0: pos, _1: len, _2: s });
                    }
                    // The omitted selector still participates in @extend target
                    // matching (dart keeps the rule in the extend graph and only
                    // omits it from the emitted CSS).
                    self.bogus_selectors.push(s);
                    continue;
                }
                self.note_placeholder_rule(s);
                // A keyframe stop is re-serialized: `FROM` -> `from`, and a
                // percentage's exponent marker `130E-1%` -> `130e-1%`.
                let s = if (self.in_keyframes) {
                    normalize_keyframe_selector(s)
                } else {
                    s
                };
                emit_selectors.push(s);
                if (full_lbs.length() != 0) {
                    emit_linebreaks.push(full_lbs.at(i) ?? false);
                }
            }
        }
        // One handle for the whole rule: shared with `current_selector` on the
        // common shape, and cloned into every block this rule flushes.
        let emitted: string[] = if (share_current) {
            current
        } else {
            emit_selectors
        };
        self.push_scope(false);
        let prev_selector = self.current_selector;
        self.current_selector = current;
        let prev_linebreaks = self.current_linebreaks;
        self.current_linebreaks = full_lbs;
        // Entering a style rule re-enables the implicit parent join for
        // anything nested below it (dart resets _atRootExcludingStyleRule).
        let prev_at_root = self.at_root_excluding_style_rule;
        self.at_root_excluding_style_rule = false;
        let rule_lines = self.stamp(
            root.ast.SrcLines {
                file: 0,
                start: rule.brace_line,
                end: rule.end_line,
                col: 0,
                // Source-map: the selector's first character — its own line and
                // 0-based column, which differ from the brace line when the
                // selector list spans several lines (dart maps
                // `node.selector.span.start`).
                start_col: root.std.saturating_sub_u(rule.selector_pos.col, 1),
                map_file: 0,
                map_line: rule.selector_pos.line,
            },
        );
        // A `@media`/`@at-root` nested in this rule's body bubbles a copy of the
        // selector out; that copy maps back to THIS selector's source position
        // (dart parity). Source-map only — never touches CSS.
        let prev_rule_lines = self.cur_rule_lines;
        self.cur_rule_lines = rule_lines;
        let prev_rule_extend_base = self.cur_rule_extend_base;
        self.cur_rule_extend_base = self.extends_.length();
        let items: OutItem[] = [];
        let nested: OutNode[] = [];
        let flushed: int? = null;
        let at_depth = self.at_rule_ctx.length();
        // dart `addSelector` timing: how many `@extend`s were already registered
        // when this rule's selector was established (before its body runs and
        // registers any of its own). A rule registered AFTER all its applicable
        // `@extend`s is extended one-shot in dart's `paths` order; otherwise the
        // registration-order fold.
        let extend_base = self.extends_.length();
        // Fresh trailing-invisible tracking for THIS body (the exit below
        // overwrites the flag with this rule's own contribution, so the
        // parent needs no save).
        self.last_child_invisible = false;
        let result: root.error.Error? = null;
        {
            // PORT: the sink borrowed `items`, `nested` and `flushed` as `&mut`;
            // here it holds them, and `nested` is read back from it below.
            let child_rule = Sink_Rule {
                selectors: SinkSelectors_Shared { _0: emitted },
                linebreaks: emit_linebreaks,
                lines: rule_lines,
                items: items,
                nested: nested,
                at_depth: at_depth,
                flushed: flushed,
                extend_base: extend_base,
            };
            let child: root.std.Cell<Sink> = root.std.Cell { value: child_rule };
            self.exec(rule.body, current, child) catch (e) {
                let err: root.error.Error => {
                    result = err;
                }
            };
            // Flush any declarations/loud comments that follow the last nested
            // rule, so they emit (in their own block) after the bubbled rules.
            if (result == null && child.value.flush_rule_block()) {
                // The flushed block is the subtree's last node — visible.
                self.last_child_invisible = false;
            }
            nested = child_rule.nested;
        };
        // After the body, so a nested rule's own bogus selector is reported
        // before its parent's — and only if the body COMPLETED. dart drops the
        // warning when the rule it belongs to failed: an error inside
        // `.a > + .b { color: $nope; }` gets the error alone, while an error in
        // a LATER rule still leaves this one warning. Measured on 1.104.1;
        // flushing unconditionally reported a deprecation for a rule that never
        // finished.
        if (result == null) {
            for (let pb in pending_bogus) {
                let dep = root.deprecation.Deprecation.bogus_combinators(pb._2);
                self.emit_deprecation(dep, pb._0, pb._1);
            }
        }
        self.current_selector = prev_selector;
        self.current_linebreaks = prev_linebreaks;
        self.at_root_excluding_style_rule = prev_at_root;
        self.cur_rule_lines = prev_rule_lines;
        self.cur_rule_extend_base = prev_rule_extend_base;
        self.pop_scope();
        if (result != null) {
            throw result;
        }
        // The body's own trailing-invisible state gates THIS rule's group
        // end; then report this rule's contribution to the PARENT body
        // (empty output = dart's invisible node).
        let body_last_invisible = self.last_child_invisible;
        self.last_child_invisible = false;
        let this_rule_invisible = nested.length() == 0 && !self.in_keyframes;
        sink.value.emit_style_rule(nested, !body_last_invisible);
        // dart's group separator rides the subtree's LAST flattened node: a
        // trailing invisible chain ANY levels down (`#al { a { &:hover {
        // @extend } } }`) owns the enclosing group's end and never renders,
        // so the next group packs tight (chirpy panel -> footer seam).
        self.last_child_invisible = this_rule_invisible || body_last_invisible;
    }

    /// The CSS text of a declaration's value, serialized through the reusable
    /// `css_buf` and then handed over as an exactly-sized `String`.
    ///
    /// The copy at the end is deliberate: the out item outlives the buffer, and
    /// a value's serialized length is not known before it is written, so the
    /// choice is between one regrown allocation per declaration or one buffer
    /// reused for all of them plus a copy that is already right-sized. Taking
    /// the buffer out of `self` is what lets `write_css` borrow it while the
    /// evaluator is borrowed mutably; the borrow is returned before this
    /// returns, and serialization cannot re-enter the evaluator (a `Value` is
    /// fully evaluated by the time it gets here), so the buffer is never
    /// observed missing. Every value that can legally reach this point writes
    /// itself into the buffer without allocating — the ones that cannot are
    /// rejected as invalid CSS values above — so the copy is the only cost the
    /// buffer adds.
    function declared_css(self, value: root.value.Value) -> string {
        let compressed = self.compressed();
        // PORT: `css_buf` is a `string` field (Rust keeps it only as a reusable
        // capacity); `write_css` needs a `StrBuf`, so a fresh one serves as the
        // buffer and the field is left as is.
        let buf = root.std.StrBuf.new();
        buf.clear();
        value.write_css(buf, compressed);
        let text = buf.as_str();
        text
    }

    function eval_decl(self, d: root.ast.Declaration) -> OutItem? {
        let name = trim_shared(self.eval_template_shared(d.property));
        let prefix = self.decl_prefix;
        let prop = if (prefix != null) {
            `${prefix}-${name}`
        } else {
            name
        };
        let value = self.eval_expr(d.value);
        if (value is root.value.Value_Null) {
            return null;
        }
        // A map is not a valid CSS value (even when nested inside a list).
        let m = find_map(value);
        if (m != null) {
            throw root.error.Error.at(
                `${m.to_css(false)} isn't a valid CSS value.`,
                d.pos,
            );
        }
        // A first-class function reference is likewise not a valid CSS value.
        if let f: root.value.Value_Function = value {
            throw root.error.Error.at(
                `${f._0.inspect()} isn't a valid CSS value.`,
                d.pos,
            );
        }
        // A first-class mixin reference is likewise not a valid CSS value.
        if let mx: root.value.Value_Mixin = value {
            throw root.error.Error.at(
                `${mx._0.inspect()} isn't a valid CSS value.`,
                d.pos,
            );
        }
        // An empty unbracketed list (`()`, or e.g. `list.join((), ())`) cannot
        // serialize as a CSS value; a bracketed `[]` is fine, as is any list
        // with at least one element.
        if let l: root.value.Value_List = value {
            if (l._0.items.length() == 0 && !l._0.bracketed) {
                throw root.error.Error.at("() isn't a valid CSS value.", d.pos);
            }
        }
        let vstr = self.declared_css(value);
        // A value that serializes to nothing (an empty unquoted string, an
        // all-`null` list) drops the whole declaration, like a `null` value.
        if (vstr == "") {
            return null;
        }
        // dart computes `valueSpanForMap` as `_expressionNode(node.value).span`
        // (evaluate.dart:1414): a BARE `$name` value resolves to wherever that
        // variable was declared; any other expression shape keeps its own span.
        let value_span = self.expression_node(d.value, d.value_pos);
        OutItem_Decl {
            prop: prop,
            value: vstr,
            important: d.important,
            custom: false,
            lines: self.stamp(
                root.ast.SrcLines {
                    file: 0,
                    start: d.pos.line,
                    end: d.end_line,
                    col: 0,
                    // Source-map: the property name's 0-based start column.
                    start_col: root.std.saturating_sub_u(d.pos.col, 1),
                    map_file: 0,
                    map_line: 0,
                },
            ),
            value_span: value_span,
        }
    }

    /// Evaluate a custom-property declaration: the name and verbatim value are
    /// templates whose `#{…}` interpolation resolves; the value is otherwise
    /// emitted exactly as written (no SassScript evaluation). An empty value
    /// (`--x: ;`) still emits.
    function eval_custom_decl(self, d: root.ast.CustomDecl) -> OutItem? {
        let prop = trim_shared(self.eval_template_shared(d.property));
        let value = self.eval_template(d.value);
        // A custom property is serialized inside `_for(node.value, …)`
        // (serialize.dart:379) — the value's OWN span, never resolved through
        // `_expressionNode`. So `--x: $c` maps to the literal `$c` text.
        let value_span = self.span_at(d.value_pos);
        OutItem_Decl {
            prop: prop,
            value: value,
            important: false,
            custom: true,
            lines: self.stamp(
                root.ast.SrcLines {
                    file: 0,
                    start: d.pos.line,
                    end: d.end_line,
                    // The name's 0-based source column caps the re-indentation
                    // strip for a multi-line value (dart _writeReindentedValue).
                    col: root.std.saturating_sub_u(d.pos.col, 1),
                    // Source-map: the property name's 0-based start column.
                    start_col: root.std.saturating_sub_u(d.pos.col, 1),
                    map_file: 0,
                    map_line: 0,
                },
            ),
            value_span: value_span,
        }
    }

    /// Evaluate a nested property set: resolve its (already prefixed) name,
    /// emit the optional leading value as a declaration, then run the body with
    /// that name installed as the child prefix so each child declaration is
    /// namespaced `<name>-<child>` and emitted in source order.
    function eval_property_set(
        self,
        ps: root.ast.PropertySet,
        parents: string[],
        sink: root.std.Cell<Sink>,
    ) -> void {
        // A nested property set whose own literal name begins with `--` is
        // rejected just like a plain `--` declaration would be when nested.
        if (self.decl_prefix != null && literal_name_is_custom_property(ps.property)) {
            throw root.error.Error.at(
                "Declarations whose names begin with \"--\" may not be nested.",
                ps.pos,
            );
        }
        let name = trim_shared(self.eval_template_shared(ps.property));
        let prefix = self.decl_prefix;
        let full = if (prefix != null) {
            `${prefix}-${name}`
        } else {
            name
        };
        // The leading value (`b: c { … }`) emits `<full>: c;` before children.
        let value_expr = ps.value;
        if (value_expr != null) {
            let value = self.eval_expr(value_expr);
            if (!(value is root.value.Value_Null)) {
                let m = find_map(value);
                if (m != null) {
                    throw root.error.Error.at(
                        `${m.to_css(false)} isn't a valid CSS value.`,
                        ps.pos,
                    );
                }
                let vstr = self.declared_css(value);
                sink.value.push_item(
                    OutItem_Decl {
                        prop: full,
                        value: vstr,
                        important: ps.important,
                        custom: false,
                        // No usable end line of its own (the value precedes the
                        // `{…}` block); the trailing-comment rule stays disabled.
                        lines: root.ast.SrcLines.default(),
                        // A property set's leading value carries no mapping today
                        // (its `lines` are already blank), so neither does its
                        // value — leaving both unmapped stays self-consistent.
                        // PORT: `VarSpan::default()` spelled out (no `default()` declared).
                        value_span: VarSpan { file: 0, line: 0, col: 0 },
                    },
                );
            }
        }
        let saved = self.decl_prefix;
        self.decl_prefix = full;
        let result: root.error.Error? = null;
        self.exec(ps.body, parents, sink) catch (e) {
            let err: root.error.Error => {
                result = err;
            }
        };
        self.decl_prefix = saved;
        if (result != null) {
            throw result;
        }
    }

    /// Evaluate an `@import` statement into `sink`. Sass arguments are parsed
    /// and inlined under the current `parents` (so a nested `@import` bubbles
    /// like an inline block); plain CSS arguments are emitted verbatim as
    /// `@import …;` in source order.
    function eval_imports(
        self,
        args: root.ast.ImportArg[],
        parents: string[],
        sink: root.std.Cell<Sink>,
    ) -> void {
        let importer = self.options.importer;
        for (let arg in args) {
            match (arg) {
                let css: root.ast.ImportArg_Css => {
                    let text = self.serialize_css_import(css.url, css.modifiers);
                    // Source-map: the rule maps to its URL token.
                    let lines = self.map_only_lines(css.pos);
                    // Inside a style rule the plain-CSS @import stays in the
                    // rule's block (dart keeps it nested:
                    // `foo { @import url(...); }`); at the top level it is a
                    // Raw node subject to import hoisting.
                    if (sink.value is Sink_Rule) {
                        sink.value.push_item(
                            OutItem_ChildlessAtRule {
                                name: "import",
                                prelude: text,
                                css_import: true,
                                lines: lines,
                            },
                        );
                    } else {
                        sink.value.push_at_rule(
                            OutNode_Raw { _0: `@import${self.at_rule_gap()}${text};`, _1: lines },
                        );
                    }
                },
                let sass: root.ast.ImportArg_Sass => {
                    let path = sass.path;
                    let pos = sass.pos;
                    let length = sass.length;
                    if (is_css_import(path)) {
                        let lines = self.map_only_lines(pos);
                        sink.value.push_at_rule(
                            OutNode_Raw { _0: `@import${self.at_rule_gap()}"${path}";`, _1: lines },
                        );
                        continue;
                    }
                    // (The `[import]` deprecation for this rule was emitted
                    // when its file was parsed: `warn_import_rules`.)
                    let base = self.current_file_dir;
                    // Per-compile import cache (dart-sass ImportCache): the
                    // same URL imported from the same base directory shares
                    // one resolution + parse; the body still EXECUTES per
                    // import (Sass semantics). Misses and parse errors are
                    // not cached — they re-error identically.
                    // PORT: key `(path, base)` encoded as `path + "\0" + base`, or
                    // just `path` when `base` is `None` (paths never hold NUL).
                    let cache_key = if (base != null) {
                        path + "\0" + base
                    } else {
                        path
                    };
                    let cached = self.import_cache.get(cache_key);
                    let entry: CachedImport? = if (cached != null) {
                        let e = cached;
                        if (self.loading.includes(path)) {
                            throw root.error.Error.unpositioned("This file is already being loaded.");
                        }
                        // A cache hit skips the importer, which is where
                        // dependency provenance is recorded: keep the rule
                        // "what a dependency loads is a dependency" here too.
                        // (Outside the arena scope, like the importer.)
                        let deps = self.options.quiet_deps;
                        if (deps != null) {
                            if (deps.is_dependency(self.current_path())) {
                                let _paused = root.arena.pause();
                                deps.mark(e._0);
                                _paused.drop();
                            }
                        }
                        e
                    } else {
                        // Run the caller's importer outside the arena scope
                        // so any state it caches (paths, sources) outlives
                        // this compile's arena reset; see the matching note
                        // in `load_module`.
                        let paused = root.arena.pause();
                        // Two-phase resolution (canonicalize, then load),
                        // both inside ONE arena pause so the importer's owned
                        // allocations survive this compile's arena reset.
                        // PORT: an importer failure (`Err(ImporterError)`) is a
                        // thrown `root.importer.ImporterError`.
                        let resolved: root.std.Tuple4<string, string, root.Syntax, string?>? = if (importer != null) {
                            let imp = importer;
                            let ctx = root.importer.CanonicalizeContext {
                                from_import: true,
                                containing_url: self.current_canonical,
                            };
                            let canon = imp.canonicalize(path, ctx) catch (e) {
                                let e: root.importer.ImporterError => {
                                    paused.drop();
                                    throw root.error.Error.unpositioned(e.message);
                                }
                            };
                            if (canon == null) {
                                null
                            } else {
                                let res = imp.load(canon) catch (e) {
                                    let e: root.importer.ImporterError => {
                                        paused.drop();
                                        throw root.error.Error.unpositioned(e.message);
                                    }
                                };
                                if (res == null) {
                                    null
                                } else {
                                    root.std.Tuple4 {
                                        _0: canon.as_str(),
                                        _1: res.contents,
                                        _2: res.syntax,
                                        _3: res.source_map_url,
                                    }
                                }
                            }
                        } else {
                            null
                        };
                        paused.drop();
                        if (resolved != null) {
                            let resolved_key = resolved._0;
                            let src = resolved._1;
                            let syntax = resolved._2;
                            let source_map_url = resolved._3;
                            if (self.loading.includes(path)) {
                                throw root.error.Error.unpositioned(
                                    "This file is already being loaded.",
                                );
                            }
                            // A loaded sheet is validated like the
                            // entry (a misplaced `@import` in a mixin
                            // body is dart's "This at-rule is not
                            // allowed here."); plain CSS has nothing
                            // to validate.
                            // PORT: `let parsed = …and_then(..); match parsed { Ok, Err }`
                            // → one block with a `catch` for the `Err` arm.
                            let sheet = {
                                let sheet = parse_with_syntax(src, syntax);
                                if (syntax != root.Syntax.Css) {
                                    validate_declarations(sheet);
                                }
                                sheet
                            } catch (err) {
                                let err: root.error.Error => {
                                    // A parse or validation error names
                                    // the IMPORTED file: render eagerly
                                    // under its url/source with an
                                    // `@import` frame at the URL token
                                    // (dart: `_mod.scss 3:19  @import`).
                                    let diag = self.module_diag_url(path, resolved_key);
                                    let saved_member = self.enter_call(pos, length, "@import");
                                    let saved_url = self.current_url;
                                    self.current_url = diag;
                                    let saved_source = self.current_source;
                                    self.current_source = src;
                                    let err = self.finalize_error(err);
                                    self.current_url = saved_url;
                                    self.current_source = saved_source;
                                    self.leave_call(saved_member);
                                    throw err;
                                }
                            };
                            let e: CachedImport = root.std.Tuple5 {
                                _0: resolved_key,
                                _1: syntax,
                                _2: sheet,
                                _3: src,
                                _4: source_map_url,
                            };
                            let _ = self.import_cache.set(cache_key, e);
                            e
                        } else {
                            null
                        }
                    };
                    if (entry != null) {
                        let resolved_key = entry._0;
                        let syntax = entry._1;
                        let sheet = entry._2;
                        // The diagnostic `@import` frame records the
                        // IMPORTING file at the URL token — push it before
                        // the context swap below rebinds current_url.
                        let saved_member = self.enter_call(pos, length, "@import");
                        // The imported file becomes the diagnostics/stamp
                        // context while its body runs (dart shows ITS name
                        // in error frames, and the trailing-comment check
                        // compares file identity): swap in its display URL
                        // and source, and re-intern the SrcLines file id.
                        let import_diag = if (resolved_key == "") {
                            self.current_url
                        } else {
                            self.module_diag_url(path, resolved_key)
                        };
                        if (self.options.source_map && resolved_key != "") {
                            let _ = self.file_texts.get_or_insert(resolved_key, entry._3);
                            // The importer's `source_map_url` names this
                            // file in `sources[]` (dart's
                            // `ImporterResult.sourceMapUrl`), for `@import`
                            // as for `@use`.
                            let smu = entry._4;
                            if (smu != null) {
                                let _ = self.file_map_urls.get_or_insert(resolved_key, smu);
                            }
                        }
                        let saved_import_url = self.current_url;
                        self.current_url = import_diag;
                        let saved_import_source = self.current_source;
                        self.current_source = entry._3;
                        self.current_url_stamp = 0;
                        // Relative URLs inside the imported sheet resolve
                        // against ITS directory, and its canonical URL is
                        // tracked in lockstep (so a nested relative
                        // `@use`/`@import` resolves against ITS directory,
                        // and its mappings — the file table is keyed by
                        // the canonical URL — land on ITS `sources` entry).
                        let saved_dir = if (resolved_key == "") {
                            self.current_file_dir
                        } else {
                            let old_dir = self.current_file_dir;
                            self.current_file_dir = dirname_of(resolved_key);
                            old_dir
                        };
                        let saved_canonical = if (resolved_key == "") {
                            self.current_canonical
                        } else {
                            let old_canonical = self.current_canonical;
                            self.current_canonical = root.importer.CanonicalUrl.new(resolved_key);
                            old_canonical
                        };
                        // A plain-CSS file imports as plain CSS: nesting
                        // preserved, no Sass evaluation (same as `@use`).
                        if (syntax == root.Syntax.Css) {
                            self.loading.push(path);
                            // PORT: `.map_err(|e| self.finalize_error(e))` kept as
                            // the caught (finalized) error, re-thrown after the
                            // restores (`result?`).
                            let result: root.error.Error? = null;
                            self.exec_css(sheet.stmts, parents, sink) catch (e) {
                                let e: root.error.Error => {
                                    result = self.finalize_error(e);
                                }
                            };
                            self.loading.pop();
                            self.current_file_dir = saved_dir;
                            self.current_canonical = saved_canonical;
                            self.current_url = saved_import_url;
                            self.current_source = saved_import_source;
                            self.current_url_stamp = 0;
                            self.leave_call(saved_member);
                            if (result != null) {
                                throw result;
                            }
                            continue;
                        }
                        self.loading.push(path);
                        // `@import` inlines the file's variables/functions/
                        // mixins into the current scope, but its module
                        // bindings (`@use`/`@forward`) stay local to the
                        // imported file and must not leak to the importer.
                        let saved_used = self.used_modules;
                        self.used_modules = {};
                        let saved_star = self.star_modules;
                        self.star_modules = [];
                        let saved_used_user = self.used_user_modules;
                        self.used_user_modules = {};
                        let saved_star_user = self.star_user_modules;
                        self.star_user_modules = [];
                        // Nested `$var: ... !global` declarations in the
                        // imported sheet register null slots in the
                        // importing module too (dart-sass: members are
                        // statically visible).
                        {
                            let slots: string[] = [];
                            collect_global_var_decls(sheet.stmts, slots);
                            let g = self.scopes.at(0);
                            if (g != null) {
                                for (let name in slots) {
                                    let _ = g.get_or_insert(name, root.value.Value_Null {  });
                                }
                            }
                        };
                        // The imported file's own `@forward`s expose members
                        // as if defined in the importer; collect them
                        // separately, then merge into the current scope.
                        let saved_fwd = self.forwarded;
                        self.forwarded = Forwarded.default();
                        // dart-sass: when the imported file loads
                        // user-defined modules (it has top-level
                        // `@use`/`@forward`), its `@forward`s see every
                        // variable visible at the import — all scope
                        // levels, inner shadowing outer — as an implicit
                        // configuration (`toImplicitConfiguration`); a
                        // file without module loads keeps the current
                        // configuration (an enclosing `with (...)` still
                        // flows into its `!default`s). Unconsumed implicit
                        // entries are never an error.
                        let loads_modules = sheet.stmts.some((s: root.ast.Stmt) -> bool {
                            s is root.ast.Stmt_Use || s is root.ast.Stmt_Forward
                        });
                        let saved_pending_consumed: root.std.Tuple4<map<string, root.std.Tuple2<root.value.Value, bool>>, string[], bool, int>? = if (loads_modules) {
                            let implicit_config: map<string, root.std.Tuple2<root.value.Value, bool>> = {};
                            for (let scope in self.scopes) {
                                for (let k in scope.keys()) {
                                    let v = scope[k];
                                    let _ = implicit_config.set(
                                        normalize_var_name(k),
                                        root.std.Tuple2 { _0: v, _1: false },
                                    );
                                }
                            }
                            let old_pending = self.pending_config;
                            self.pending_config = implicit_config;
                            let old_consumed = self.consumed_config;
                            self.consumed_config = [];
                            let old_implicit = self.config_is_implicit;
                            self.config_is_implicit = true;
                            let old_id = self.pending_config_id;
                            self.pending_config_id = 0;
                            root.std.Tuple4 {
                                _0: old_pending,
                                _1: old_consumed,
                                _2: old_implicit,
                                _3: old_id,
                            }
                        } else {
                            null
                        };
                        let saved_clone: root.std.Tuple2<string, map<string, bool>>? = if (loads_modules) {
                            let n = self.copy_counter + 1;
                            self.copy_counter = n;
                            let old_clone = self.import_clone;
                            let visited: map<string, bool> = {};
                            self.import_clone = root.std.Tuple2 { _0: `#import${n}`, _1: visited };
                            old_clone
                        } else {
                            let old_clone = self.import_clone;
                            self.import_clone = null;
                            old_clone
                        };
                        // dart parses an imported file as a TOP-LEVEL
                        // stylesheet: a bare declaration there — even
                        // inside top-level control flow — is its parse
                        // error `expected "{".`, regardless of the
                        // @import sitting inside a rule (issue_2295).
                        // PORT: nested fn `has_top_decl` hoisted to
                        // `eval_imports__has_top_decl` (after `Evaluator`).
                        if (eval_imports__has_top_decl(sheet.stmts)) {
                            throw root.error.Error.unpositioned("expected \"{\".");
                        }
                        // The imported file's own `@import` deprecations
                        // fire now, as if at its parse (the per-location
                        // dedup makes a re-import of a cached file quiet,
                        // like dart's once-parsed stylesheet).
                        self.warn_import_rules(sheet.stmts);
                        // Render any error before the context restores
                        // below strip its attribution (the `@import`
                        // frame from above is still on the stack).
                        let result: root.error.Error? = null;
                        self.exec(sheet.stmts, parents, sink) catch (e) {
                            let e: root.error.Error => {
                                result = self.finalize_error(e);
                            }
                        };
                        self.leave_call(saved_member);
                        self.current_url = saved_import_url;
                        self.current_source = saved_import_source;
                        self.current_url_stamp = 0;
                        self.current_file_dir = saved_dir;
                        self.current_canonical = saved_canonical;
                        self.import_clone = saved_clone;
                        if (saved_pending_consumed != null) {
                            self.pending_config = saved_pending_consumed._0;
                            self.consumed_config = saved_pending_consumed._1;
                            self.config_is_implicit = saved_pending_consumed._2;
                            self.pending_config_id = saved_pending_consumed._3;
                        }
                        let imported_fwd = self.forwarded;
                        self.forwarded = saved_fwd;
                        self.used_modules = saved_used;
                        self.star_modules = saved_star;
                        self.used_user_modules = saved_used_user;
                        self.star_user_modules = saved_star_user;
                        self.loading.pop();
                        if (result != null) {
                            throw result;
                        }
                        // A `@forward`ed member from the imported file becomes
                        // an ordinary member of the importing scope: dart's
                        // @import is textual inclusion, so each forwarded
                        // callable rebinds to the IMPORT SITE's environment
                        // and lands in the innermost frame (a nested
                        // import's members stay scoped to the enclosing
                        // rule and pop with it).
                        if (self.scopes.length() == 1) {
                            for (let k in imported_fwd.functions.keys()) {
                                let f = imported_fwd.functions[k];
                                let rebound = self.recapture_callable(f);
                                self.define_function(k, rebound);
                            }
                            for (let k in imported_fwd.mixins.keys()) {
                                let m = imported_fwd.mixins[k];
                                let rebound = self.recapture_callable(m);
                                self.define_mixin(k, rebound);
                            }
                            let g = self.scopes.at(0);
                            if (g != null) {
                                for (let k in imported_fwd.vars.keys()) {
                                    let val = imported_fwd.vars[k];
                                    // The forwarded module's assignments
                                    // behave as if written at the import:
                                    // they overwrite an existing
                                    // user-defined global (`$a: shadowed;
                                    // @import "fwd"` sees the forwarded
                                    // value afterwards) — but a global a
                                    // previous forward-merge created stays
                                    // bound to its module, so re-importing
                                    // the SAME module must not clobber an
                                    // intervening assignment, while a
                                    // forward from a DIFFERENT module
                                    // overrides it (sass/dart-sass#888).
                                    // PORT: the source-module pointer is its `_id` (`""` = none).
                                    let src_ptr = imported_fwd.var_src.get(k) ?? "";
                                    match (self.forwarded_globals.get(k)) {
                                        let prev: string if prev == src_ptr => {
                                            let _ = g.get_or_insert(k, val);
                                        },
                                        _ => {
                                            let _ = self.forwarded_globals.set(k, src_ptr);
                                            let _ = g.set(k, val);
                                        },
                                    }
                                }
                            }
                        } else {
                            // A nested `@import`'s forwarded variables join
                            // the enclosing rule's scope (so a following
                            // nested import's implicit configuration sees
                            // them, and a local assignment updates them);
                            // its forwarded functions/mixins land in the
                            // innermost frame, scoped to the enclosing
                            // rule (they pop with it, like dart).
                            let s = root.std.last(self.scopes);
                            if (s != null) {
                                for (let k in imported_fwd.vars.keys()) {
                                    let _ = s.set(k, imported_fwd.vars[k]);
                                }
                            }
                            for (let k in imported_fwd.functions.keys()) {
                                let f = imported_fwd.functions[k];
                                let rebound = self.recapture_callable(f);
                                self.define_function(k, rebound);
                            }
                            for (let k in imported_fwd.mixins.keys()) {
                                let m = imported_fwd.mixins[k];
                                let rebound = self.recapture_callable(m);
                                self.define_mixin(k, rebound);
                            }
                        }
                    } else {
                        // dart names no url — the span points at it, all of
                        // it (`@import foo screen` carets ten characters).
                        throw root.error.Error.at("Can't find stylesheet to import.", pos).with_length(length);
                    }
                },
                _ => {},
            }
        }
    }
}

/// Nested `fn has_top_decl` of [`Evaluator::eval_imports`].
function eval_imports__has_top_decl(stmts: root.ast.Stmt[]) -> bool {
    stmts.some((s: root.ast.Stmt) -> bool {
        match (s) {
            root.ast.Stmt_Decl {} | root.ast.Stmt_PropertySet {} | root.ast.Stmt_CustomDecl {} => {
                true
            },
            let i: root.ast.Stmt_If => {
                i._0.some((b: root.ast.IfBranch) -> bool {
                    eval_imports__has_top_decl(b.body)
                })
            },
            root.ast.Stmt_For { body: let body }
                | root.ast.Stmt_Each { body: let body }
                | root.ast.Stmt_While { body: let body } =>
            {
                eval_imports__has_top_decl(body)
            },
            _ => false,
        }
    })
}

/// One frame of the diagnostic call stack: the call site (file + 1-based
/// position) and the name of the member that contained that call.
class DiagFrame {
    url: string,
    pos: root.scanner.Pos,
    /// The member name to print for this frame (`root stylesheet` or `name()`).
    member: string,
    /// Byte length of the call-site span, to size the snippet caret when this
    /// frame is the primary (innermost) one — used by `@error`.
    length: int,
    /// True for a `@content;` invocation: it appears in the trace, but a
    /// spanless `@error` never attaches to it — dart attaches at the nearest
    /// mixin or function call boundary, through any number of forwarded
    /// content blocks.
    content: bool,
    /// The text of the file the call site is in, for the snippet when this
    /// frame is an `@error`'s boundary. Carried rather than looked up by
    /// `url`: display names are not unique across custom importers.
    source: string,
}

/// An evaluated user module: its public members plus the bindings it itself
/// `@use`d (so a `ns.member` lookup can recurse through forwards).
class Module {
    /// Top-level variables (the module's global scope). Shared and mutable so an
    /// outside `ns.$var: value` assignment updates the module and its own
    /// functions/mixins observe the new value on their next call.
    vars: Scope,
    /// Definition spans for `vars`, in lockstep (dart's module `Environment`
    /// carries its `_variableNodes` the same way). Source-map only.
    var_spans: SpanScope,
    /// Top-level functions/mixins (the module's global frame). Shared by Rc
    /// with the chains the module's own callables captured, so they resolve
    /// each other (and forwarded members merged after evaluation).
    functions: FnScope,
    mixins: FnScope,
    /// Namespaced user modules this module `@use`d (for transitive `ns.fn()`
    /// calls evaluated inside this module's own functions/mixins).
    used_user_modules: map<string, Module>,
    star_user_modules: Module[],
    /// Built-in modules this module `@use`d, by namespace, and unprefixed.
    used_builtin_modules: map<string, string>,
    star_builtin_modules: string[],
    /// Built-in `sass:*` modules re-exported via `@forward`. A `ns.member` that
    /// misses every captured member is retried against these.
    forwarded_builtins: ForwardedBuiltin[],
    /// For members re-exported via `@forward`, the module they actually live
    /// in (the variable entry also carries the ORIGINAL name): reads, writes
    /// and calls route there so the defining module's environment is live.
    var_origins: map<string, root.std.Tuple2<Module, string>>,
    /// Like `var_origins`, but kept even when the module's own same-named
    /// variable SHADOWS the forwarded one: dart reads the own variable but a
    /// namespaced *assignment* still writes through to the forwarded module.
    var_write_origins: map<string, root.std.Tuple2<Module, string>>,
    fn_origins: map<string, Module>,
    mixin_origins: map<string, Module>,
    /// The identity of the original explicit configuration this module was
    /// first evaluated with (0 = none/implicit).
    config_origin: int,
    /// Whether this module's CSS has been emitted into the MAIN tree (an
    /// ordinary `@use`/`@forward` load). A module first loaded inside an
    /// `@import`/load-css clone has not — the next plain load emits it.
    emitted_main: bool,
    /// The module's emitted CSS, captured at first evaluation so an
    /// `@import`-reached module can re-emit it at each import site (dart
    /// clones the module's CSS tree per import).
    css: OutNode[],
    /// PORT: pointer identity. Rust compares modules with `Rc::as_ptr` (and keys
    /// `Forwarded::var_src`/`fn_src`/`mixin_src` and
    /// `Evaluator::forwarded_globals` by that pointer); BAML has no reference
    /// identity, so every module carries a unique id set from
    /// `root.std.fresh_id()` at construction. `""` plays the null pointer.
    _id: string,
    /// Look up a public variable. Names are dash/underscore-insensitive, so an
    /// exact miss falls back to comparing the canonical (dashed) form against
    /// every key. Private members (leading `-`/`_`) are the caller's
    /// responsibility to exclude.
    function var(self, name: string) -> root.value.Value? {
        // A forwarded member reads live from its defining module.
        let origin = self.var_origin(name);
        if (origin != null) {
            let m = origin._0;
            let oname = origin._1;
            return m.var(oname);
        }
        let vars = self.vars;
        let v = vars.get(name);
        if (v != null) {
            return v;
        }
        let norm = normalize_var_name(name);
        let k = vars.keys().find((k) -> {
            normalize_var_name(k) == norm
        });
        if (k != null) {
            vars.get(k)
        } else {
            null
        }
    }

    /// The defining module (and original variable name) of a forwarded
    /// variable, dash/underscore-insensitively.
    function var_origin(self, name: string) -> root.std.Tuple2<Module, string>? {
        let found = self.var_origins.get(name);
        if (found != null) {
            return root.std.Tuple2 { _0: found._0, _1: found._1 };
        }
        let norm = normalize_var_name(name);
        let k = self.var_origins.keys().find((k) -> {
            normalize_var_name(k) == norm
        });
        if (k != null) {
            let mo = self.var_origins[k];
            root.std.Tuple2 { _0: mo._0, _1: mo._1 }
        } else {
            null
        }
    }

    /// The write-through target of a forwarded variable (kept even when
    /// shadowed by the module's own same-named variable).
    function var_write_origin(self, name: string) -> root.std.Tuple2<Module, string>? {
        let found = self.var_write_origins.get(name);
        if (found != null) {
            return root.std.Tuple2 { _0: found._0, _1: found._1 };
        }
        let norm = normalize_var_name(name);
        let k = self.var_write_origins.keys().find((k) -> {
            normalize_var_name(k) == norm
        });
        if (k != null) {
            let mo = self.var_write_origins[k];
            root.std.Tuple2 { _0: mo._0, _1: mo._1 }
        } else {
            null
        }
    }

    /// The defining module of a forwarded function/mixin.
    function fn_origin(self, name: string) -> Module? {
        let m = self.fn_origins.get(name);
        if (m != null) {
            return m;
        }
        let norm = normalize_var_name(name);
        let k = self.fn_origins.keys().find((k) -> {
            normalize_var_name(k) == norm
        });
        if (k != null) {
            self.fn_origins.get(k)
        } else {
            null
        }
    }

    function mixin_origin(self, name: string) -> Module? {
        let m = self.mixin_origins.get(name);
        if (m != null) {
            return m;
        }
        let norm = normalize_var_name(name);
        let k = self.mixin_origins.keys().find((k) -> {
            normalize_var_name(k) == norm
        });
        if (k != null) {
            self.mixin_origins.get(k)
        } else {
            null
        }
    }

    function function_(self, name: string) -> UserCallable? {
        let fns = self.functions;
        let f = fns.get(name);
        if (f != null) {
            return f;
        }
        let norm = normalize_var_name(name);
        let k = fns.keys().find((k) -> {
            normalize_var_name(k) == norm
        });
        if (k != null) {
            fns.get(k)
        } else {
            null
        }
    }

    function mixin(self, name: string) -> UserCallable? {
        let mixins = self.mixins;
        let m = mixins.get(name);
        if (m != null) {
            return m;
        }
        let norm = normalize_var_name(name);
        let k = mixins.keys().find((k) -> {
            normalize_var_name(k) == norm
        });
        if (k != null) {
            mixins.get(k)
        } else {
            null
        }
    }
}

/// A `@content` block plus, when the enclosing `@include` targets a mixin from
/// another module, a snapshot of the call-site environment in which the content
/// must run (dart-sass: a content block closes over its definition site).
class ContentBlock {
    stmts: root.ast.Stmt[],
    /// The `using (params)` clause's parameters; `@content(args)` binds its
    /// arguments to these before the block runs.
    params: root.ast.ParamList?,
    /// `Some` only for a cross-module include: the environment to install while
    /// the block runs, so the content resolves against the call site, not the
    /// mixin's module.
    caller_env: SavedModuleEnv?,
    /// The file the block was written in (the `@include` site's file). The
    /// block runs against it — dart's `@content` frame names the includer's
    /// file, and the block's output maps there — not against the mixin's.
    origin: root.value.MixinOrigin?,
}

/// The caller-side environment saved while a cross-module member call runs in
/// the callee module's environment.
class SavedModuleEnv {
    scopes: Scope[],
    /// Definition spans parallel to `scopes` (source-map only).
    var_spans: SpanScope[],
    scope_semi_global: bool[],
    functions: FnFrame[],
    mixins: FnFrame[],
    used_modules: map<string, string>,
    star_modules: string[],
    used_user_modules: map<string, Module>,
    star_user_modules: Module[],
    /// When set (a cross-module call), the module whose global scope was
    /// installed: `leave_module` writes the (possibly mutated) global scope back
    /// so a `!global` assignment inside the module persists.
    write_back: Module?,
}

/// Members a module re-exports via `@forward`, accumulated while it evaluates.
class Forwarded {
    vars: map<string, root.value.Value>,
    /// Definition spans for `vars`, keyed identically (source-map only): a
    /// forwarded variable keeps pointing at the `$x: <value>` that defined it
    /// in its home module.
    var_spans: map<string, VarSpan>,
    functions: map<string, UserCallable>,
    mixins: map<string, UserCallable>,
    /// The module each re-exported member actually lives in (with the
    /// member's ORIGINAL name for variables), so calls/assignments through
    /// the forward run against the defining module's environment.
    var_origins: map<string, root.std.Tuple2<Module, string>>,
    fn_origins: map<string, Module>,
    mixin_origins: map<string, Module>,
    /// Built-in `sass:*` modules re-exported via `@forward "sass:x"`.
    builtins: ForwardedBuiltin[],
    /// For each re-exported member name, the source module it came from (by
    /// pointer). Re-forwarding the SAME module is idempotent (no conflict);
    /// forwarding a same-named member from a DIFFERENT module is a conflict.
    /// PORT: `*const Module` -> the module's `_id` (see [`Module::_id`]).
    var_src: map<string, string>,
    fn_src: map<string, string>,
    mixin_src: map<string, string>,

    /// derive(Default)
    function default() -> Forwarded {
        Forwarded {
            vars: {},
            var_spans: {},
            functions: {},
            mixins: {},
            var_origins: {},
            fn_origins: {},
            mixin_origins: {},
            builtins: [],
            var_src: {},
            fn_src: {},
            mixin_src: {},
        }
    }
}

/// A built-in module re-exported via `@forward "sass:x" [as p-*] [show|hide ...]`,
/// possibly through further `@forward`s of the module that wrote that rule.
class ForwardedBuiltin {
    module: string,
    /// One entry per `@forward` the member passed through, innermost first.
    filters: ForwardFilter[],
    /// The full prefix the member is exported under.
    function prefix(self) -> string {
        root.std.last(self.filters)?.prefix ?? ""
    }

    /// Whether a re-exported built-in member (given by its bare, un-prefixed
    /// name) survives every `@forward` it passed through.
    function visible(self, bare: string, kind: ForwardKind) -> bool {
        self.filters.every((f) -> {
            let exported = `${f.prefix}${bare}`;
            // PORT: `let (show, hide) = match kind { … }` -> one match per binding.
            let show = match (kind) {
                ForwardKind.Name => f.show,
                ForwardKind.Var => f.show_vars,
            };
            let hide = match (kind) {
                ForwardKind.Name => f.hide,
                ForwardKind.Var => f.hide_vars,
            };
            if (f.has_show) {
                show?.has(exported) ?? false
            } else {
                !(hide?.has(exported) ?? false)
            }
        })
    }
}

/// The `show`/`hide` clause of one `@forward` in a chain, together with the
/// prefix the member is exported under at that point. dart matches `show`/`hide`
/// against the member's name AS THAT RULE EXPORTS IT — `@forward "sass:map" as
/// p-* hide p-get` hides `p-get`, not `get` — which is what the prefix is for.
class ForwardFilter {
    /// The accumulated prefix at this level, canonical and possibly empty.
    prefix: string,
    /// Whether the rule had a `show` clause at all: one that names only
    /// variables still hides every function and mixin.
    has_show: bool,
    /// `show`/`hide` lists of exported function and mixin names.
    show: map<string, bool>?,
    hide: map<string, bool>?,
    /// The same, for the `$variable` entries of those clauses.
    show_vars: map<string, bool>?,
    hide_vars: map<string, bool>?,
}

/// Which kind of member a forwarded-built-in lookup is for: `show`/`hide`
/// name variables separately from functions and mixins.
enum ForwardKind {
    Name,
    Var,
}

/// A pending `@extend`, captured during eval and applied after flattening.
class PendingExtend {
    /// The resolved target simple selector (e.g. `.foo`, `%bar`).
    target: root.selector.Simple,
    /// The resolved target selector string, for error messages.
    target_str: string,
    /// The enclosing rule's resolved selector list (the extenders), shared with
    /// the rule that registered this `@extend` — see
    /// [`Evaluator::current_selector`].
    extenders: string[],
    /// Source line-break flags parallel to `extenders` (an extend product
    /// inherits its extender's flag, dart's ComplexSelector.lineBreak).
    extender_breaks: bool[],
    optional: bool,
    /// Whether this `@extend` was registered inside a `@media` context.
    in_media: bool,
    /// The canonical key of the module this `@extend` was written in
    /// (empty for the root stylesheet).
    origin: string,
    pos: root.scanner.Pos,
}

/// Whether a calc space-list item is a substitution that makes the unparsed
/// run legal: a `#{…}` interpolation, or a `var()`/`env()` reference (which
/// the parser lowers to an [`Expr::Ident`] whose text begins with `var(`/
/// `env(`, possibly after a vendor prefix). A plain ident, number, nested
/// calc, or variable is NOT a substitution.
/// Whether a property-name template begins, *literally*, with `--` (a custom
/// property). A name whose first piece is `#{…}` interpolation is not literal,
/// so `#{--b}` is allowed to namespace inside a property set while a written
/// `--b` is not.
function literal_name_is_custom_property(property: root.ast.TplPiece[]) -> bool {
    match (property.at(0)) {
        root.ast.TplPiece_Lit { _0: let s } => root.std.trim_start(s).starts_with("--"),
        _ => false,
    }
}

function expr_has_substitution(e: root.ast.Expr) -> bool {
    match (e) {
        root.ast.Expr_Interp {} => true,
        // `var()`/`env()` are parsed as plain function calls; inside a calc
        // space-list they are legal substitutions (`calc(var(--c) 1)`).
        let f: root.ast.Expr_Func => {
            root.std.eq_ignore_ascii_case(f.name, "var")
                || root.std.eq_ignore_ascii_case(f.name, "env")
        },
        let id: root.ast.Expr_Ident => {
            id._0.some((p: root.ast.TplPiece) -> bool {
                match (p) {
                    root.ast.TplPiece_Interp {} => true,
                    let l: root.ast.TplPiece_Lit => {
                        let lower = root.std.ascii_lower(root.std.trim_start(l._0));
                        lower.starts_with("var(") || lower.starts_with("env(")
                    },
                    _ => false,
                }
            })
        },
        _ => false,
    }
}

/// Whether an expression tree contains a calculation substitution — a
/// `var()`/`env()` reference or an interpolation — anywhere within it
/// (recursing through operations, parentheses, nested calculations, and
/// lists). Used to decide whether a legacy global math function such as `abs()`
/// is being used as a CSS calculation (so its argument is preserved) rather
/// than as the deprecated Sass global.
function expr_contains_calc_substitution(e: root.ast.Expr) -> bool {
    if (expr_has_substitution(e)) {
        return true;
    }
    match (e) {
        let b: root.ast.Expr_Binary => {
            expr_contains_calc_substitution(b.lhs) || expr_contains_calc_substitution(b.rhs)
        },
        let d: root.ast.Expr_Div => {
            expr_contains_calc_substitution(d.lhs) || expr_contains_calc_substitution(d.rhs)
        },
        let u: root.ast.Expr_Unary => expr_contains_calc_substitution(u.operand),
        let p: root.ast.Expr_Paren => expr_contains_calc_substitution(p._0),
        let c: root.ast.Expr_Calc => expr_contains_calc_substitution(c.inner),
        let l: root.ast.Expr_List => {
            l.items.some((x: root.ast.Expr) -> bool {
                expr_contains_calc_substitution(x)
            })
        },
        _ => false,
    }
}

/// Collect the names of every `$var: ... !global` declaration nested inside
/// block statements (rules, conditionals, loops, mixins are NOT entered —
/// dart-sass registers slots for statically visible nested globals in rules
/// and control flow). Top-level declarations register themselves on
/// evaluation.
function collect_global_var_decls(stmts: root.ast.Stmt[], out: string[]) -> void {
    for (let stmt in stmts) {
        match (stmt) {
            let v: root.ast.Stmt_VarDecl if v._0.is_global && v._0.namespace == null => {
                out.push(v._0.name);
            },
            let r: root.ast.Stmt_Rule => {
                collect_global_var_decls(r._0.body, out);
            },
            let i: root.ast.Stmt_If => {
                for (let b in i._0) {
                    collect_global_var_decls(b.body, out);
                }
            },
            root.ast.Stmt_For { body: let body }
                | root.ast.Stmt_Each { body: let body }
                | root.ast.Stmt_While { body: let body }
                | root.ast.Stmt_Media { body: let body }
                | root.ast.Stmt_Supports { body: let body }
                | root.ast.Stmt_AtRoot { body: let body }
                | root.ast.Stmt_Keyframes { body: let body } =>
            {
                collect_global_var_decls(body, out);
            },
            // PORT: `Stmt::AtRule { body: Some(b), .. }` → bind the variant, then test the body.
            let a: root.ast.Stmt_AtRule => {
                let b = a.body;
                if (b != null) {
                    collect_global_var_decls(b, out);
                }
            },
            _ => {},
        }
    }
}

/// Nest module CSS under the style rule enclosing an `@import` (descendant
/// join on every top-level rule, recursing into at-rule bodies). dart-sass
/// clones the module's CSS into the current parent; a top-level import
/// (`parents` empty) passes through unchanged.
function reparent_nodes(nodes: OutNode[], parents: string[]) -> OutNode[] {
    if (parents.length() == 0) {
        return nodes;
    }
    // A rule whose selector contains a parent reference `&` keeps native
    // CSS-nesting semantics: it nests VERBATIM inside one leading
    // parent-selector shell instead of the descendant join (dart `nestWithin`
    // with `preserveParentSelectors` — through_load_css:top_level_parent).
    let preserved: OutItem[] = [];
    let rest: OutNode[] = [];
    for (let n in nodes) {
        match (n) {
            let r: OutNode_Rule => {
                let selectors = r.selectors.into_strings();
                if (
                    selectors.some((s: string) -> bool {
                        part_has_parent_ref(s)
                    })
                ) {
                    preserved.push(
                        OutItem_NestedRule {
                            selectors: selectors,
                            linebreaks: r.linebreaks,
                            items: r.items,
                            lines: r.lines,
                        },
                    );
                } else {
                    rest.push(
                        OutNode_Rule {
                            selectors: RuleSelectors_Raw {
                                _0: parents.flat_map((p: string) -> string[] {
                                    selectors.map((s: string) -> string {
                                        `${p} ${s}`
                                    })
                                }),
                            },
                            linebreaks: [],
                            items: r.items,
                            lines: r.lines,
                            extend_base: r.extend_base,
                        },
                    );
                }
            },
            let a: OutNode_AtRule => {
                rest.push(
                    OutNode_AtRule {
                        name: a.name,
                        prelude: a.prelude,
                        body: reparent_nodes(a.body, parents),
                        has_block: a.has_block,
                        kind: a.kind,
                        lines: a.lines,
                    },
                );
            },
            let other => {
                rest.push(other);
            },
        }
    }
    let out: OutNode[] = [];
    if (preserved.length() != 0) {
        out.push(
            OutNode_plain_rule(root.std.clone_vec(parents), preserved, root.ast.SrcLines.default()),
        );
    }
    root.std.extend(out, rest);
    out
}

/// Whether an expression contains a SassScript-only operator (`%`, a
/// comparison, boolean logic) that can never appear in a CSS calculation.
/// dart-sass's parser then treats the whole call as a plain function rather
/// than a calculation (`round(7 % 3, 1)` is the legacy one-argument
/// `math.round` — an arity error).
function expr_has_non_calc_op(e: root.ast.Expr) -> bool {
    match (e) {
        let b: root.ast.Expr_Binary => {
            let is_non_calc = match (b.op) {
                root.ast.BinOp.Mod
                    | root.ast.BinOp.Eq
                    | root.ast.BinOp.Neq
                    | root.ast.BinOp.Lt
                    | root.ast.BinOp.Gt
                    | root.ast.BinOp.Le
                    | root.ast.BinOp.Ge
                    | root.ast.BinOp.And
                    | root.ast.BinOp.Or
                    | root.ast.BinOp.SingleEq =>
                {
                    true
                },
                _ => false,
            };
            is_non_calc || expr_has_non_calc_op(b.lhs) || expr_has_non_calc_op(b.rhs)
        },
        let d: root.ast.Expr_Div => expr_has_non_calc_op(d.lhs) || expr_has_non_calc_op(d.rhs),
        let u: root.ast.Expr_Unary => expr_has_non_calc_op(u.operand),
        let p: root.ast.Expr_Paren => expr_has_non_calc_op(p._0),
        let l: root.ast.Expr_List => {
            l.items.some((x: root.ast.Expr) -> bool {
                expr_has_non_calc_op(x)
            })
        },
        _ => false,
    }
}

/// The inspect-style spelling of a value rejected from a calculation, for
/// dart-sass's "Value … can't be used in a calculation." error. `null`
/// spells out as `null`, a list is parenthesized (`(1 2 3)`, `(1, 2)`); every
/// other type matches its plain CSS form (`true`, `blue`, `"foo"`, `(b: c)`).
function calc_value_repr(v: root.value.Value) -> string {
    match (v) {
        root.value.Value_Null {} => "null",
        root.value.Value_List {} => `(${v.to_css(false)})`,
        let other => other.to_css(false),
    }
}

/// Resolve a calc() numeric constant from its (unquoted) ident spelling,
/// case-insensitively: `pi`, `e`, `infinity`/`-infinity`, and `nan`. Returns
/// `None` for any other identifier, which is then kept verbatim.
function calc_constant(text: string) -> float? {
    match (root.std.ascii_lower(text)) {
        "pi" => root.std.F64_PI(),
        "e" => root.std.F64_E(),
        "infinity" => root.std.F64_INFINITY(),
        "-infinity" => root.std.F64_NEG_INFINITY(),
        "nan" => root.std.F64_NAN(),
        _ => null,
    }
}

/// Whether `s` is exactly one complete CSS-calculation function call —
/// `name(...)` for a recognized calculation function, with the closing paren
/// at the very end (balanced, nothing trailing). Used so that a `calc()`
/// wrapping a single already-complete calculation (`calc(min(1%, 2px))`)
/// drops its redundant outer `calc()`, matching dart-sass. A non-calculation
/// leaf (`var(--x)`, an unknown function) keeps its wrapper.
/// Whether a single-string operand produced by a *nested* `calc()` must be
/// wrapped in parentheses when spliced into the surrounding calculation.
///
/// dart-sass keeps a nested calc's unresolved interpolation/`var()` operand
/// grouped (`calc(calc(#{"c*"}))` -> `calc((c*))`, `calc(1 + calc(var(--c)))`
/// -> `calc(1 + (var(--c)))`), but a clean single token flattens bare
/// (`calc(calc(c))` -> `calc(c)`, `calc(calc(c-d))` -> `calc(c-d)`). The
/// operand needs grouping when it is not already a complete sub-calculation
/// (`min(…)`, `clamp(…)`, …) and either contains a character that would be
/// ambiguous unparenthesized — whitespace, `*`, `/`, or `\` — or is a `var()`
/// substitution (which dart-sass always treats as an opaque group).
function nested_calc_needs_parens(s: string) -> bool {
    if (is_complete_calculation(s)) {
        return false;
    }
    let trimmed = root.std.trim_start(s);
    let is_var = trimmed.length() >= 4 && root.std.eq_ignore_ascii_case(trimmed.slice(0, 4), "var(");
    is_var
        || root.std.any_char(s, (c: string) -> bool {
            root.std.is_whitespace(c) || c == "*" || c == "/" || c == "\\"
        })
}

function is_complete_calculation(s: string) -> bool {
    let s = root.std.trim(s);
    let open = s.index_of("(");
    if (open == null) {
        return false;
    }
    if (!s.ends_with(")")) {
        return false;
    }
    let name = root.std.ascii_lower(root.std.trim(s.slice(0, open)));
    let is_calc_name = match (name) {
        "calc"
            | "min"
            | "max"
            | "clamp"
            | "round"
            | "mod"
            | "rem"
            | "sin"
            | "cos"
            | "tan"
            | "asin"
            | "acos"
            | "atan"
            | "atan2"
            | "pow"
            | "sqrt"
            | "exp"
            | "log"
            | "hypot"
            | "abs"
            | "sign"
            | "calc-size" =>
        {
            true
        },
        _ => false,
    };
    if (!is_calc_name) {
        return false;
    }
    // The opening paren must match the final paren (one balanced call that
    // spans the whole string), so `min(1%, 2px)` qualifies but
    // `min(1%, 2px) + min(…)` (extra trailing content) does not.
    let depth = 0;
    // PORT: `char_indices()` → a char counter; `)` is one byte, so the
    // "last byte" test is "last char".
    let cs = s.chars();
    let i = 0;
    for (let c in cs) {
        match (c) {
            "(" => {
                depth += 1;
            },
            ")" => {
                depth -= 1;
                if (depth == 0) {
                    return i == cs.length() - 1;
                }
            },
            _ => {},
        }
        i += 1;
    }
    false
}

/// Convert an evaluated value into a calc operand node. Numbers stay numeric
/// (and can fold); everything else becomes an opaque string token preserved
/// verbatim.
function value_to_calc_node(v: root.value.Value) -> root.value.CalcNode {
    match (v.without_slash()) {
        let n: root.value.Value_Number => root.value.CalcNode_Number { _0: n._0 },
        let c: root.value.Value_Calc => c._0,
        let other => root.value.CalcNode_Str { _0: other.to_css(false) },
    }
}

/// Fold a calc operation: combine two compatible numbers into one; raise
/// dart-sass's incompatible-units error for two known-but-cross-dimension
/// operands of `+`/`-`; otherwise keep the operation for canonical
/// serialization. Only the immediate numeric operands are considered, like
/// dart-sass's limited simplification.
function fold_calc(
    op: root.value.CalcOp,
    left: root.value.CalcNode,
    right: root.value.CalcNode,
    pos: root.scanner.Pos,
) -> root.value.CalcNode {
    if let a: root.value.CalcNode_Number = left {
        if let b: root.value.CalcNode_Number = right {
            let n = fold_numbers(op, a._0, b._0, pos);
            if (n != null) {
                return root.value.CalcNode_Number { _0: n };
            }
        }
    }
    // An addition/subtraction operand that is a purely-numeric multiplication of
    // two unit operands (a compound unit like `1px * 1px`) or a division by a
    // unit operand (an inverse unit like `1 / 1px`) is a number with complex
    // units, which CSS calculations cannot mix into a sum. dart-sass rejects it
    // ("Number calc(1px * 1px) isn't compatible with CSS calculations."). A
    // standalone `calc(1px * 1px)` is fine — only the `+`/`-` context checks.
    if (op == root.value.CalcOp.Add || op == root.value.CalcOp.Sub) {
        for (let operand in [left, right]) {
            let node = calc_complex_unit_operand(operand);
            if (node != null) {
                throw root.error.Error.at(
                    `Number calc(${node.to_calc_css(false)}) isn't compatible with CSS calculations.`,
                    pos,
                );
            }
        }
    }
    root.value.CalcNode_Op { op: op, left: left, right: right }
}

/// If `node` is a purely-numeric calc operation that produces a number with
/// complex units — a multiplication of two unit-bearing numeric operands
/// (`1px * 1px`), or a division whose denominator carries a unit (`1 / 1px`) —
/// return the offending node. An operation involving a `var()`/interpolation
/// (opaque) operand is not a resolved number and is left preserved, so it never
/// triggers this check.
function calc_complex_unit_operand(node: root.value.CalcNode) -> root.value.CalcNode? {
    match (node) {
        root.value.CalcNode_Op { op: root.value.CalcOp.Mul, left: let left, right: let right }
            if calc_node_carries_unit(left) && calc_node_carries_unit(right) => node,
        root.value.CalcNode_Op { op: root.value.CalcOp.Div, right: let right }
            if calc_node_carries_unit(right) => node,
        _ => null,
    }
}

/// Whether a resolved (no opaque operand) calc node carries a real unit: a
/// unit-bearing number, or a `*`/`/` chain of such numbers. A node containing a
/// `var()`/interpolation is opaque (unknown unit) and reported as not carrying
/// a unit, so it does not count toward a compound/inverse unit.
function calc_node_carries_unit(node: root.value.CalcNode) -> bool {
    match (node) {
        let n: root.value.CalcNode_Number => !n._0.is_unitless(),
        root.value.CalcNode_Str {} => false,
        let o: root.value.CalcNode_Op
            if o.op == root.value.CalcOp.Mul || o.op == root.value.CalcOp.Div => {
            calc_node_carries_unit(o.left) || calc_node_carries_unit(o.right)
        },
        root.value.CalcNode_Op {} => false,
        // A nested calculation function has no single determinable unit here.
        root.value.CalcNode_Func {} => false,
        _ => false,
    }
}

/// Try to combine two numbers under a calc operator.
///
/// `Ok(Some(n))` folds them; `Ok(None)` preserves the operation verbatim;
/// `Err` is dart-sass's "<a> and <b> are incompatible." rejection.
///
/// For `+`/`-` dart-sass folds equal units and convertible units (converting
/// the right into the left), but — unlike Sass arithmetic — treats a unitless
/// operand mixed with any real unit as an error, and rejects two known
/// absolute units of different dimensions (`1px + 1s`). Two distinct units
/// where at least one is relative/unknown (`1px + 1vw`, `100% - 10px`) or
/// that share a class but are not convertible (`1khz + 1hz`) are preserved.
///
/// `*`/`/` always fold, with dart-sass unit cancellation: a compound result
/// (`6px * 1s` -> `6px*s`) is a single multi-unit number whose calc
/// serialization spells the units back out as operands.
function fold_numbers(
    op: root.value.CalcOp,
    a: root.value.Number,
    b: root.value.Number,
    pos: root.scanner.Pos,
) -> root.value.Number? {
    match (op) {
        root.value.CalcOp.Add | root.value.CalcOp.Sub => {
            let apply = (x: float, y: float) -> float {
                if (op == root.value.CalcOp.Add) {
                    x + y
                } else {
                    x - y
                }
            };
            // A multi-unit operand folds against convertible unit lists;
            // anything else is dart-sass's "isn't compatible with CSS
            // calculations." rejection (quoting the first complex operand).
            if (a.has_complex_units() || b.has_complex_units()) {
                let factor = root.value.unit_lists_factor(
                    root.std.Tuple2 { _0: b.numer_units(), _1: b.denom_units() },
                    root.std.Tuple2 { _0: a.numer_units(), _1: a.denom_units() },
                );
                if (factor != null) {
                    return a.copy_units(apply(a.value, b.value * factor));
                }
                let complex = if (a.has_complex_units()) {
                    a
                } else {
                    b
                };
                throw root.error.Error.at(
                    `Number ${complex.to_css(false)} isn't compatible with CSS calculations.`,
                    pos,
                );
            }
            // Identical units (incl. `%`, relative units, both unitless)
            // fold; dart compares unit names exactly (`PX` != `px`).
            if (a.unit() == b.unit()) {
                return a.copy_units(apply(a.value, b.value));
            }
            // A unitless operand mixed with a real unit is an error in calc.
            if (a.is_unitless() || b.is_unitless()) {
                throw calc_incompatible(a, b, pos);
            }
            // Two distinct real units: convert when in the same convertible
            // group; error when both are known but cross-dimension; otherwise
            // preserve (a relative/unknown unit is involved).
            let factor = root.value.convert_factor(b.unit(), a.unit());
            if (factor != null) {
                a.copy_units(apply(a.value, b.value * factor))
            } else if (root.value.calc_units_incompatible(a.unit(), b.unit())) {
                throw calc_incompatible(a, b, pos)
            } else {
                null
            }
        },
        root.value.CalcOp.Mul => a.mul(b),
        root.value.CalcOp.Div => a.div(b),
    }
}

/// dart-sass's `calc()` incompatible-units error (note: "are incompatible.",
/// distinct from the arithmetic "have incompatible units." wording).
function calc_incompatible(
    a: root.value.Number,
    b: root.value.Number,
    pos: root.scanner.Pos,
) -> root.error.Error {
    root.error.Error.at(`${a.to_css(false)} and ${b.to_css(false)} are incompatible.`, pos)
}

/// The declaration scope a statement is nested in, for validating that
/// `@function`/`@mixin` declarations appear only where dart-sass allows them.
enum DeclScope {
    /// Top level, a style rule, or a plain at-rule (`@media`): declarations OK.
    Allowed,
    /// Inside `@if`/`@each`/`@for`/`@while` (propagates through style rules).
    Control,
    /// Inside a `@function` body.
    Function,
    /// Inside a `@mixin` body.
    Mixin,
}

/// The lexical context a statement is nested in, used to statically reject
/// misplaced statements exactly like dart-sass — *before* evaluation, so even
/// an unexecuted `@if false { … }` branch is validated.
class ScopeCtx {
    /// `@function`/`@mixin`/control declaration scope (see [`DeclScope`]).
    decl: DeclScope,
    /// Lexically inside a style rule (dart-sass's parser `_inStyleRule`). Set by
    /// [`Stmt::Rule`]; preserved through `@media`/`@supports`/`@keyframes`/
    /// generic at-rules and control directives. Governs where `@extend` may
    /// appear lexically.
    in_style_rule: bool,
    /// Inside an `@at-root` body or an `@include` content block: the lexical
    /// `@extend` placement check is deferred to the evaluator, which checks the
    /// *runtime* style-rule context (the `@at-root` query and the include site
    /// determine whether a style rule survives — neither is knowable statically).
    /// All other validations still apply.
    defer_extend: bool,
    function root() -> ScopeCtx {
        ScopeCtx { decl: DeclScope.Allowed, in_style_rule: false, defer_extend: false }
    }

    function with(self, decl: DeclScope) -> ScopeCtx {
        ScopeCtx { ...self, decl: decl }
    }
}

/// Reject statements nested where dart-sass forbids them. Runs once after
/// parsing, so an unexecuted `@while (false) { @function … }` still errors (it
/// is a compile-time, not run-time, restriction). Covers:
/// - `@function`/`@mixin` declarations in control/function/mixin bodies;
/// - the full set of statements illegal inside a `@function` body (style rules,
///   declarations, and everything that isn't a var assignment / control flow /
///   `@return` / `@warn` / `@debug` / `@error`);
/// - `@content` outside a `@mixin` declaration;
/// - `@extend` outside a style rule or mixin.
function validate_declarations(sheet: root.ast.Stylesheet) -> void {
    validate_decl_scope(sheet.stmts, ScopeCtx.root())
}

function validate_decl_scope(stmts: root.ast.Stmt[], ctx: ScopeCtx) -> void {
    let scope = ctx.decl;
    for (let stmt in stmts) {
        // Inside a `@function` body dart-sass only permits variable
        // assignments, control flow, `@return`, `@warn`/`@debug`/`@error`, and
        // comments. Reject the rest here (with dart's precedence ordering)
        // before the generic per-statement handling below.
        if (scope == DeclScope.Function) {
            match (stmt) {
                // The indented-syntax parser can attach a function header's
                // parameter list on a continuation line (`@function a\n  ()`) as
                // a spurious empty-`()` "style rule" in the body. dart-sass reads
                // it as the (empty) parameter list, not a rule — and `()` is not
                // a valid selector dart would ever produce — so this artifact is
                // not a real style rule. Skip it; a genuine rule is rejected.
                let r: root.ast.Stmt_Rule if is_empty_parens_selector(r._0.selector) => {},
                root.ast.Stmt_Rule {} => {
                    throw root.error.Error.unpositioned(
                        "@function rules may not contain style rules.",
                    );
                },
                root.ast.Stmt_Decl {} | root.ast.Stmt_CustomDecl {} | root.ast.Stmt_PropertySet {} => {
                    throw root.error.Error.unpositioned(
                        "@function rules may not contain declarations.",
                    );
                },
                // Allowed in a function body: keep walking (control flow) or
                // accept verbatim (assignments / `@return` / diagnostics /
                // comments). Function/mixin definitions fall through to the
                // declaration check below, which already yields dart's
                // "This at-rule is not allowed here." for a nested function.
                root.ast.Stmt_VarDecl {}
                    | root.ast.Stmt_Return {}
                    | root.ast.Stmt_Warn {}
                    | root.ast.Stmt_Debug {}
                    | root.ast.Stmt_Error {}
                    | root.ast.Stmt_Comment {}
                    | root.ast.Stmt_If {}
                    | root.ast.Stmt_For {}
                    | root.ast.Stmt_Each {}
                    | root.ast.Stmt_While {}
                    | root.ast.Stmt_FunctionDef {}
                    | root.ast.Stmt_MixinDef {} =>
                {},
                // An `@import` is rejected with its span (dart underlines the
                // rule); the generic arm below would lose it.
                let imp: root.ast.Stmt_Import => {
                    let e = root.error.Error.at("This at-rule is not allowed here.", imp.pos);
                    e.length = imp.length;
                    throw e;
                },
                // Anything else (@extend, @content, @include, @media, @at-root,
                // @use, @charset, generic at-rules, …) is rejected.
                _ => {
                    throw root.error.Error.unpositioned(
                        "This at-rule is not allowed here.",
                    );
                },
            }
        }
        match (stmt) {
            let c: root.ast.Stmt_FunctionDef => {
                let msg = decl_error(scope, "function");
                if (msg != null) {
                    throw root.error.Error.unpositioned(msg);
                }
                validate_decl_scope(c._0.body, ctx.with(DeclScope.Function));
            },
            let c: root.ast.Stmt_MixinDef => {
                let msg = decl_error(scope, "mixin");
                if (msg != null) {
                    throw root.error.Error.unpositioned(msg);
                }
                validate_decl_scope(c._0.body, ctx.with(DeclScope.Mixin));
            },
            // `@content` is only legal lexically within a `@mixin` declaration
            // (directly or nested through style rules / control / at-rules). The
            // `decl` scope is `Mixin` throughout a mixin body, so testing it
            // captures every nesting. (Inside a `@function` the earlier guard
            // already emitted "This at-rule is not allowed here.".)
            root.ast.Stmt_Content {} if scope != DeclScope.Mixin => {
                throw root.error.Error.unpositioned(
                    "@content is only allowed within mixin declarations.",
                );
            },
            // `@extend` applies at the include site, so lexically it is legal
            // only within a style rule or a mixin. Elsewhere — top level, or a
            // control directive not inside a style rule — dart-sass errors at
            // parse time. (Inside a `@function` the earlier guard wins; inside
            // an `@at-root` body or an `@include` content block the check is
            // deferred to the evaluator — see `defer_extend`.)
            root.ast.Stmt_Extend {}
                if !ctx.defer_extend && !ctx.in_style_rule && scope != DeclScope.Mixin => {
                throw root.error.Error.unpositioned(
                    "@extend may only be used within style rules.",
                );
            },
            // Control directives establish (or keep) the control/function/mixin
            // scope; a `@function`/`@mixin` body's scope sticks through them.
            // They preserve the enclosing `in_style_rule` flag.
            let i: root.ast.Stmt_If => {
                let inner = ctx.with(enter_control(scope));
                for (let b in i._0) {
                    validate_decl_scope(b.body, inner);
                }
            },
            root.ast.Stmt_For { body: let body }
                | root.ast.Stmt_Each { body: let body }
                | root.ast.Stmt_While { body: let body } =>
            {
                validate_decl_scope(body, ctx.with(enter_control(scope)));
            },
            // A style rule establishes the style-rule context for `@extend`.
            let r: root.ast.Stmt_Rule => {
                validate_decl_scope(r._0.body, ScopeCtx { ...ctx, in_style_rule: true });
            },
            // `@at-root` runs its body at the document root: whether a style
            // rule survives depends on the (runtime-evaluated) `with`/`without`
            // query, so defer the `@extend` placement check to the evaluator.
            // A nested style rule inside the body re-establishes `in_style_rule`
            // for its own descendants (handled by the `Stmt::Rule` arm).
            let a: root.ast.Stmt_AtRoot => {
                validate_decl_scope(a.body, ScopeCtx { ...ctx, defer_extend: true });
            },
            // Plain at-rules / `@media` / `@supports` / `@keyframes` preserve
            // both the declaration scope and the style-rule context.
            // PORT: `Stmt::AtRule { body: Some(body), .. }` / `InterpAtRule` →
            // bind the variant, then test the body (a `None` body matches no
            // other arm either).
            let a: root.ast.Stmt_AtRule => {
                let body = a.body;
                if (body != null) {
                    validate_decl_scope(body, ctx);
                }
            },
            let a: root.ast.Stmt_InterpAtRule => {
                let body = a.body;
                if (body != null) {
                    validate_decl_scope(body, ctx);
                }
            },
            root.ast.Stmt_Media { body: let body }
                | root.ast.Stmt_Supports { body: let body }
                | root.ast.Stmt_Keyframes { body: let body } =>
            {
                validate_decl_scope(body, ctx);
            },
            // An `@include`'s content block resolves at the include site, so its
            // `@extend` placement is only knowable at runtime — defer it. The
            // block is still mixin-body-like for declaration validation, so the
            // other checks keep running with the surrounding scope.
            let inc: root.ast.Stmt_Include => {
                let content = inc.content;
                if (content != null) {
                    validate_decl_scope(content, ScopeCtx { ...ctx, defer_extend: true });
                }
            },
            // A Sass `@import` (one that inlines a partial) is forbidden inside
            // a control directive or a function/mixin body; a plain-CSS
            // `@import` is always allowed (passed through verbatim).
            let imp: root.ast.Stmt_Import
                if scope != DeclScope.Allowed
                && imp.args.some((a: root.ast.ImportArg) -> bool {
                    a is root.ast.ImportArg_Sass
                }) => {
                // Positioned at the rule, so the error renders dart's snippet
                // (`@import "x"` underlined) and its frames — for a loaded file,
                // the loader chain.
                let e = root.error.Error.at("This at-rule is not allowed here.", imp.pos);
                e.length = imp.length;
                throw e;
            },
            // A property set's body is a declaration block: dart parses its
            // children as declarations and a short list of at-rules that
            // excludes `@import` of ANY kind (plain-CSS ones included, unlike
            // a control directive's body) and `@function`/`@mixin`.
            let ps: root.ast.Stmt_PropertySet => {
                let found = first_import_rule(ps._0.body);
                if (found != null) {
                    let e = root.error.Error.at("This at-rule is not allowed here.", found._0);
                    e.length = found._1;
                    throw e;
                }
                validate_decl_scope(ps._0.body, ctx.with(enter_control(scope)));
            },
            _ => {},
        }
    }
}

/// True when a rule selector is the empty-`()` artifact the indented-syntax
/// parser emits for a `@function` header whose parameter list spills onto a
/// continuation line. dart-sass treats `()` there as the parameter list, never
/// a selector, so it must not count as a style rule inside a `@function` body.
function is_empty_parens_selector(selector: root.ast.TplPiece[]) -> bool {
    match (selector) {
        [root.ast.TplPiece_Lit { _0: let s }] => root.std.trim(s) == "()",
        _ => false,
    }
}

/// Entering a control directive: a `@function`/`@mixin` body keeps its own
/// scope (declarations inside still get the function/mixin message); otherwise
/// control flow establishes the `Control` scope.
/// The first `@import` rule (of any kind) in a property set's body, looking
/// through control directives and nested property sets.
function first_import_rule(stmts: root.ast.Stmt[]) -> root.std.Tuple2<root.scanner.Pos, int>? {
    for (let stmt in stmts) {
        let found: root.std.Tuple2<root.scanner.Pos, int>? = match (stmt) {
            let imp: root.ast.Stmt_Import => root.std.Tuple2 { _0: imp.pos, _1: imp.length },
            let i: root.ast.Stmt_If => {
                // PORT: `branches.iter().find_map(..)` → an early-exit loop.
                let r: root.std.Tuple2<root.scanner.Pos, int>? = null;
                for (let b in i._0) {
                    r = first_import_rule(b.body);
                    if (r != null) {
                        break;
                    }
                }
                r
            },
            root.ast.Stmt_For { body: let body }
                | root.ast.Stmt_Each { body: let body }
                | root.ast.Stmt_While { body: let body } =>
            {
                first_import_rule(body)
            },
            let ps: root.ast.Stmt_PropertySet => first_import_rule(ps._0.body),
            _ => null,
        };
        if (found != null) {
            return found;
        }
    }
    null
}

function enter_control(scope: DeclScope) -> DeclScope {
    match (scope) {
        DeclScope.Function | DeclScope.Mixin => scope,
        _ => DeclScope.Control,
    }
}

function decl_error(scope: DeclScope, kind: string) -> string? {
    match (scope) {
        DeclScope.Allowed => null,
        DeclScope.Control => {
            let noun = if (kind == "function") {
                "Functions"
            } else {
                "Mixins"
            };
            `${noun} may not be declared in control directives.`
        },
        DeclScope.Function => "This at-rule is not allowed here.",
        DeclScope.Mixin => `Mixins may not contain ${kind} declarations.`,
    }
}

function is_css_import(arg: string) -> bool {
    arg.ends_with(".css")
        || arg.starts_with("http://")
        || arg.starts_with("https://")
        || arg.starts_with("//")
}

/// Append a top-level group's output, prefixing a blank-line separator
/// when there is already prior output (and the group is non-empty).
/// dart-sass omits the blank line after an at-rule, so two adjacent at-rules
/// (or an at-rule followed by a style rule) pack together with no gap.
/// Move every top-level plain-CSS `@import` (a `Raw` node) to the front of the
/// document, preserving their relative order — dart-sass requires CSS `@import`
/// rules to precede all style rules. Imports nested in `@media`/rules are not
/// `Raw` top-level nodes and are unaffected. A no-op when there is at most one
/// import or no rules precede any import.
function hoist_css_imports(out: OutNode[]) -> void {
    // PORT: nested fns `is_import`, `scan`, `is_clone_scope`,
    // `normalize_out_of_order` and `visit` hoisted to
    // `hoist_css_imports__<name>` below.
    // Hoisting only kicks in when a CSS `@import` follows a *style-producing*
    // node (a rule/at-rule/declaration). Imports interleaved only with comments
    // and blanks keep their source order (dart-sass preserves comment context).
    // ModuleScope wrappers are transparent for both detection and extraction.
    let seen_css = root.std.Cell.new(false);
    if (!hoist_css_imports__scan(out, seen_css)) {
        return;
    }
    // Stage 1 — dart's per-module `_endOfImports`/`_outOfOrderImports`: a
    // root-level plain-CSS import that appears AFTER other css re-inserts at
    // the end of the module's leading import run (comments before any css
    // extend the run; a ModuleScope is transparent but keeps its position).
    // A load-css / import-clone copy scope is dart's `clone: true` splice:
    // the cloned CSS joins the SURROUNDING module's own statements with no
    // module boundary, so its imports take part in the surrounding module's
    // out-of-order handling and leading-run split.
    // Stage 2 — dart `_combineCss`'s visitModule: two buckets. Each module
    // contributes its leading run (comments + plain-CSS @imports up to the
    // LAST import — `_indexAfterImports`) to the `imports` bucket and
    // everything after to the `css` flow. Comments written before a `@use`
    // (sitting before a ModuleScope here) are that module's
    // preModuleComments: they go to the imports bucket while the css flow is
    // still empty, and stay in place afterwards. The css flow keeps its
    // ModuleScope structure.
    let original = hoist_css_imports__normalize_out_of_order(root.std.take_all(out));
    let imports: OutNode[] = [];
    let css_seen = root.std.Cell.new(false);
    let rest = hoist_css_imports__visit(original, imports, css_seen);
    root.std.extend(out, imports);
    // The css flow keeps its eval-time grouping and packs tight against the
    // imports bucket (dart writes the flow right after the imports).
    while (rest.at(0) is OutNode_Blank) {
        rest.remove_at(0);
    }
    root.std.extend(out, rest);
    while (root.std.last(out) is OutNode_Blank) {
        out.pop();
    }
}

function hoist_css_imports__is_import(n: OutNode) -> bool {
    match (n) {
        OutNode_Raw { _0: let s } if s.starts_with("@import") => true,
        _ => false,
    }
}

function hoist_css_imports__scan(nodes: OutNode[], seen_css: root.std.Cell<bool>) -> bool {
    for (let n in nodes) {
        match (n) {
            let m: OutNode_ModuleScope => {
                if (hoist_css_imports__scan(m.nodes, seen_css)) {
                    return true;
                }
            },
            let n if hoist_css_imports__is_import(n) => {
                if (seen_css.value) {
                    return true;
                }
            },
            OutNode_Blank {} | OutNode_Comment {} => {},
            _ => {
                seen_css.value = true;
            },
        }
    }
    false
}

function hoist_css_imports__is_clone_scope(key: string) -> bool {
    key.includes("#copy") || key.includes("#import")
}

function hoist_css_imports__normalize_out_of_order(nodes: OutNode[]) -> OutNode[] {
    // PORT: the `VecDeque` is only popped/pushed at its FRONT, so it is kept
    // as a stack whose top is the front: `pop_front` → `pop()`,
    // `push_front(x)` → `push(x)`.
    let queue: OutNode[] = nodes.reverse();
    let result: OutNode[] = [];
    let out_of_order: OutNode[] = [];
    let frozen = false;
    let insert_at = 0;
    while let n: OutNode = queue.pop() {
        match (n) {
            let m: OutNode_ModuleScope if hoist_css_imports__is_clone_scope(m.key) => {
                // `for x in inner.into_iter().rev() { queue.push_front(x) }`
                let inner = m.nodes;
                let j = inner.length() - 1;
                while (j >= 0) {
                    queue.push(inner[j]);
                    j -= 1;
                }
            },
            let m: OutNode_ModuleScope => {
                result.push(
                    OutNode_ModuleScope {
                        key: m.key,
                        nodes: hoist_css_imports__normalize_out_of_order(m.nodes),
                    },
                );
                if (!frozen) {
                    insert_at = result.length();
                }
            },
            let n if hoist_css_imports__is_import(n) => {
                if (frozen) {
                    out_of_order.push(n);
                } else {
                    result.push(n);
                    insert_at = result.length();
                }
            },
            OutNode_Comment {} | OutNode_Blank {} => {
                result.push(n);
                if (!frozen) {
                    insert_at = result.length();
                }
            },
            let other => {
                frozen = true;
                result.push(other);
            },
        }
    }
    if (out_of_order.length() != 0) {
        result.splice(insert_at, 0, out_of_order);
    }
    result
}

function hoist_css_imports__visit(
    nodes: OutNode[],
    imports: OutNode[],
    css_seen: root.std.Cell<bool>,
) -> OutNode[] {
    let rest: OutNode[] = [];
    // PORT: the peekable iterator → an index cursor into `nodes`.
    let idx = 0;
    // Phase 1: pre-module comment runs and embedded upstream modules.
    let pending: OutNode[] = [];
    while (true) {
        match (nodes.at(idx)) {
            OutNode_Comment {} | OutNode_Blank {} => {
                pending.push(nodes[idx]);
                idx += 1;
            },
            let m: OutNode_ModuleScope => {
                idx += 1;
                let key = m.key;
                let inner = m.nodes;
                // preModuleComments: into the imports bucket only while
                // no css flowed yet (dart `css.isEmpty ? imports : css`).
                if (!css_seen.value) {
                    root.std.extend(
                        imports,
                        root.std.take_all(pending).filter((n: OutNode) -> bool {
                            !(n is OutNode_Blank)
                        }),
                    );
                } else {
                    root.std.extend(rest, root.std.take_all(pending));
                }
                let inner_rest = hoist_css_imports__visit(inner, imports, css_seen);
                if (inner_rest.length() != 0) {
                    css_seen.value = true;
                    rest.push(OutNode_ModuleScope { key: key, nodes: inner_rest });
                }
            },
            _ => {
                break;
            },
        }
    }
    // Phase 2: the module's own statements — `_indexAfterImports` over
    // the remaining sequence (pending comments are its leading run).
    let own: OutNode[] = pending;
    root.std.extend(own, nodes.slice(idx, nodes.length()));
    let last_import: int? = null;
    let i = 0;
    for (let n in own) {
        if (hoist_css_imports__is_import(n)) {
            last_import = i;
        } else if (!(n is OutNode_Comment || n is OutNode_Blank)) {
            break;
        }
        i += 1;
    }
    if (last_import != null) {
        let li = last_import;
        let tail = root.std.split_off(own, li + 1);
        root.std.extend(
            imports,
            own.filter((n: OutNode) -> bool {
                !(n is OutNode_Blank)
            }),
        );
        // Pulling the run leaves a NEW seam between the preceding css and
        // the remainder: its eval-time separator left with the run, so
        // re-derive it exactly like the eval-time `push_group` (dart's
        // group-end rule). Everything after the seam keeps its eval-time
        // grouping verbatim (a parent rule packs tight against its own
        // flattened nested children).
        while (tail.at(0) is OutNode_Blank) {
            tail.remove_at(0);
        }
        if (
            tail.some((n: OutNode) -> bool {
                !(n is OutNode_Blank)
            })
        ) {
            css_seen.value = true;
        }
        push_group(rest, tail);
        return rest;
    }
    if (
        own.some((n: OutNode) -> bool {
            !(n is OutNode_Blank)
        })
    ) {
        css_seen.value = true;
    }
    root.std.extend(rest, own);
    rest
}

/// Splice an already-grouped node sequence (a module's captured CSS) into a
/// sink. Into a top-level sink the whole sequence is ONE group — its internal
/// `Blank` separators are preserved and exactly one separator is added before
/// it — instead of per-node `push_group` calls that would double the blanks.
function splice_nodes(sink: root.std.Cell<Sink>, nodes: OutNode[]) -> void {
    match (sink.value) {
        let t: Sink_Top => push_group(t._0, nodes),
        _ => {
            for (let n in nodes) {
                if (!(n is OutNode_Blank)) {
                    sink.value.push_at_rule(n);
                }
            }
        },
    }
}

/// Drop leading blank separators (an unwrapped module-scope boundary can
/// leave one at the head of a cloned subtree).
function trim_leading_blanks(nodes: OutNode[]) -> void {
    while (nodes.at(0) is OutNode_Blank) {
        nodes.remove_at(0);
    }
}

/// Turn an INTERIOR `GroupEnd` marker (one that is immediately followed by an
/// output-producing node) into a single `Blank`, leaving a trailing marker
/// untouched. An in-place `@at-root` hoist that resumes its enclosing style rule
/// leaves such a marker between the hoisted style rule and the resumed parent;
/// dart separates them with one blank line. Today the only `GroupEnd` reaching a
/// style rule's `nested` is that one (top-level post-rule markers stay trailing,
/// consumed by the next `push_group`), so this is a no-op for every other shape.
function materialize_interior_group_ends(nodes: OutNode[]) -> OutNode[] {
    let is_content = (n: OutNode) -> bool {
        !(
            n is OutNode_Blank
                || n is OutNode_GroupEnd
                || n is OutNode_MediaHoist
                || n is OutNode_AtRootHoist
                || n is OutNode_AtRootPackTight
        )
    };
    let result: OutNode[] = [];
    // PORT: the peekable iterator → an index cursor.
    let i = 0;
    while (i < nodes.length()) {
        let node = nodes[i];
        i += 1;
        let peek = nodes.at(i);
        let peek_is_content = if (peek != null) {
            is_content(peek)
        } else {
            false
        };
        if (node is OutNode_GroupEnd && peek_is_content) {
            result.push(OutNode_Blank {  });
        } else {
            result.push(node);
        }
    }
    result
}

function push_group(out: OutNode[], group: OutNode[]) -> void {
    if (group.length() == 0) {
        return;
    }
    // A pack-tight or group-end sentinel attaches to the previous group
    // verbatim — no separator logic now; the NEXT group packs tight against
    // a pack-tight sentinel and blank-separates after a group-end one.
    if (group.length() == 1 && (group[0] is OutNode_AtRootPackTight || group[0] is OutNode_GroupEnd)) {
        root.std.extend(out, group);
        return;
    }
    // The last EFFECTIVE node before this group: module-scope wrappers are
    // judged by their last non-blank child (a module's captured CSS may end
    // in a style-group-end sentinel from its own evaluation). An EMPTY
    // module scope (e.g. a settings module of pure variables) is invisible
    // and must not act as the separator anchor — skip it and keep drilling
    // (uswds/bulma function modules ending in `@use "settings"`).
    // PORT: nested fns `invisible_wrapper`/`last_effective` hoisted to
    // `push_group__<name>` below.
    // A completed style rule always separates from the next group (dart
    // isGroupEnd); a top-level sentinel is consumed here, one inside a
    // wrapper just informs the decision (the emitters skip it).
    let top_marker = root.std.last(out) is OutNode_GroupEnd;
    if (top_marker) {
        out.pop();
    }
    let last = root.std.last(out);
    let last_eff: OutNode? = if (last != null) {
        push_group__last_effective(last)
    } else {
        null
    };
    let prev_group_end = top_marker || last_eff is OutNode_GroupEnd;
    // dart-sass never prefixes a blank line after an at-rule, a passed-through
    // CSS `@import` (a `Raw` at-rule), or a loud comment: the next group packs
    // tight against them. A blank line is only inserted after a style rule (or
    // top-level declaration) that already emitted CSS.
    let prev_packs_tight = match (last_eff) {
        OutNode_AtRule {} | OutNode_Comment {} => true,
        // A passed-through CSS `@import` and the remaining hoist markers (which a
        // module wrapper's last child can be) pack tight; only a group-end marker
        // forces the separator.
        OutNode_Raw {} | OutNode_MediaHoist {} | OutNode_AtRootHoist {} | OutNode_AtRootPackTight {} => {
            true
        },
        _ => false,
    };
    // A consumed group-end sentinel forces the separator even when popping it
    // emptied `out` (a stripped sourceMappingURL comment leading the document:
    // dart still writes a leading blank before the first emitted node).
    if ((top_marker || out.length() != 0) && (prev_group_end || !prev_packs_tight)) {
        out.push(OutNode_Blank {  });
    }
    root.std.extend(out, group);
}

function push_group__invisible_wrapper(n: OutNode) -> bool {
    match (n) {
        OutNode_Blank {} => true,
        let m: OutNode_ModuleScope => {
            m.nodes.every((x: OutNode) -> bool {
                push_group__invisible_wrapper(x)
            })
        },
        _ => false,
    }
}

function push_group__last_effective(n: OutNode) -> OutNode {
    if let m: OutNode_ModuleScope = n {
        // PORT: `nodes.iter().rev().find(..)` → a descending index loop.
        let j = m.nodes.length() - 1;
        while (j >= 0) {
            let l = m.nodes[j];
            if (!push_group__invisible_wrapper(l)) {
                return push_group__last_effective(l);
            }
            j -= 1;
        }
    }
    n
}

/// The integer indices a `@for` iterates: ascending or descending, with the
/// end included (`through`) or excluded (`to`).
/// Normalize a Sass argument/parameter name: hyphens and underscores are
/// interchangeable, so `$b-c` and `$b_c` refer to the same parameter. A name
/// containing CSS escapes is decoded first, so the raw definition spelling
/// `foo\func` and a call site's canonical `foo\f unc` agree (issue_553) —
/// dart decodes escapes into the identifier text at parse time.
function normalize_arg_name(name: string) -> string {
    if (name.includes("\\")) {
        return decode_ident_escapes(name).replace_all("_", "-");
    }
    // The common case is a name with no underscore: borrow it untouched
    // (this runs 4-6x per function call, so the no-alloc path matters).
    if (name.includes("_")) {
        name.replace_all("_", "-")
    } else {
        name
    }
}

/// Decode CSS escapes (`\66 ` / `\func` / `\\`) to their code points: up to
/// six hex digits terminated by one optional whitespace, or a literal next
/// character. NUL decodes to U+FFFD like CSS.
function decode_ident_escapes(s: string) -> string {
    let out = root.std.StrBuf.new();
    // PORT: the peekable char iterator → an index cursor over `s.chars()`.
    let cs = s.chars();
    let i = 0;
    while (i < cs.length()) {
        let c = cs[i];
        i += 1;
        if (c != "\\") {
            out.push(c);
            continue;
        }
        let hex = "";
        while (hex.length() < 6 && root.std.is_ascii_hexdigit(cs.at(i))) {
            hex = hex + cs[i];
            i += 1;
        }
        if (hex == "") {
            match (cs.at(i)) {
                let l: string => {
                    i += 1;
                    out.push(l);
                },
                _ => {
                    out.push("\\");
                },
            }
        } else {
            // PORT: `u32::from_str_radix(&hex, 16)` (≤ 6 hex digits, never
            // fails) → accumulate the digits.
            let cp = 0;
            for (let h in hex.chars()) {
                cp = cp * 16 + (root.std.to_digit(h, 16) ?? 0);
            }
            let ch = root.std.chr(cp);
            out.push(
                match (ch) {
                    "\0" | null => "�",
                    let ch: string => ch,
                },
            );
            let peek = cs.at(i);
            if (peek == " " || peek == "\t" || peek == "\n") {
                i += 1;
            }
        }
    }
    out.as_str()
}

/// Whether `name` is a global CSS-calculation function that dart-sass parses
/// as a calculation expression, and so cannot accept a `...` rest argument
/// (`clamp`, `hypot`, the exponent/trig functions). `min`/`max` are excluded:
/// they are variadic Sass functions that also accept a splat.
function is_calc_function(name: string) -> bool {
    match (name) {
        "clamp" | "hypot" | "atan2" | "log" | "pow" => true,
        _ => false,
    }
}

/// Whether `name` is a fixed-arity math calculation (`sin`, `cos`, `sqrt`,
/// `pow`, `log`, `hypot`, …) that dart-sass parses as a calculation rather than
/// an ordinary SassScript function. Matched case-insensitively. The legacy
/// global functions `abs`/`round`/`min`/`max`/`ceil`/`floor` are deliberately
/// excluded: they fall back to the Sass math builtin (with a deprecation
/// warning) instead of rejecting non-calculation operands, and `clamp`/`min`/
/// `max` keep their dedicated builtin preservation.
function is_pure_calc_math_function(name: string) -> bool {
    // Compared case-insensitively in place. Folding `name` into an owned
    // lowercase copy first would allocate on every call, and this predicate is
    // reached for every function call in every expression.
    let NAMES: string[] = [
        "sin",
        "cos",
        "tan",
        "asin",
        "acos",
        "atan",
        "atan2",
        "exp",
        "log",
        "pow",
        "hypot",
        "sqrt",
        "sign",
        "mod",
        "rem",
    ];
    NAMES.some((n: string) -> bool {
        root.std.eq_ignore_ascii_case(name, n)
    })
}

/// Whether a calc node carries an opaque operand — a `var()`, interpolation, or
/// unknown identifier preserved verbatim — anywhere in its tree. Such a node
/// cannot reduce to a single number, so a math calculation containing it stays
/// preserved (`sin(2px + var(--c))`).
function calc_node_has_opaque(node: root.value.CalcNode) -> bool {
    match (node) {
        root.value.CalcNode_Number {} => false,
        root.value.CalcNode_Str {} => true,
        let o: root.value.CalcNode_Op => {
            calc_node_has_opaque(o.left) || calc_node_has_opaque(o.right)
        },
        // A nested calculation function is already preserved, so a calc holding
        // it cannot reduce to a single number.
        root.value.CalcNode_Func {} => true,
        _ => false,
    }
}

/// Serialize an unquoted string as dart-sass `_visitUnquotedString` does: each
/// newline becomes a single space, and any whitespace immediately following a
/// newline is dropped. Used for `@supports` custom-property values.
function unquoted_string_css(s: string) -> string {
    let out = root.std.StrBuf.new();
    let after_newline = false;
    for (let ch in s.chars()) {
        match (ch) {
            "\n" => {
                out.push(" ");
                after_newline = true;
            },
            " " => {
                if (!after_newline) {
                    out.push(" ");
                }
            },
            let other => {
                after_newline = false;
                out.push(other);
            },
        }
    }
    out.as_str()
}

/// Whether `name` is a CSS math function that dart-sass parses as a calculation
/// (and so keeps unsimplified inside a `@supports` declaration). Matched
/// case-insensitively, mirroring dart-sass's calculation-function set.
function is_supports_calc_function(name: string) -> bool {
    let lower = root.std.ascii_lower(name);
    match (lower) {
        "min"
            | "max"
            | "clamp"
            | "round"
            | "mod"
            | "rem"
            | "abs"
            | "sign"
            | "sin"
            | "cos"
            | "tan"
            | "asin"
            | "acos"
            | "atan"
            | "atan2"
            | "exp"
            | "sqrt"
            | "pow"
            | "log"
            | "hypot"
            | "calc-size" =>
        {
            true
        },
        _ => false,
    }
}

/// Find a map anywhere in a value (including nested in a list), returning a
/// reference to the first one. Used to reject maps in CSS output positions,
/// where dart-sass errors with "(…) isn't a valid CSS value.".
function find_map(v: root.value.Value) -> root.value.Map? {
    match (v) {
        let m: root.value.Value_Map => m._0,
        let l: root.value.Value_List => {
            // PORT: `l.items.iter().find_map(find_map)` → an early-exit loop.
            let found: root.value.Map? = null;
            for (let item in l._0.items) {
                found = find_map(item);
                if (found != null) {
                    break;
                }
            }
            found
        },
        _ => null,
    }
}

/// The dart-sass "isn't a valid CSS value." error message for a value that
/// cannot be serialized to CSS, or `None` if it can. Mirrors the
/// declaration-emit guard exactly: a MAP found anywhere (including nested in a
/// list) is rejected with its own serialization, and a TOP-LEVEL empty
/// unbracketed list (`()`) is rejected as `()`. A bracketed `[]`, and an empty
/// list merely nested inside a non-empty list, both serialize fine. Reused at
/// every other CSS-serialization site (unary `-`/`+`, the `+`/`-`/`/` string
/// joins, and `#{…}` interpolation) so they reject the same shapes dart does
/// instead of silently emitting bogus output.
function css_value_error_msg(v: root.value.Value) -> string? {
    let m = find_map(v);
    if (m != null) {
        return `${m.to_css(false)} isn't a valid CSS value.`;
    }
    if let l: root.value.Value_List = v {
        if (l._0.items.length() == 0 && !l._0.bracketed) {
            return "() isn't a valid CSS value.";
        }
    }
    null
}

/// Serialize a value for interpolation, erroring (like dart-sass) if it is a
/// map or empty list that cannot become CSS. Shared by every interpolation
/// context that turns a value into text (`@media`/`@supports` queries and
/// feature decls). The error carries no span — these template sites have no
/// per-piece source position — but matches dart's message and non-zero exit.
function interp_checked(v: root.value.Value) -> string {
    let s = root.std.StrBuf.new();
    interp_checked_into(s, v);
    s.as_str()
}

/// [`interp_checked`] into the caller's buffer, for the template evaluators
/// that are already building one: `#{$i}` writes its digits into the template's
/// string rather than into one of its own.
function interp_checked_into(out: root.std.StrBuf, v: root.value.Value) -> void {
    let msg = css_value_error_msg(v);
    if (msg != null) {
        throw root.error.Error.unpositioned(msg);
    }
    v.write_interp(out);
}

function for_indices(start: int, end: int, inclusive: bool) -> int[] {
    let out: int[] = [];
    if (start <= end) {
        let last = if (inclusive) {
            end
        } else {
            end - 1
        };
        let i = start;
        while (i <= last) {
            out.push(i);
            i += 1;
        }
    } else {
        let last = if (inclusive) {
            end
        } else {
            end + 1
        };
        let i = start;
        while (i >= last) {
            out.push(i);
            i -= 1;
        }
    }
    out
}

/// The diagnostic stack-frame name for an `@include`: dart-sass prints the bare
/// mixin name with empty parens (`name()`), without the `ns.` namespace.
function mixin_frame_name(name: string, unused_module: string?) -> string {
    `${name}()`
}

/// Whether a mixin body contains a reachable `@content`. dart-sass scans the
/// whole body tree — control flow, at-rules, nested style rules, and nested
/// `@include` content blocks all count (nested mixin/function definitions are
/// disallowed by the grammar, so there is no separate scope to exclude).
function body_uses_content(body: root.ast.Stmt[]) -> bool {
    body.some((s: root.ast.Stmt) -> bool {
        stmt_uses_content(s)
    })
}

function stmt_uses_content(stmt: root.ast.Stmt) -> bool {
    match (stmt) {
        root.ast.Stmt_Content {} => true,
        let r: root.ast.Stmt_Rule => body_uses_content(r._0.body),
        let i: root.ast.Stmt_If => {
            i._0.some((b: root.ast.IfBranch) -> bool {
                body_uses_content(b.body)
            })
        },
        root.ast.Stmt_For { body: let body }
            | root.ast.Stmt_Each { body: let body }
            | root.ast.Stmt_While { body: let body }
            | root.ast.Stmt_Media { body: let body }
            | root.ast.Stmt_Supports { body: let body }
            | root.ast.Stmt_AtRoot { body: let body }
            | root.ast.Stmt_Keyframes { body: let body } =>
        {
            body_uses_content(body)
        },
        // PORT: `Stmt::AtRule { body: Some(body), .. }` / `Stmt::Include {
        // content: Some(content), .. }` → bind the variant, then test the field.
        let a: root.ast.Stmt_AtRule => {
            let body = a.body;
            if (body != null) {
                body_uses_content(body)
            } else {
                false
            }
        },
        let inc: root.ast.Stmt_Include => {
            let content = inc.content;
            if (content != null) {
                body_uses_content(content)
            } else {
                false
            }
        },
        _ => false,
    }
}

/// Validate a (post-interpolation) selector string against the subset of
/// dart-sass's parser rules this build can safely enforce:
///   * `&` may appear only at the beginning of a compound selector (so `b&`,
///     `[x]&`, `.y&` are all errors). A `&` followed directly by an
///     identifier-name character (`a`, `-`, `_`, digit, `\`) is a "suffix":
///     at the document root (no parent) that is an error, but inside a style
///     rule it concatenates onto the parent.
///   * A `%` placeholder must be followed directly by an identifier name-start
///     character; a bare `%` (or `%` before `.`, a digit, whitespace, …) is
///     "Expected identifier.". A `%` right after a digit is a percentage
///     keyframe selector (`10%`), not a placeholder.
///   * An `[…]` attribute selector's modifier must be a single ASCII letter
///     immediately before the closing `]`.
///
/// Quoted strings (with `\` escapes) and the contents of nested `[…]`/`(…)`
/// groups are skipped so combinators/`&`/`%` inside them are not misread.
/// Reject the selector forms plain CSS forbids in one comma-part: a placeholder
/// (`%x`), a parent reference with a suffix (`&x`), a top-level leading
/// combinator (`> a`), and a trailing combinator (`a >`). The text is the
/// already-resolved selector (no interpolation left).
/// The parent directory of a resolved file key, for relative URL resolution
/// (`None` when the key has no directory component or is not a path).
function dirname_of(key: string) -> string? {
    let p = key;
    let d = root.std.path_parent(p);
    // `.filter(|d| !d.as_os_str().is_empty())`
    if (d == null) {
        return null;
    }
    if (d == "") {
        return null;
    }
    d
}

/// An `@at-root` batch awaiting its graft point (paired with a hoist marker).
class AtRootBatch {
    /// Index of the topmost excluded at-rule layer = the depth the batch
    /// re-enters the tree at (0 = document root).
    target: int,
    /// Whether the `@at-root` ran with no enclosing style rule: dart then
    /// marks the batch's last node as a group end (the next root-level node
    /// gets a blank line) instead of packing tight.
    group_end: bool,
    nodes: OutNode[],
}

/// Whether `n` is a hoist marker whose batch escapes a body at `depth`:
/// media hoists always escape; an at-root batch escapes when its graft
/// target lies outside this body. Escaping markers are transparent to
/// block anchoring (the batch is not a sibling inside this node).
function is_escaping_marker(n: OutNode, depth: int) -> bool {
    match (n) {
        OutNode_MediaHoist {} => true,
        let h: OutNode_AtRootHoist => h.target < depth,
        _ => false,
    }
}

/// One enclosing at-rule layer recorded for `@at-root` queries: the data
/// needed to re-wrap a hoisted body in that layer (dart's "included" copies).
interface AtCtx {
    /// The query name this layer matches (dart `AtRootQuery.excludes`).
    function query_name(self) -> string throws never {
        match (self) {
            AtCtx_Media {} => "media",
            AtCtx_Supports {} => "supports",
            AtCtx_Keyframes {} => "keyframes",
            _ => root.std.unreachable(),
        }
    }

    /// Wrap `body` in this layer's at-rule node.
    function wrap(self, body: OutNode[]) -> OutNode throws never {
        match (self) {
            let m: AtCtx_Media => {
                OutNode_AtRule {
                    name: "media",
                    prelude: m.prelude,
                    body: body,
                    has_block: true,
                    kind: AtRuleKind.Conditional,
                    lines: root.ast.SrcLines.default(),
                }
            },
            let s: AtCtx_Supports => {
                OutNode_AtRule {
                    name: "supports",
                    prelude: s.prelude,
                    body: body,
                    has_block: true,
                    kind: AtRuleKind.Conditional,
                    lines: root.ast.SrcLines.default(),
                }
            },
            let k: AtCtx_Keyframes => {
                OutNode_AtRule {
                    name: k.name,
                    prelude: k.prelude,
                    body: body,
                    has_block: true,
                    kind: AtRuleKind.Generic,
                    lines: root.ast.SrcLines.default(),
                }
            },
            _ => root.std.unreachable(),
        }
    }
}

class AtCtx_Media {
    prelude: string,
    implements AtCtx {}
}

class AtCtx_Supports {
    prelude: string,
    implements AtCtx {}
}

class AtCtx_Keyframes {
    name: string,
    prelude: string,
    implements AtCtx {}
}

/// A parsed `@at-root` query (dart `AtRootQuery`): `(with: …)` keeps only
/// the named layers, `(without: …)` drops them, `all` matches every layer,
/// and the default (no query) is `(without: rule)`.
class AtRootQuery {
    include: bool,
    names: string[],
    all: bool,
    rule: bool,
    function parse(text: string?) -> AtRootQuery {
        if (text == null) {
            return AtRootQuery { include: false, names: ["rule"], all: false, rule: true };
        }
        let inner = root.std.trim_end_matches(root.std.trim_start_matches(root.std.trim(text), "("), ")");
        let split = root.std.split_once(inner, ":");
        let include_list: root.std.Tuple2<bool, string> = match (split) {
            root.std.Tuple2<string, string> { _0: let k, _1: let v }
                if root.std.eq_ignore_ascii_case(root.std.trim(k), "with") => {
                root.std.Tuple2 { _0: true, _1: v }
            },
            root.std.Tuple2<string, string> { _1: let v } => root.std.Tuple2 { _0: false, _1: v },
            _ => root.std.Tuple2 { _0: false, _1: inner },
        };
        let include = include_list._0;
        let list = include_list._1;
        // PORT: `list.split_whitespace()` → split on (Unicode) whitespace runs by hand.
        let words: string[] = [];
        let cur = "";
        for (let c in list.chars()) {
            if (c.is_whitespace()) {
                if (cur != "") {
                    words.push(cur);
                    cur = "";
                }
            } else {
                cur = cur + c;
            }
        }
        if (cur != "") {
            words.push(cur);
        }
        let names: string[] = words.map((s: string) -> string {
            root.std.ascii_lower(root.std.trim_matches(root.std.trim_matches(s, "\""), "'"))
        });
        let all = names.some((n: string) -> bool {
            n == "all"
        });
        let rule = names.some((n: string) -> bool {
            n == "rule"
        });
        AtRootQuery { include: include, names: names, all: all, rule: rule }
    }

    /// Whether the query excludes style rules (dart `excludesStyleRules`).
    function excludes_style_rules(self) -> bool {
        (self.all || self.rule) != self.include
    }

    /// Whether the query excludes the layer named `name`.
    function excludes_name(self, name: string) -> bool {
        if (self.all) {
            return !self.include;
        }
        self.names.some((n: string) -> bool {
            n == name
        })
            != self.include
    }
}

/// Normalize a keyframe selector the way dart re-serializes a stop: the
/// `from`/`to` keywords are lowercased (`FROM` -> `from`), and so is a
/// percentage stop's scientific-notation marker (`130E-1%` -> `130e-1%`);
/// the digits are left verbatim.
function normalize_keyframe_selector(s: string) -> string {
    let t = root.std.trim(s);
    if (root.std.eq_ignore_ascii_case(t, "from") || root.std.eq_ignore_ascii_case(t, "to")) {
        return root.std.ascii_lower(t);
    }
    if (!s.includes("E")) {
        return s;
    }
    let is_pct = t.ends_with("%")
        && root.std.all_chars(t.slice(0, t.length() - 1), (c: string) -> bool {
            c.is_ascii_numeric() || c == "." || c == "+" || c == "-" || c == "e" || c == "E"
        });
    if (is_pct) {
        s.replace_all("E", "e")
    } else {
        s
    }
}

/// Convert an at-rule-body node list (as produced by `eval_at_body` with no
/// parents) into rule items, for at-rules nested verbatim inside keyframe
/// blocks.
function at_body_to_items(nodes: OutNode[]) -> OutItem[] {
    let items: OutItem[] = [];
    for (let n in nodes) {
        match (n) {
            let d: OutNode_AtDecl => {
                items.push(
                    OutItem_Decl {
                        prop: d.prop,
                        value: d.value,
                        important: d.important,
                        custom: d.custom,
                        lines: d.lines,
                        value_span: d.value_span,
                    },
                );
            },
            let c: OutNode_Comment => {
                items.push(OutItem_Comment { _0: c._0, _1: c._1 });
            },
            let r: OutNode_Rule => {
                items.push(
                    OutItem_NestedRule {
                        selectors: r.selectors.into_strings(),
                        linebreaks: r.linebreaks,
                        items: r.items,
                        lines: r.lines,
                    },
                );
            },
            let a: OutNode_AtRule => {
                if (a.has_block) {
                    items.push(
                        OutItem_NestedAtRule {
                            name: a.name,
                            prelude: a.prelude,
                            items: at_body_to_items(a.body),
                            kind: a.kind,
                            lines: a.lines,
                        },
                    );
                } else {
                    items.push(
                        OutItem_ChildlessAtRule {
                            name: a.name,
                            prelude: a.prelude,
                            css_import: false,
                            lines: a.lines,
                        },
                    );
                }
            },
            let m: OutNode_ModuleScope => {
                root.std.extend(items, at_body_to_items(m.nodes));
            },
            // Raw passthroughs, blanks, and the control-only hoist markers carry
            // no rule-block item.
            OutNode_Raw {}
                | OutNode_Blank {}
                | OutNode_GroupEnd {}
                | OutNode_MediaHoist {}
                | OutNode_AtRootHoist {}
                | OutNode_AtRootPackTight {} =>
            {},
            _ => {},
        }
    }
    items
}

function validate_plain_css_selector(part: string, top_level: bool) -> void {
    let trimmed = root.std.trim(part);
    let chars_buf = CharBuf_of(trimmed);
    let chars: string[] = chars_buf.deref();
    // A leading combinator is allowed when *nested* (it joins onto the parent),
    // but not at the top level.
    let first = chars.at(0);
    if (top_level && (first == ">" || first == "+" || first == "~")) {
        throw root.error.Error.unpositioned(
            "Top-level leading combinators aren't allowed in plain CSS.",
        );
    }
    // A trailing combinator never has a selector to bind to.
    let last = root.std.last(chars);
    if (last == ">" || last == "+" || last == "~") {
        throw root.error.Error.unpositioned("expected selector.");
    }
    let i = 0;
    // True at the start of each compound (start, or after a combinator/space).
    let at_compound_start = true;
    let depth = 0; // inside `[...]`/`(...)`
    while (i < chars.length()) {
        let c = chars[i];
        match (c) {
            "\\" => {
                i += 2;
                at_compound_start = false;
                continue;
            },
            "[" | "(" => {
                depth += 1;
            },
            "]" | ")" => {
                depth -= 1;
            },
            _ if depth > 0 => {},
            " " | "\t" | "\n" | "\r" | ">" | "+" | "~" => {
                at_compound_start = true;
            },
            "%" if at_compound_start => {
                throw root.error.Error.unpositioned(
                    "Placeholder selectors aren't allowed in plain CSS.",
                );
            },
            "&" => {
                let next = chars.at(i + 1);
                let suffix = if (next != null) {
                    next.is_ascii_alphanumeric() || next == "-" || next == "_" || next == "\\"
                } else {
                    false
                };
                if (suffix) {
                    throw root.error.Error.unpositioned(
                        "Parent selectors can't have suffixes in plain CSS.",
                    );
                }
                at_compound_start = false;
            },
            _ => {
                at_compound_start = false;
            },
        }
        i += 1;
    }
}

/// Whether the `(` at `chars[open]` directly follows a pseudo-class/element
/// name: a non-empty run of identifier characters whose preceding character is
/// a `:` (`:not(`, `::-webkit-any(`).
function paren_follows_pseudo(chars: string[], open: int) -> bool {
    let j = open;
    while (j > 0) {
        let p = chars[j - 1];
        if (p.is_ascii_alphanumeric() || p == "-" || p == "_" || root.std.ord(p) >= 0x80) {
            j -= 1;
        } else {
            break;
        }
    }
    j < open && j > 0 && chars[j - 1] == ":"
}

function validate_selector(sel: string, has_parent: bool) -> void {
    // A selector list whose FIRST comma part is empty is dart-sass's
    // "expected selector." (`,b`); later empty parts (`a,,b`, trailing `a,`)
    // are tolerated and skipped.
    if (root.std.trim_start(sel).starts_with(",")) {
        throw root.error.Error.unpositioned("expected selector.");
    }
    // Parens and brackets must nest properly: `a:b([c)]` is dart's
    // `expected "]".` (a `)` closing while a `[` is still open). A selector
    // without any bracket/quote/escape byte cannot mis-nest — skip the scan.
    if (
        root.std.any_char(sel, (c: string) -> bool {
            c == "(" || c == "[" || c == ")" || c == "]" || c == "\"" || c == "'" || c == "\\"
        })
    ) {
        let stack: string[] = [];
        let quote: string? = null;
        let prev_escape = false;
        for (let c in sel.chars()) {
            if (prev_escape) {
                prev_escape = false;
                continue;
            }
            match (c) {
                "\\" => {
                    prev_escape = true;
                },
                "\"" | "'" => {
                    let q = c;
                    match (quote) {
                        let open: string if open == q => {
                            quote = null;
                        },
                        let _open: string => {},
                        null => {
                            quote = q;
                        },
                    }
                },
                _ if quote != null => {},
                "(" | "[" => {
                    stack.push(c);
                },
                ")" | "]" => {
                    let open = stack.pop();
                    if (c == ")" && open == "[") {
                        throw root.error.Error.unpositioned("expected \"]\".");
                    }
                    if (c == "]" && open == "(") {
                        throw root.error.Error.unpositioned("expected \")\".");
                    }
                },
                _ => {},
            }
        }
    }
    // Any pseudo-class/element must name an identifier: a bare or repeated colon
    // with no ident-start after it (`a::`, `a:::before`, `::before::`, `a:`) is
    // dart's `Expected identifier.`. Gated on a `:` being present.
    if (sel.includes(":")) {
        validate_pseudo_names(sel);
    }
    // Grammar-typed pseudo arguments — the An+B microsyntax of
    // `:nth-child`/`:nth-last-child` and the non-empty selector list of
    // `:not`/`:is`/`:where`/`:has`/… — are validated against dart's parser.
    // Gated on a parenthesized pseudo (a `:` somewhere before a `(`).
    if (sel.includes("(") && sel.includes(":")) {
        root.selector.validate_pseudo_args(sel) catch (e) {
            let m: root.std.StrError => {
                throw root.error.Error.unpositioned(m.message);
            }
        };
    }
    // One byte pre-scan classifies the rest of the validation: most resolved
    // selectors are plain (idents/classes/combinators/spaces) and need at
    // most the sigil ident-start check — no char-vector materialization, no
    // comma split. Every rejection or recursion in the full walk below is
    // triggered by one of the "slow" bytes, except the `#`/`.` ident-start
    // rule, which the byte-only light path reproduces exactly (UTF-8
    // continuation bytes are >= 0x80, so byte lookarounds match char ones).
    let needs_slow = false;
    let has_sigil = false;
    // PORT: the byte scan walks chars; every byte it tests for is ASCII.
    for (let b in sel.chars()) {
        match (b) {
            "\\" | "\"" | "'" | "[" | "(" | ")" | "]" | "&" | "%" | "/" => {
                needs_slow = true;
            },
            "#" | "." => {
                has_sigil = true;
            },
            _ => {},
        }
    }
    // Equivalence of the light/skip paths against the full walk was proven
    // by a check build asserting identical Results on every call across the
    // full sass-spec suite.
    if (needs_slow) {
        validate_selector_tail(sel, has_parent);
    } else if (has_sigil) {
        validate_plain_sigils(sel);
    }
}

/// Every pseudo-class/element must name an identifier: after its leading `:`
/// (or `::`), an identifier-start character is required. A bare or repeated
/// colon (`a::`, `a:::before`, `a:`, `::before::`) — including one nested in a
/// selector-argument pseudo (`:not(::)`) — is dart's `Expected identifier.`.
/// Colons inside `[...]` attribute selectors and string literals are exempt.
function validate_pseudo_names(sel: string) -> void {
    let chars_buf = CharBuf_of(sel);
    let chars: string[] = chars_buf.deref();
    let i = 0;
    while (i < chars.length()) {
        match (chars[i]) {
            "\\" => {
                i += 2;
            },
            "\"" | "'" => {
                i = skip_string(chars, i);
            },
            "[" => {
                i = matching_bracket(chars, i) + 1;
            },
            ":" => {
                i += 1;
                // A second colon makes a pseudo-element (`::before`).
                if (chars.at(i) == ":") {
                    i += 1;
                }
                // The name must begin with a CSS identifier-start character.
                if (!pseudo_name_starts_at(chars, i)) {
                    throw root.error.Error.unpositioned("Expected identifier.");
                }
            },
            _ => {
                i += 1;
            },
        }
    }
}

/// Whether `chars[i..]` begins a CSS identifier (the pseudo name after a colon):
/// a letter, `_`, escape, or non-ASCII char; or a `-` provided the NEXT
/// character is itself an identifier-start (`-foo`, `--foo`) — a lone `-`, a
/// `-` then a digit (`-9`), and a leading digit (`0`, `9x`) are not.
function pseudo_name_starts_at(chars: string[], i: int) -> bool {
    let is_start = (c: string) -> bool {
        c.is_ascii_alphabetic() || c == "_" || c == "\\" || root.std.ord(c) >= 0x80
    };
    match (chars.at(i)) {
        let c: string if is_start(c) => true,
        "-" => {
            let n = chars.at(i + 1);
            if (n != null) {
                is_start(n) || n == "-"
            } else {
                false
            }
        },
        _ => false,
    }
}

/// The `#`/`.` ident-start rule on a selector with no escape, quote,
/// bracket, paren, `&`, `%`, or `/` byte: every sigil is top-level, and its
/// next character must start an identifier (a `.` right after a digit is a
/// keyframe decimal point and is skipped; `#` gets no such exemption).
function validate_plain_sigils(sel: string) -> void {
    let b = sel.to_utf8();
    for (let i in baml.iter.Range.new(0, b.length())) {
        let c = b[i];
        // b'#' = 35, b'.' = 46
        if (c != 35 && c != 46) {
            continue;
        }
        // b'0'..=b'9' = 48..=57
        if (c == 46 && i > 0 && b[i - 1] >= 48 && b[i - 1] <= 57) {
            continue;
        }
        let starts_ident = if (i + 1 < b.length()) {
            let n = b[i + 1];
            // ASCII letter, b'-' = 45, b'_' = 95, or a non-ASCII lead byte.
            (n >= 65 && n <= 90) || (n >= 97 && n <= 122) || n == 45 || n == 95 || n >= 0x80
        } else {
            false
        };
        if (!starts_ident) {
            throw root.error.Error.unpositioned("Expected identifier.");
        }
    }
}

/// The full per-part validation walk (slow path).
function validate_selector_tail(sel: string, has_parent: bool) -> void {
    for (let part in split_commas(sel).deref()) {
        let chars_buf = CharBuf_of(part);
        let chars: string[] = chars_buf.deref();
        let i = 0;
        // True at the start of each compound selector (start of the part and
        // immediately after any combinator or whitespace).
        let at_compound_start = true;
        let depth = 0; // inside `[...]` or `(...)`
        // PORT: the `'#' | '.'` arm's guard, as a closure (a BAML match guard
        // cannot hold a parenthesized sub-expression).
        let is_decimal_point = (c: string, i: int) -> bool {
            c == "." && i > 0 && root.std.is_ascii_digit(chars[i - 1])
        };
        while (i < chars.length()) {
            let c = chars[i];
            match (c) {
                "\\" => {
                    // An escape consumes the following character verbatim.
                    i += 2;
                    at_compound_start = false;
                    continue;
                },
                "\"" | "'" => {
                    i = skip_string(chars, i);
                    at_compound_start = false;
                    continue;
                },
                "[" if depth == 0 => {
                    let end = matching_bracket(chars, i);
                    validate_attribute(chars.slice(i + 1, end));
                    i = end + 1;
                    at_compound_start = false;
                    continue;
                },
                // A top-level `(` is only valid as a pseudo-class/element
                // argument list (`:not(…)`, `::part(…)`): the run of identifier
                // characters directly before it must follow a `:`. Anywhere
                // else — compound start, after a plain identifier, after `]` —
                // dart-sass reports "expected selector." (`a(b)`, `a (b)`).
                "(" if depth == 0 => {
                    if (!paren_follows_pseudo(chars, i)) {
                        throw root.error.Error.unpositioned("expected selector.");
                    }
                    depth += 1;
                    at_compound_start = false;
                },
                // A stray top-level closer never matches an open bracket.
                ")" if depth == 0 => {
                    throw root.error.Error.unpositioned("Unexpected \")\".");
                },
                "[" | "(" => {
                    depth += 1;
                    at_compound_start = false;
                },
                "]" | ")" => {
                    depth -= 1;
                    at_compound_start = false;
                },
                _ if depth > 0 => {},
                " " | "\t" | "\n" | "\r" => {
                    at_compound_start = true;
                },
                ">" | "+" | "~" => {
                    at_compound_start = true;
                },
                "&" => {
                    if (!at_compound_start) {
                        throw root.error.Error.unpositioned(
                            "\"&\" may only used at the beginning of a compound selector.",
                        );
                    }
                    let next = chars.at(i + 1);
                    let is_suffix = if (next != null) {
                        next.is_ascii_alphanumeric() || next == "-" || next == "_" || next == "\\"
                    } else {
                        false
                    };
                    if (is_suffix && !has_parent) {
                        throw root.error.Error.unpositioned(
                            "A top-level selector may not contain a parent selector with a suffix.",
                        );
                    }
                    at_compound_start = false;
                },
                "%" => {
                    let prev_is_digit = i > 0 && root.std.is_ascii_digit(chars[i - 1]);
                    if (!prev_is_digit) {
                        let next = chars.at(i + 1);
                        let starts_ident = if (next != null) {
                            next.is_ascii_alphabetic() || next == "-" || next == "_" || next == "\\"
                        } else {
                            false
                        };
                        if (!starts_ident) {
                            throw root.error.Error.unpositioned("Expected identifier.");
                        }
                    }
                    at_compound_start = false;
                },
                // A `#`/`.` (id/class) must be followed by an identifier name
                // start; `#2b` / `.3c` are "Expected identifier." (a `-`, `_`,
                // letter, escape, or non-ASCII char is fine). A `.` right after a
                // digit is a decimal point (a keyframe stop like `50.5%`), not a
                // class, so it is skipped. A bare digit *type* selector (`1a`) is
                // also left alone: `50%` keyframe stops reach this same validator.
                "#" | "." if !is_decimal_point(c, i) => {
                    let next = chars.at(i + 1);
                    let starts_ident = if (next != null) {
                        next.is_ascii_alphabetic()
                            || next == "-"
                            || next == "_"
                            || next == "\\"
                            || root.std.ord(next) >= 0x80
                    } else {
                        false
                    };
                    if (!starts_ident) {
                        throw root.error.Error.unpositioned("Expected identifier.");
                    }
                    at_compound_start = false;
                },
                // A reference combinator (`/foo/`) used to be valid CSS but is
                // no longer supported; dart-sass now rejects any top-level `/`
                // in a selector with "expected selector.". (A `/` inside an
                // attribute value or a pseudo argument is at depth > 0 and is
                // handled above.)
                "/" => {
                    throw root.error.Error.unpositioned("expected selector.");
                },
                _ => {
                    at_compound_start = false;
                },
            }
            i += 1;
        }
    }
}

/// Inline capacity of a [`CharBuf`], in characters. Selector parts measure
/// around 16 characters on the benchmark corpora and whole selectors around
/// 40, so 64 keeps effectively all of them off the heap, and initializing that
/// much stack costs far less than the allocate-and-grow it replaces. Longer
/// input takes the heap arm, which builds no array at all.
function CHAR_BUF_INLINE() -> int {
    64
}

/// A selector's characters, materialized for index-based scanning.
///
/// The scanners here want `[char]` rather than bytes: an escape advances by one
/// CHARACTER, and several of the predicates are Unicode-aware, so a byte cursor
/// would have to decode as it walks. Collecting a `Vec<char>` is what that used
/// to cost — and more than one allocation per call, because `str::chars()` only
/// promises `len / 4` characters, so the `Vec` started at a quarter of the size
/// it needed and doubled its way up. Selectors are short, so the characters go
/// into an inline array instead and a scan touches the allocator not at all.
///
/// Never pooled across calls: inside a compile scope the heap arm's allocation
/// comes from the arena, and the arena is reset wholesale when the scope ends
/// (see [`crate::arena`]), so a buffer kept past that point would hand out
/// memory the next compile is also using.
///
/// Bind a `&[char]` from it once (`let chars: &[char] = &buf;`) instead of
/// indexing the buffer: a scan loop then walks a plain slice, exactly as it did
/// the `Vec` this replaces, with no per-index arm to pick.
// The big inline arm is the point of the type, and every `CharBuf` is a
// stack local that never enters a collection, so the arms' size difference
// costs nothing.
interface CharBuf {
    function deref(self) -> string[] throws never {
        match (self) {
            let inline: CharBuf_Inline => {
                // PORT: `&chars[..len]`; the inline arm holds exactly `len`
                // characters (see `CharBuf_of`), so no copy is needed then.
                if (inline.len == inline.chars.length()) {
                    inline.chars
                } else {
                    inline.chars.slice(0, inline.len)
                }
            },
            let heap: CharBuf_Heap => heap._0,
            _ => root.std.unreachable(),
        }
    }
}

/// The characters are `chars[..len]` — no allocation.
class CharBuf_Inline {
    chars: string[],
    len: int,
    implements CharBuf {}
}

/// Input too long for the array.
class CharBuf_Heap {
    _0: string[],
    implements CharBuf {}
}

/// The characters of `s`, in order.
function CharBuf_of(s: string) -> CharBuf {
    // A character is at least one byte, so a string of at most
    // `CHAR_BUF_INLINE` bytes holds at most that many characters.
    if (s.byte_length() > CHAR_BUF_INLINE()) {
        // Deliberately a plain `collect`. Sizing the `Vec` from the byte
        // length first (`with_capacity(s.len())` — one allocation instead
        // of the grow chain) measured SLOWER on every corpus: a `char` is
        // four bytes, so that asks the arena for four times what the text
        // needs, while growing into the arena's tail is nearly free.
        return CharBuf_Heap { _0: s.chars() };
    }
    // PORT: BAML has no fixed-size stack array (`['\0'; CHAR_BUF_INLINE]`
    // filled slot by slot); the inline arm holds exactly the characters.
    let chars = s.chars();
    let len = chars.length();
    CharBuf_Inline { chars: chars, len: len }
}

/// Index just past a quoted string starting at `start` (a `"` or `'`),
/// honouring `\` escapes. Returns `chars.len()` for an unterminated string.
function skip_string(chars: string[], start: int) -> int {
    let quote = chars[start];
    let i = start + 1;
    while (i < chars.length()) {
        match (chars[i]) {
            "\\" => {
                i += 2;
            },
            let c if c == quote => {
                return i + 1;
            },
            _ => {
                i += 1;
            },
        }
    }
    chars.length()
}

/// Index of the `]` matching the `[` at `open`, skipping quoted strings and
/// escapes. Returns `chars.len()` when unmatched.
function matching_bracket(chars: string[], open: int) -> int {
    let i = open + 1;
    while (i < chars.length()) {
        match (chars[i]) {
            "\\" => {
                i += 2;
            },
            "\"" | "'" => {
                i = skip_string(chars, i);
            },
            "]" => {
                return i;
            },
            _ => {
                i += 1;
            },
        }
    }
    chars.length()
}

/// Validate the inner content of an `[…]` attribute selector. dart-sass allows
/// at most a single trailing ASCII-letter modifier, directly before the close
/// bracket: `[a]`, `[a=b]`, `[a=b ]`, `[a="b"i]`, and `[a=b i]` are valid, but
/// `[a b]` (no operator), `[a=b cd]` (too long), `[a=b 1]`/`[a=b _]`/`[a=b ï]`
/// (non-letter), and `[a=b i ]` (trailing space after the modifier) are not.
function validate_attribute(inner: string[]) -> void {
    let err = () -> root.error.Error {
        root.error.Error.unpositioned("expected \"]\".")
    };
    let i = 0;
    // PORT: `skip_ws(&mut i)` → a closure that advances the captured `i`.
    let skip_ws = () -> void {
        while (i < inner.length() && inner[i].is_whitespace()) {
            i += 1;
        }
    };
    // Namespace + attribute name (identifiers, escapes, and a `|` namespace
    // separator); interpolation has already been resolved to literal text.
    skip_ws();
    while (i < inner.length()) {
        let c = inner[i];
        if (c == "\\") {
            i += 2;
        } else if (is_name_char(c) || c == "|" || c == "*") {
            i += 1;
        } else {
            break;
        }
    }
    skip_ws();
    if (i >= inner.length()) {
        return; // bare `[name]`
    }
    // An operator must follow the name; anything else (e.g. a second
    // identifier in `[a b]`) is invalid.
    let op_ok = match (inner[i]) {
        "=" => true,
        "~" | "|" | "^" | "$" | "*" => inner.at(i + 1) == "=",
        _ => false,
    };
    if (!op_ok) {
        throw err();
    }
    i
        += if (inner[i] == "=") {
            1
        } else {
            2
        };
    skip_ws();
    // The value: a quoted string or an unquoted identifier (with escapes).
    match (inner.at(i)) {
        "\"" | "'" => {
            i = skip_string(inner, i);
        },
        let _c: string => {
            while (i < inner.length()) {
                let c = inner[i];
                if (c == "\\") {
                    i += 2;
                } else if (c.is_whitespace()) {
                    break;
                } else {
                    i += 1;
                }
            }
        },
        null => {
            throw err();
        },
    }
    skip_ws();
    if (i >= inner.length()) {
        return; // value, no modifier
    }
    // A modifier: exactly one ASCII letter, immediately before the close.
    if (inner[i].is_ascii_alphabetic() && i + 1 == inner.length()) {
        return;
    }
    throw err();
}

function is_name_char(c: string) -> bool {
    c.is_ascii_alphanumeric() || c == "-" || c == "_" || !c.is_ascii()
}

function is_name_start(c: string) -> bool {
    c.is_ascii_alphabetic() || c == "_" || !c.is_ascii()
}

/// Whether `s` is a plain CSS identifier that needs no escaping — so a quoted
/// attribute value `"<s>"` can be emitted unquoted as `<s>` by simply dropping
/// the quotes. Matches dart-sass's `_isIdentifier` for the escape-free case:
/// a leading `-` must be followed by a name-start char (`--x`, `-1`, `-` alone
/// are not identifiers), the first significant char is a name-start, and the
/// rest are name chars. Strings containing escapes or non-name characters are
/// conservatively treated as non-identifiers (kept quoted) so nothing
/// regresses.
function is_plain_css_identifier(s: string) -> bool {
    let chars_buf = CharBuf_of(s);
    let chars: string[] = chars_buf.deref();
    if (chars.length() == 0) {
        return false;
    }
    let i = 0;
    if (chars[0] == "-") {
        i = 1;
    }
    match (chars.at(i)) {
        let c: string if is_name_start(c) => {
            i += 1;
        },
        _ => {
            return false;
        },
    }
    chars.slice(i, chars.length()).every((c: string) -> bool {
        is_name_char(c)
    })
}

/// Canonicalize the interior of an `[…]` attribute selector for emit, matching
/// dart-sass's `[name op value modifier]` form: whitespace around the operator
/// and at the edges is removed, and a trailing single-letter modifier is
/// preceded by exactly one space. The value text is preserved verbatim (no
/// unquoting). On any parse uncertainty the original (trimmed) text is kept so
/// no currently-passing selector regresses.
function normalize_attribute_text(inner: string) -> string {
    let chars_buf = CharBuf_of(inner);
    let chars: string[] = chars_buf.deref();
    let fallback = () -> string {
        root.std.trim(inner)
    };
    let i = 0;
    // PORT: `skip_ws(&mut i)` → a closure that advances the captured `i`.
    let skip_ws = () -> void {
        while (i < chars.length() && chars[i].is_whitespace()) {
            i += 1;
        }
    };
    skip_ws();
    // Namespace + name.
    let name_start = i;
    while (i < chars.length()) {
        let c = chars[i];
        if (c == "\\") {
            i += 2;
        } else if (is_name_char(c) || c == "|" || c == "*") {
            i += 1;
        } else {
            break;
        }
    }
    if (i == name_start) {
        return fallback();
    }
    let name: string = root.std.join(chars.slice(name_start, root.std.imin(i, chars.length())), "");
    skip_ws();
    if (i >= chars.length()) {
        return name; // `[name]`
    }
    // Operator.
    let op: string = match (chars[i]) {
        "=" => {
            i += 1;
            "="
        },
        "~" | "|" | "^" | "$" | "*" if chars.at(i + 1) == "=" => {
            let c = chars[i];
            i += 2;
            `${c}=`
        },
        _ => {
            return fallback();
        },
    };
    skip_ws();
    // Value (quoted string or unquoted run), preserved verbatim.
    let value_start = i;
    match (chars.at(i)) {
        "\"" | "'" => {
            i = skip_string(chars, i);
        },
        let _c: string => {
            while (i < chars.length()) {
                let c = chars[i];
                if (c == "\\") {
                    i += 2;
                } else if (c.is_whitespace()) {
                    break;
                } else {
                    i += 1;
                }
            }
        },
        null => {
            return fallback();
        },
    }
    let raw_value: string = root.std.join(chars.slice(value_start, root.std.imin(i, chars.length())), "");
    // dart-sass emits a quoted value unquoted when its content is a plain CSS
    // identifier (`[a="b"]` -> `[a=b]`). Only the escape-free, plain case is
    // unquoted here; anything needing re-escaping is kept verbatim.
    let value = unquote_plain_attribute_value(raw_value);
    skip_ws();
    if (i >= chars.length()) {
        return `${name}${op}${value}`;
    }
    // A single-letter modifier (case-insensitive) before the close.
    if (chars[i].is_ascii_alphabetic() && i + 1 == chars.length()) {
        return `${name}${op}${value} ${chars[i]}`;
    }
    fallback()
}

/// Drop the quotes from an attribute value when its content is a plain CSS
/// identifier; otherwise return it unchanged.
function unquote_plain_attribute_value(raw: string) -> string {
    let bytes_buf = CharBuf_of(raw);
    let bytes: string[] = bytes_buf.deref();
    if (bytes.length() >= 2) {
        let q = bytes[0];
        if ((q == "\"" || q == "'") && bytes[bytes.length() - 1] == q) {
            let content: string = root.std.join(bytes.slice(1, bytes.length() - 1), "");
            if (is_plain_css_identifier(content)) {
                return content;
            }
        }
    }
    raw
}

/// Whether any TOP-LEVEL style rule (not nested inside an at-rule such as
/// `@media`) contains the extend `target` simple selector. Used to detect an
/// `@extend` that crosses a media-query boundary.
function root_rule_contains_target(nodes: OutNode[], target: root.selector.Simple) -> bool {
    nodes.some((node: OutNode) -> bool {
        match (node) {
            let rule: OutNode_Rule => {
                rule.selectors.to_strings().some((s: string) -> bool {
                    let cs = root.selector.parse.parse_list(s);
                    if (cs != null) {
                        root.selector.list_contains_simple(cs, target)
                    } else {
                        false
                    }
                })
            },
            _ => false,
        }
    })
}

/// Walk the flattened output tree, rewriting each style-rule selector list per
/// the collected extensions and dropping rules whose every complex selector
/// still contains a placeholder. Recurses into at-rule bodies (e.g. `@media`),
/// but NOT into `@keyframes` (whose "selectors" are keyframe stops like `50%`).
/// Scoped extend pass: rewrite `nodes` belonging to module `scope` with the
/// extensions visible there (the module's own plus those of every module that
/// (transitively) loads it — dart-sass per-module ExtensionStores), recursing
/// into [`OutNode::ModuleScope`] wrappers with their own scope.
function rewrite_nodes_scoped(
    nodes: OutNode[],
    scope: string,
    all: root.selector.Extension[],
    origins: string[],
    closures: map<string, map<string, bool>>,
    order: ExtendOrderCtx,
) -> void {
    // The extensions whose origin can reach `scope` along load edges. A
    // private placeholder target (`%-name`/`%_name`) is module-private:
    // only extensions written in the same module may match it.
    // PORT: `zip().filter().map(clone).collect()` → an index loop. The entry
    // is shared rather than cloned: `build_extend_plan` only reads it, and its
    // `matched` flag is shared with the original in Rust too (`Rc<Cell>`).
    let visible: root.selector.Extension[] = [];
    let k = 0;
    while (k < all.length() && k < origins.length()) {
        let e = all[k];
        let o = origins[k];
        let c = closures.get(o);
        let reachable = o == scope
            || (
                if (c != null) {
                    c.has(scope)
                } else {
                    false
                }
            );
        let private_ok = match (e.target) {
            root.selector.Simple_Placeholder { _0: let n }
                if n.starts_with("-") || n.starts_with("_") => {
                o == scope
            },
            _ => true,
        };
        if (reachable && private_ok) {
            visible.push(e);
        }
        k += 1;
    }
    // dart builds ONE `ExtensionStore` per module scope, then extends each rule
    // against it incrementally. Build the scope-fixed extend plan ONCE here and
    // reuse it for every rule in this scope, rather than re-deriving the whole
    // transitive closure per rule (the old O(rules × extensions) blow-up).
    let empty_rank: map<string, int> = {};
    let plan = root.selector.build_extend_plan(
        visible,
        scope,
        if (order.has_import_clones) {
            empty_rank
        } else {
            order.rank_for(scope)
        },
        order.has_import_clones,
    );
    rewrite_with_scopes(nodes, plan, scope, all, origins, closures, order);
}

/// The walk shared by [`rewrite_nodes_scoped`]: rules use the current scope's
/// `plan` (the prebuilt extend closure); a nested [`OutNode::ModuleScope`]
/// re-enters with its own scope and its own plan.
/// The module-graph context for dart's store-merge ORDER: reverse load
/// edges (who loads whom) plus each origin's first registration index.
class ExtendOrderCtx {
    /// loaded module -> loaders (direct downstream modules).
    rev_deps: map<string, string[]>,
    /// origin -> smallest extension registration index (first-load rank).
    first_reg: map<string, int>,
    /// Module-loading `@import`s (clone scopes) are in play: dart merges the
    /// cloned subtree's extension stores into the IMPORTING module's own,
    /// which the pure-`@use` store-merge order below cannot express — fall
    /// back to the legacy fold order for the whole compile.
    has_import_clones: bool,
    /// The per-origin rank in `scope`'s downstream store-merge flatten:
    /// DFS from `scope` over reverse edges, visiting each level's direct
    /// downstream modules in DESCENDING first-load order (a later-loaded
    /// sibling's store registers earlier into the upstream's list), own
    /// store before its absorbed downstreams (pre-order).
    function rank_for(self, scope: string) -> map<string, int> {
        let rank: map<string, int> = {};
        let next = 0;
        let stack: string[] = [];
        let push_children = (of: string, stack: string[], rank: map<string, int>) -> void {
            let deps = self.rev_deps.get(of);
            let kids: string[] = if (deps != null) {
                deps.filter((k: string) -> bool {
                    !rank.has(k) && k != scope
                })
            } else {
                []
            };
            // Descending first-load; push reversed so the largest pops first.
            let _ = kids.sort_by_key((k: string) -> int {
                self.first_reg.get(k) ?? root.std.INT_MAX()
            });
            for (let k in kids) {
                stack.push(k);
            }
        };
        push_children(scope, stack, rank);
        while let m: string = stack.pop() {
            if (rank.has(m)) {
                continue;
            }
            let _ = rank.set(m, next);
            next += 1;
            push_children(m, stack, rank);
        }
        rank
    }
}

function rewrite_with_scopes(
    nodes: OutNode[],
    plan: root.selector.ExtendPlan,
    scope: string,
    all: root.selector.Extension[],
    origins: string[],
    closures: map<string, map<string, bool>>,
    order: ExtendOrderCtx,
) -> void {
    for (let node in nodes) {
        match (node) {
            let ms: OutNode_ModuleScope => {
                let key = ms.key;
                rewrite_nodes_scoped(ms.nodes, key, all, origins, closures, order);
            },
            let at: OutNode_AtRule if !is_keyframes_name(at.name) => {
                rewrite_with_scopes(at.body, plan, scope, all, origins, closures, order);
            },
            _ => {},
        }
    }
    rewrite_nodes(nodes, plan, scope);
}

function rewrite_nodes(nodes: OutNode[], plan: root.selector.ExtendPlan, scope: string) -> void {
    let i = 0;
    while (i < nodes.length()) {
        let drop = match (nodes[i]) {
            // Already rewritten (with its own scope) by rewrite_with_scopes;
            // drop the wrapper when nothing visible remains inside (so its
            // group separator doesn't leave a stray blank line). Post-eval,
            // group-end/pack-tight sentinels are inert (their eval-time
            // consumers have run), so a wrapper holding only markers — e.g. a
            // placeholder-only module whose rules were all dropped — counts
            // as empty too.
            let ms: OutNode_ModuleScope => {
                rewrite_nodes__invisible(ms.nodes)
            },
            let rule: OutNode_Rule => {
                match (
                    extend_selector_list(rule.selectors, rule.linebreaks, plan, scope, rule.extend_base)
                ) {
                    // No change → skip the clone + write-back entirely.
                    SelectorRewrite_Unchanged {} => false,
                    let changed: SelectorRewrite_Changed => {
                        // Line-break flags travel with their selectors (dart's
                        // ComplexSelector.lineBreak): an original keeps its
                        // flag, an extend product takes its extender's.
                        rule.linebreaks = changed._1;
                        rule.selectors = changed._0;
                        false
                    },
                    // Entirely placeholders → drop the rule.
                    SelectorRewrite_Drop {} => true,
                    _ => root.std.unreachable(),
                }
            },
            let at: OutNode_AtRule => {
                // Body rules were already rewritten by rewrite_with_scopes
                // (which knows the per-module scopes); only the empty-group
                // drop remains here. A conditional group rule
                // (`@media`/`@supports`) whose body is emptied by placeholder
                // removal produces no CSS, so drop it. A GENERIC at-rule
                // survives an empty body, whatever its name spells
                // (`@#{"media"} screen {}` is `@media screen {}` in dart).
                at.has_block && at.body.length() == 0 && at.kind.is_conditional()
            },
            _ => false,
        };
        if (drop) {
            let _ = nodes.remove_at(i);
            // A dropped rule takes its OWN group separator with it — the Blank
            // that follows it (pushed when the next group arrived because this
            // rule had ended a group) — never the Blank before it, which
            // belongs to the previous group and still separates that group
            // from whatever visible node comes next (dart: `previous` is the
            // last VISIBLE node, and its `isGroupEnd` decides the blank line).
            // Two dropped rules from one statement (`%p { a: 1; > * {} }`)
            // used to eat both blanks, one each. Only at the very end, with
            // nothing following, is the preceding Blank the dangling one.
            // Inert eval-time markers may trail the dropped rule; look past
            // them for what actually follows.
            // PORT: `nodes[i..].iter().position(..)` → an index scan (no slice copy).
            let k: int? = null;
            let p = i;
            while (p < nodes.length()) {
                if (!nodes[p].is_inert_marker()) {
                    k = p - i;
                    break;
                }
                p += 1;
            }
            match (k) {
                let kk: int if nodes[i + kk] is OutNode_Blank => {
                    let _ = nodes.remove_at(i + kk);
                },
                let _kk: int => {},
                null => {
                    // The preceding node may be an earlier dropped rule's
                    // `GroupEnd`; look back past inert markers too.
                    // PORT: `nodes[..i].iter().rposition(..)` → a descending index scan.
                    let j = i - 1;
                    while (j >= 0 && nodes[j].is_inert_marker()) {
                        j -= 1;
                    }
                    if (j >= 0) {
                        if (nodes[j] is OutNode_Blank) {
                            // Removing a PRECEDING node shifts `i` back with it.
                            let _ = nodes.remove_at(j);
                            i -= 1;
                        }
                    }
                },
            }
        } else {
            i += 1;
        }
    }
}

/// Nested `fn invisible` of `rewrite_nodes`.
function rewrite_nodes__invisible(nodes: OutNode[]) -> bool {
    nodes.every((n: OutNode) -> bool {
        match (n) {
            OutNode_Blank {} | OutNode_GroupEnd {} | OutNode_AtRootPackTight {} => true,
            let ms: OutNode_ModuleScope => rewrite_nodes__invisible(ms.nodes),
            _ => false,
        }
    })
}

/// True for `@keyframes` and its vendor-prefixed spellings, whose block
/// selectors are keyframe stops, not real selectors.
function is_keyframes_name(name: string) -> bool {
    let lower = root.std.ascii_lower(name);
    lower == "keyframes" || lower.ends_with("-keyframes")
}

/// Derive the default namespace for `@use "<url>"`: the final path component,
/// with any leading `_` removed and everything from the first `.` (i.e. all
/// extensions) discarded. dart-sass rejects a result that is not a valid Sass
/// identifier.
function default_namespace(url: string, pos: root.scanner.Pos) -> string {
    // PORT: `url.rsplit('/').next()` is the text after the last `/` (all of
    // `url` when it has none).
    let tail = root.std.rsplit_once(url, "/");
    let last = if (tail != null) {
        tail._1
    } else {
        url
    };
    let last = root.std.strip_prefix(last, "_") ?? last;
    // Strip every extension: the namespace is the basename up to its first dot.
    let split = root.std.split_once(last, ".");
    let stem = if (split != null) {
        split._0
    } else {
        last
    };
    if (!is_valid_namespace(stem)) {
        throw root.error.Error.at(
            `The default namespace "${stem}" is not a valid Sass identifier.`,
            pos,
        );
    }
    stem
}

/// Build a predicate deciding whether an upstream `$variable` (by bare name) is
/// re-exported through a `@forward`'s `show`/`hide` clause.
function forward_var_visibility(
    show: root.ast.ForwardMember[]?,
    hide: root.ast.ForwardMember[]?,
) -> (string) -> bool throws unknown {
    let show = member_set(show, true);
    let hide = member_set(hide, true);
    (name: string) -> bool {
        let n = normalize_var_name(name);
        if let s: map<string, bool> = show {
            return s.has(n);
        }
        if let h: map<string, bool> = hide {
            return !h.has(n);
        }
        true
    }
}

/// Canonicalize a Sass variable name: `-` and `_` are interchangeable, so the
/// canonical form replaces every `_` with `-` (dart-sass dash-insensitivity).
function normalize_var_name(name: string) -> string {
    // `-`/`_` are interchangeable; borrow when there is nothing to replace
    // (the overwhelmingly common case).
    if (name.includes("_")) {
        name.replace_all("_", "-")
    } else {
        name
    }
}

/// Whether a member name is private (dart-sass: a leading `-` or `_`), so it is
/// not accessible across module boundaries.
function is_private_member(name: string) -> bool {
    name.starts_with("-") || name.starts_with("_")
}

/// Whether `module` exposes `name` as a built-in mixin. dart-sass's `sass:meta`
/// module defines the `load-css` and `apply` mixins; no other built-in module
/// exposes a mixin. Matched dash/underscore-insensitively.
function is_builtin_mixin(module: string, name: string) -> bool {
    if (module != "meta") {
        return false;
    }
    match (normalize_arg_name(name)) {
        "load-css" | "apply" => true,
        _ => false,
    }
}

/// Collect the names from a `@forward` `show`/`hide` member list, selecting
/// either the `$variable` entries (`vars == true`) or the function/mixin names.
/// Names are stored in canonical (dashed) form for dash-insensitive matching.
function member_set(members: root.ast.ForwardMember[]?, vars: bool) -> map<string, bool>? {
    if (members == null) {
        return null;
    }
    root.std.set_of(
        members.filter_map((m: root.ast.ForwardMember) -> string? {
            match (m) {
                let v: root.ast.ForwardMember_Var if vars => normalize_var_name(v._0),
                let n: root.ast.ForwardMember_Name if !vars => normalize_var_name(n._0),
                _ => null,
            }
        }),
    )
}

/// Whether `s` is a valid Sass identifier usable as a module namespace.
function is_valid_namespace(s: string) -> bool {
    let chars = s.chars();
    match (chars.at(0)) {
        let c: string if c == "_" || c == "-" || c.is_ascii_alphabetic() || !c.is_ascii() => {},
        _ => {
            return false;
        },
    }
    chars.slice(1, chars.length()).every((c: string) -> bool {
        c == "_" || c == "-" || c.is_ascii_alphanumeric() || !c.is_ascii()
    })
}

/// The outcome of extending one rule's selector list.
interface SelectorRewrite {}

/// The selector needs no change — leave the rule's selectors in place
/// (no clone, no write-back). The common case on extend-free stylesheets.
class SelectorRewrite_Unchanged {
    implements SelectorRewrite {}
}

/// The selector was extended/placeholder-stripped — replace it.
class SelectorRewrite_Changed {
    _0: RuleSelectors,
    _1: bool[],
    implements SelectorRewrite {}
}

/// Every complex selector is still a placeholder after extension, so the
/// rule emits no CSS — drop it.
class SelectorRewrite_Drop {
    implements SelectorRewrite {}
}

/// Compute the extended selector list for a rule. [`SelectorRewrite::Drop`]
/// when, after extension, every complex selector still contains a placeholder
/// (the rule emits no CSS); [`SelectorRewrite::Unchanged`] when the selector
/// needs no change (so the caller skips the clone + write-back entirely).
///
/// Phase 1d: the engine works on the typed [`crate::selector::Complex`] model
/// and the result is carried as [`RuleSelectors::Parsed`] — emit renders it
/// directly, so there is no `join(", ")` + `parse_list` round trip back to
/// strings. The fast path (no `@extend` and no placeholder) and the
/// unparseable fallback keep the rule's original [`RuleSelectors::Raw`] strings
/// untouched, byte-for-byte.
function extend_selector_list(
    selectors: RuleSelectors,
    breaks: bool[],
    plan: root.selector.ExtendPlan,
    scope: string,
    extend_base: int,
) -> SelectorRewrite {
    // Fast path: no extensions and no placeholder → the selector is untouched.
    // Crucially this leaves selectors we don't model (keyframe stops are handled
    // separately, but also unusual selectors) byte-for-byte intact.
    //
    // The placeholder probe is a full `%` scan of every selector of the rule, and
    // it is only ever read here — so it runs only when `plan.is_empty()` has
    // already said the answer can matter. With extensions in scope this pass has
    // to parse and extend regardless, and the scan was pure waste.
    let has_placeholder = () -> bool {
        match (selectors) {
            let raw: RuleSelectors_Raw => {
                raw._0.some((s: string) -> bool {
                    s.includes("%")
                })
            },
            let parsed: RuleSelectors_Parsed => {
                parsed._0.some((c: root.selector.Complex) -> bool {
                    root.selector.complex_has_placeholder(c)
                })
            },
            _ => root.std.unreachable(),
        }
    };
    if (plan.is_empty() && !has_placeholder()) {
        return SelectorRewrite_Unchanged {  };
    }
    // Parse the rule's selectors into the typed model exactly once. A `Raw`
    // rule (the only shape an evaluated rule arrives in) is joined and parsed
    // here; a `Parsed` rule (a re-entered already-rewritten list, not produced
    // today) is borrowed directly.
    // PORT: no `parsed_owned` slot needed — arrays are references.
    let parsed: root.selector.Complex[] = match (selectors) {
        let raw: RuleSelectors_Raw => {
            let joined = root.std.join(raw._0, ", ");
            let p = root.selector.parse.parse_list(joined);
            if (p == null) {
                // Unparseable selector: never lose it; leave untouched.
                return SelectorRewrite_Unchanged {  };
            }
            p
        },
        let v: RuleSelectors_Parsed => v._0,
        _ => root.std.unreachable(),
    };
    let result = root.selector.extend_selectors(parsed, breaks, plan, scope, extend_base);
    if (result.all_placeholders) {
        return SelectorRewrite_Drop {  };
    }
    SelectorRewrite_Changed { _0: RuleSelectors_Parsed { _0: result.selectors }, _1: result.breaks }
}

/// For each non-empty top-level comma part of a selector list, whether the
/// emitted complex selector should begin on its own line — parallel to the
/// parts `resolve_selectors` keeps.
///
/// dart-sass carries a per-complex `lineBreak` flag set when a newline precedes
/// the part in source (`a,\nb`). During parent resolution that flag survives for
/// an *implicit*-parent part (`parent.lineBreak || child.lineBreak`), but a part
/// that *references* the parent with `&` takes the parent complex's flag instead
/// and drops its own. We don't track parent line-breaks, so for a `&`-part in a
/// nested rule we conservatively report `false` (correct whenever the governing
/// parent is the first/unbroken one, and never emits a break dart-sass wouldn't).
function comma_linebreaks(sel: string, nested: bool) -> bool[] {
    // An EMPTY comma part (a stray trailing/doubled comma) is dropped, but a
    // newline inside it still belongs to the next real part:
    // `#foo #bar,,\n,#baz #boom,` keeps `#baz #boom` on its own line.
    let out: bool[] = [];
    let pending_nl = false;
    let segs = split_commas(sel).deref();
    // PORT: `chars().take_while(is_whitespace).any(|c| c == '\n')` → a closure
    // over the chars (reversed for the trailing run).
    let ws_run_has_nl = (cs: string[]) -> bool {
        for (let c in cs) {
            if (!c.is_whitespace()) {
                return false;
            }
            if (c == "\n") {
                return true;
            }
        }
        false
    };
    let i = 0;
    while (i < segs.length()) {
        let seg = segs[i];
        if (root.std.trim(seg) == "") {
            pending_nl = pending_nl || (i > 0 && seg.includes("\n"));
            i += 1;
            continue;
        }
        // dart marks a complex as line-broken when ANY newline sits between
        // it and the previous one — including BEFORE the comma (`a\n, b`).
        let leading_nl = ws_run_has_nl(seg.chars());
        let prev_trailing_nl = i > 0 && ws_run_has_nl(segs[i - 1].chars().reverse());
        let newline_before = i > 0 && (leading_nl || prev_trailing_nl);
        out.push((newline_before || pending_nl) && !(nested && part_has_parent_ref(seg)));
        pending_nl = false;
        i += 1;
    }
    out
}

/// Whether a selector comma-part contains a top-level parent reference `&`
/// (not inside `[…]` or a quoted string). Interpolation has already been
/// resolved into `sel` by the time this runs, so a `&` here is a real parent
/// reference.
function part_has_parent_ref(part: string) -> bool {
    let bracket = 0;
    let quote: string? = null;
    // PORT: the `chars` iterator → an index cursor (`chars.next()` → `ci += 1`).
    let chars = part.chars();
    let ci = 0;
    while (ci < chars.length()) {
        let c = chars[ci];
        ci += 1;
        match (quote) {
            let q: string => {
                if (c == "\\") {
                    ci += 1;
                } else if (c == q) {
                    quote = null;
                }
            },
            null => {
                match (c) {
                    // `\&` is an ampersand in an identifier, not a parent
                    // reference.
                    "\\" => {
                        ci += 1;
                    },
                    "\"" | "'" => {
                        quote = c;
                    },
                    "[" => {
                        bracket += 1;
                    },
                    "]" => {
                        bracket = root.std.imax(bracket - 1, 0);
                    },
                    "&" if bracket == 0 => {
                        return true;
                    },
                    _ => {},
                }
            },
        }
    }
    false
}

/// The char index of the first `@` outside quoted strings in a resolved
/// selector, if any — `@` has no legal position in a CSS selector.
function find_unquoted_at(sel: string) -> int? {
    // `@` is ASCII: no `@` byte means no occurrence at all — skip the
    // quote-tracking walk that otherwise runs for every resolved selector.
    if (!sel.includes("@")) {
        return null;
    }
    let quote: string? = null;
    // PORT: the `chars().enumerate()` iterator → an index cursor
    // (`iter.next()` → `i += 1`).
    let chars = sel.chars();
    let i = 0;
    while (i < chars.length()) {
        let c = chars[i];
        match (quote) {
            let q: string => {
                if (c == "\\") {
                    i += 1;
                } else if (c == q) {
                    quote = null;
                }
            },
            null => {
                match (c) {
                    "\"" | "'" => {
                        quote = c;
                    },
                    "\\" => {
                        i += 1;
                    },
                    "@" => {
                        return i;
                    },
                    _ => {},
                }
            },
        }
        i += 1;
    }
    null
}

/// Replace top-level `&` parent references with `parent`. A `&` inside `[…]`
/// or a quoted string is literal text (issue_2291 `[str="&"]` keeps its
/// ampersand); one inside pseudo parentheses is still a real reference.
function replace_parent_refs(part: string, parent: string) -> string {
    let out = root.std.StrBuf.with_capacity(part.length() + parent.length());
    let bracket = 0;
    let quote: string? = null;
    // PORT: the `chars` iterator → an index cursor (`chars.next()` → `ci += 1`).
    let chars = part.chars();
    let ci = 0;
    while (ci < chars.length()) {
        let c = chars[ci];
        ci += 1;
        match (quote) {
            let q: string => {
                out.push(c);
                if (c == "\\") {
                    if (ci < chars.length()) {
                        out.push(chars[ci]);
                        ci += 1;
                    }
                } else if (c == q) {
                    quote = null;
                }
            },
            null => {
                match (c) {
                    "\\" => {
                        out.push(c);
                        if (ci < chars.length()) {
                            out.push(chars[ci]);
                            ci += 1;
                        }
                    },
                    "\"" | "'" => {
                        quote = c;
                        out.push(c);
                    },
                    "[" => {
                        bracket += 1;
                        out.push(c);
                    },
                    "]" => {
                        bracket = root.std.imax(bracket - 1, 0);
                        out.push(c);
                    },
                    "&" if bracket == 0 => {
                        out.push_str(parent);
                    },
                    _ => {
                        out.push(c);
                    },
                }
            },
        }
    }
    out.as_str()
}

/// Count a part's TOP-LEVEL `&` references (outside parens/brackets) and split
/// it into the segments between them. With k >= 2 refs the part expands to the
/// parents' k-fold cartesian product (`& &` under `ul, ol` is
/// `ul ul, ul ol, ol ul, ol ol`, issue_1710); with fewer, a cheaper path
/// resolves it and there is nothing to split, so `None` comes back having
/// allocated nothing at all — a part with one `&` or none is the common case.
/// The segments are borrowed: they are the substrings between the references,
/// character for character.
function split_parent_refs(part: string) -> string[]? {
    let first: int? = null;
    // Stays empty — and unallocated — until a SECOND reference proves the part
    // is cartesian; only then does the first one become a cut too.
    let cuts: int[] = [];
    let depth = 0;
    let quote: string? = null;
    let escaped = false;
    // PORT: `char_indices()` → char offsets (the segments are sliced by char
    // offsets below, so they are the same substrings).
    let next_i = 0;
    for (let c in part.chars()) {
        let i = next_i;
        next_i += 1;
        if let q: string = quote {
            // `\"` does not end a `"`-quoted value, and a quote that ends
            // early would swallow the `]` after it and hide every top-level
            // `&` that follows.
            if (escaped) {
                escaped = false;
                continue;
            }
            if (c == "\\") {
                escaped = true;
            } else if (c == q) {
                quote = null;
            }
            continue;
        }
        // The character a backslash escapes is skipped by the branch above on
        // the next turn, so `\&` is a literal rather than a reference.
        if (escaped) {
            escaped = false;
            continue;
        }
        match (c) {
            "\\" => {
                escaped = true;
            },
            "\"" | "'" => {
                quote = c;
            },
            "(" | "[" => {
                depth += 1;
            },
            ")" | "]" => {
                depth -= 1;
            },
            "&" if depth == 0 => {
                match (first) {
                    null => {
                        first = i;
                    },
                    let f: int => {
                        if (cuts.length() == 0) {
                            cuts.push(f);
                        }
                        cuts.push(i);
                    },
                }
            },
            _ => {},
        }
    }
    if (cuts.length() == 0) {
        return null;
    }
    let segments: string[] = [];
    let start = 0;
    for (let cut in cuts) {
        segments.push(part.slice(start, cut));
        start = cut + 1; // '&' is one character
    }
    segments.push(part.slice(start, part.length()));
    segments
}

/// One rule's resolved selector list: the complexes, and their source
/// line-break flags only when the caller asked for them. A selector list with
/// no newline in it, under parents that carry no break of their own, has
/// all-false flags — which every consumer already reads off an EMPTY vec — so
/// on that shape, which is nearly every rule, the flags are not collected at
/// all. Keeping the two as separate lists is also what lets the caller take the
/// complexes as they are: paired into tuples they would have to be unzipped
/// again, into two fresh vectors, one of which it then drops.
class ResolvedSelectors {
    sels: string[],
    /// Empty unless `flags`; parallel to `sels` when collected.
    lbs: bool[],
    flags: bool,
    /// True unless **every** selector in `sels` was proved canonical by
    /// [`canonical_plain`]. Because that predicate's byte set is disjoint from
    /// `has_bogus_trigger`'s `> + ~ (`, `false` *proves* no selector in the
    /// list can be a bogus-combinator complex — which is what lets the emitter
    /// skip `complex_selector_block_is_bogus` for the whole list instead of
    /// scanning every byte of every selector. `true` means "not proved", never
    /// "has one".
    maybe_bogus: bool,
    /// True if any selector in `sels` contains a `%`. Only a `%`-bearing
    /// selector can be a placeholder rule, so `false` lets the emitter skip its
    /// per-selector placeholder bookkeeping outright.
    any_percent: bool,
    function new(flags: bool) -> ResolvedSelectors {
        ResolvedSelectors {
            sels: [],
            lbs: [],
            flags: flags,
            maybe_bogus: false,
            any_percent: false,
        }
    }

    function len(self) -> int {
        self.sels.length()
    }

    function reserve(self, additional: int) -> void {
        // PORT: `Vec::reserve` is a capacity hint; BAML arrays grow on demand, so
        // `self.sels.reserve(additional)` and (when `self.flags`)
        // `self.lbs.reserve(additional)` have nothing to do.
    }

    /// Push a selector that is already normalized and whose facts are already
    /// accounted for — the row-of-rows merge, where the strings move across
    /// from rows whose flags arrive via [`ResolvedSelectors::absorb`]. Every
    /// other caller goes through [`ResolvedSelectors::push_owned`] or
    /// [`ResolvedSelectors::push_ref`], which is what keeps the flags honest:
    /// normalizing inside the push is the only way they stay free.
    function push_merged(self, sel: string, lb: bool) -> void {
        self.sels.push(sel);
        if (self.flags) {
            self.lbs.push(lb);
        }
    }

    /// Normalize an owned selector and push it, recording what its canonical
    /// scan saw.
    function push_owned(self, sel: string, lb: bool) -> void {
        self.push_normalized(normalize_selector_owned_facts(sel), lb);
    }

    /// Normalize a borrowed selector and push it, recording what its canonical
    /// scan saw.
    function push_ref(self, sel: string, lb: bool) -> void {
        self.push_normalized(normalize_selector_facts(sel), lb);
    }

    function push_normalized(self, n: Normalized, lb: bool) -> void {
        self.maybe_bogus = self.maybe_bogus || !n.canonical;
        self.any_percent = self.any_percent || n.percent;
        self.push_merged(n.sel, lb);
    }

    /// OR another list's facts into this one. Used by the row-of-rows merge,
    /// whose selectors are pushed with [`ResolvedSelectors::push_merged`] and so
    /// carry no facts of their own.
    function absorb(self, other: ResolvedSelectors) -> void {
        self.maybe_bogus = self.maybe_bogus || other.maybe_bogus;
        self.any_percent = self.any_percent || other.any_percent;
    }
}

/// Resolve a selector against its parents with dart's `implicitParent` switch: inside
/// `@at-root` (before the first nested style rule) a part WITHOUT `&` stays
/// at the root instead of joining the parent, while `&` still substitutes.
/// Also derives each output complex's source line-break flag (dart carries
/// `lineBreak` on the ComplexSelector object): a part WITHOUT `&` keeps its
/// own flag OR'd with the joined parent's; a part WITH `&` drops its own flag
/// and takes the substituted parent's (dart rebuilds those complexes from a
/// `lineBreak: false` base); a k>=2 cartesian combo ORs its chosen parents'.
/// The flags are only derived when `want_linebreaks` says the caller has a use
/// for them.
function resolve_selectors_opt(
    sel: string,
    parents: string[],
    implicit_parent: bool,
    part_lbs: bool[],
    parent_lbs: bool[],
    want_linebreaks: bool,
) -> ResolvedSelectors {
    // Borrowed: every part is a contiguous substring of `sel` and nothing below
    // needs to own one, so a rule pays no `String` per selector part. A
    // selector with no top-level comma is a single part, which is the common
    // shape of a nested rule, and it reads out of a fixed slot instead of a
    // heap vector.
    let parts: string[] = match (split_commas(sel)) {
        let one: Segments_One => {
            let single = [trim_selector_part(one._0)];
            if (single[0] == "") {
                []
            } else {
                single
            }
        },
        let v: Segments_Many => {
            v._0
                .map((p: string) -> string {
                    trim_selector_part(p)
                })
                .filter((p: string) -> bool {
                    p != ""
                })
        },
        _ => root.std.unreachable(),
    };
    // dart: a parent that ends in a combinator can't substitute into a `&`
    // that is part of a compound (`.a > { &.b {} }` errors; `& .b` is fine).
    let check_compound_parent = (part: string, parent: string) -> void {
        let trimmed = root.std.trim_end(parent);
        let tail = root.std.last_char(trimmed);
        if (!(tail == ">" || tail == "+" || tail == "~")) {
            return;
        }
        let chars_buf = CharBuf_of(part);
        let chars: string[] = chars_buf.deref();
        let skip = false;
        let bracket = 0;
        let quote: string? = null;
        let next_i = 0;
        for (let c in chars) {
            let i = next_i;
            next_i += 1;
            if (skip) {
                skip = false;
                continue;
            }
            if (c == "\\") {
                skip = true;
                continue;
            }
            if let q: string = quote {
                if (c == q) {
                    quote = null;
                }
                continue;
            }
            match (c) {
                "\"" | "'" => {
                    quote = c;
                    continue;
                },
                "[" => {
                    bracket += 1;
                },
                "]" => {
                    bracket = root.std.imax(bracket - 1, 0);
                },
                _ => {},
            }
            // An `&` inside an attribute is not a parent reference.
            if (c == "&" && bracket == 0) {
                let next = chars.at(i + 1);
                if (next != null) {
                    if (
                        next.is_alphanumeric()
                            || next == "."
                            || next == "#"
                            || next == ":"
                            || next == "["
                            || next == "%"
                            || next == "\\"
                            || next == "-"
                            || next == "_"
                    ) {
                        throw root.error.Error.unpositioned(
                            `Selector "${trimmed}" can't be used as a parent in a compound selector.`,
                        );
                    }
                }
            }
        }
    };
    // A `&` that sits only inside pseudo arguments takes the WHOLE parent
    // list in place (dart: `:not(&-c)` under `.a, .b` is `:not(.a-c, .b-c)`,
    // ONE complex — no cartesian expansion). A part with any top-level `&`
    // (or a pseudo-`&` glued to a non-suffix simple) uses the normal path.
    let substitute_pseudo_refs = (part: string) -> string? {
        if (!part.includes("&")) {
            return null;
        }
        let chars_buf = CharBuf_of(part);
        let chars: string[] = chars_buf.deref();
        let depth = 0;
        let bracket = 0;
        let quote: string? = null;
        let out = root.std.StrBuf.new();
        let i = 0;
        let replaced = false;
        while (i < chars.length()) {
            let c = chars[i];
            if let q: string = quote {
                out.push(c);
                i += 1;
                if (c == "\\") {
                    let n = chars.at(i);
                    if (n != null) {
                        out.push(n);
                        i += 1;
                    }
                } else if (c == q) {
                    quote = null;
                }
                continue;
            }
            match (c) {
                "\\" => {
                    out.push(c);
                    i += 1;
                    let n = chars.at(i);
                    if (n != null) {
                        out.push(n);
                        i += 1;
                    }
                    continue;
                },
                "\"" | "'" => {
                    quote = c;
                },
                "[" => {
                    bracket += 1;
                },
                "]" => {
                    bracket = root.std.imax(bracket - 1, 0);
                },
                "(" => {
                    depth += 1;
                },
                ")" => {
                    depth -= 1;
                },
                // An `&` inside an attribute is text: copy it and let the
                // normal path handle the part.
                "&" if bracket > 0 => {},
                "&" => {
                    if (depth == 0) {
                        return null;
                    }
                    // Collect an identifier suffix (`&-c`); any other glued
                    // simple (`&.x`, `&:h`) bails to the normal path.
                    let suffix = "";
                    let j = i + 1;
                    while (
                        j < chars.length()
                            && (chars[j].is_alphanumeric() || chars[j] == "-" || chars[j] == "_")
                    ) {
                        suffix = suffix + chars[j];
                        j += 1;
                    }
                    let glued = chars.at(j);
                    if (
                        glued == "."
                            || glued == "#"
                            || glued == ":"
                            || glued == "["
                            || glued == "%"
                            || glued == "\\"
                            || glued == "&"
                    ) {
                        return null;
                    }
                    let expansion = parents
                        .map((p: string) -> string {
                            `${p}${suffix}`
                        })
                        .join(", ");
                    out.push_str(expansion);
                    replaced = true;
                    i = j;
                    continue;
                },
                _ => {},
            }
            out.push(c);
            i += 1;
        }
        if (replaced) {
            out.as_str()
        } else {
            null
        }
    };
    let expand_cartesian = (segments: string[], result: ResolvedSelectors) -> void {
        let k = segments.length() - 1;
        let n = parents.length();
        let idx = baml.Array.filled(k, 0);
        while (true) {
            let s = "";
            let i = 0;
            for (let seg in segments.slice(0, k)) {
                s = s + seg;
                s = s + parents[idx[i]];
                i += 1;
            }
            s = s + segments[k];
            // A `&` nested in pseudo parens is NOT a cartesian position (the
            // split counts depth-0 refs only) but still substitutes — with
            // the whole parent list, like any pseudo-`&`
            // (quasar: `&-container:not(&--mini-animate) &--mini`).
            let s = substitute_pseudo_refs(s) ?? s;
            // The combo's flag ORs its chosen parents' flags (mastodon's
            // adjacent-state selectors break per combo, not per template).
            let flag = idx.some((pi: int) -> bool {
                parent_lbs.at(pi) ?? false
            });
            result.push_owned(s, flag);
            // Increment with the LAST ref fastest (dart's order).
            let j = k;
            while (true) {
                if (j == 0) {
                    return;
                }
                j -= 1;
                idx[j] += 1;
                if (idx[j] < n) {
                    break;
                }
                idx[j] = 0;
            }
        }
    };
    let result = ResolvedSelectors.new(want_linebreaks);
    if (parents.length() == 0) {
        // At the document root (no enclosing style rule) a parent selector `&`
        // has no parent to substitute, so dart-sass keeps it literal: `& {a: b}`
        // emits `& {\u{2026}}` and `&.foo {\u{2026}}` emits `&.foo {\u{2026}}`. (A `&`-with-suffix
        // such as `&foo` is rejected earlier by `validate_selector`.)
        result.reserve(parts.length());
        let pi = 0;
        for (let part in parts) {
            result.push_ref(part, part_lbs.at(pi) ?? false);
            pi += 1;
        }
    } else if (!implicit_parent) {
        // dart resolves per complex: a part with `&` expands across the
        // parents; a part without stays at the root exactly once.
        let part_i = 0;
        for (let part in parts) {
            let s = substitute_pseudo_refs(part);
            if (s != null) {
                result.push_owned(s, false);
            } else {
                let segments = split_parent_refs(part);
                if (segments != null) {
                    for (let parent in parents) {
                        check_compound_parent(part, parent);
                    }
                    expand_cartesian(segments, result);
                } else if (part_has_parent_ref(part)) {
                    let pi = 0;
                    for (let parent in parents) {
                        check_compound_parent(part, parent);
                        result.push_owned(
                            replace_parent_refs(part, parent),
                            parent_lbs.at(pi) ?? false,
                        );
                        pi += 1;
                    }
                } else {
                    result.push_ref(part, part_lbs.at(part_i) ?? false);
                }
            }
            part_i += 1;
        }
    } else {
        // dart `resolveParentSelectors`: each part resolves to its own ROW of
        // complexes, and the final list is `flattenVertically(rows)` —
        // column-major across the parts. For `&`-less and single-`&` parts
        // (rows of exactly `parents.len()`) that is the familiar parent-major
        // order; a part with k >= 2 top-level refs contributes a row of
        // `parents.len()^k` combos, interleaved column-by-column with its
        // sibling parts (mastodon's `&:hover + &:is(...)` lists).
        // One part's row, appended to `out`.
        let resolve_row = (part_i: int, part: string, out: ResolvedSelectors) -> void {
            // A pseudo-only `&` part resolves ONCE (whole parent list in
            // place): a single-entry row.
            let s = substitute_pseudo_refs(part);
            if (s != null) {
                out.push_owned(s, false);
                return;
            }
            let segments = split_parent_refs(part);
            if (segments != null) {
                for (let parent in parents) {
                    check_compound_parent(part, parent);
                }
                expand_cartesian(segments, out);
                return;
            }
            let has_ref = part_has_parent_ref(part);
            let pi = 0;
            for (let parent in parents) {
                let parent_lb = parent_lbs.at(pi) ?? false;
                let combined_flag = if (has_ref) {
                    check_compound_parent(part, parent);
                    // A `&` part drops its own source flag (dart rebuilds the
                    // complex from a lineBreak:false base) and takes the
                    // substituted parent's.
                    root.std.Tuple2 { _0: replace_parent_refs(part, parent), _1: parent_lb }
                } else {
                    // The joined length is known, so the buffer is sized once
                    // here instead of growing out of an empty `format!`.
                    let combined = parent + " " + part;
                    root.std.Tuple2 {
                        _0: combined,
                        _1: (part_lbs.at(part_i) ?? false) || parent_lb,
                    }
                };
                out.push_owned(combined_flag._0, combined_flag._1);
                pi += 1;
            }
        };
        // A single part is a single row, and flattening one row leaves it in
        // its own order: it resolves straight into the result, without the
        // row-of-rows scaffolding the general case needs.
        if (parts.length() == 1) {
            let part = parts[0];
            result.reserve(parents.length());
            resolve_row(0, part, result);
        } else {
            let rows: ResolvedSelectors[] = [];
            let part_i = 0;
            for (let part in parts) {
                let row = ResolvedSelectors.new(want_linebreaks);
                row.reserve(parents.length());
                resolve_row(part_i, part, row);
                rows.push(row);
                part_i += 1;
            }
            let longest = 0;
            for (let r in rows) {
                longest = root.std.imax(longest, r.len());
            }
            result.reserve(
                rows.reduce(
                    (acc: int, r: ResolvedSelectors) -> int {
                        acc + r.len()
                    },
                    0,
                ),
            );
            // The strings move across already normalized, so their facts come
            // from the rows that normalized them.
            for (let row in rows) {
                result.absorb(row);
            }
            for (let j in baml.iter.Range.new(0, longest)) {
                // Each slot is read exactly once, so the string moves out instead
                // of being cloned; what stays behind is an empty `String`, which
                // owns no buffer, and `rows` is dropped right after.
                // PORT: `std::mem::take(sel)` → read the slot (strings are values).
                for (let row in rows) {
                    let sel = row.sels.at(j);
                    if (sel != null) {
                        let lb = row.lbs.at(j) ?? false;
                        result.push_merged(sel, lb);
                    }
                }
            }
        }
    }
    result
}

/// `s.trim()` without an allocation when `s` has no surrounding whitespace —
/// the common case for an evaluated property name, which is trimmed on every
/// declaration and almost never has anything to lose. Hands back the same
/// shared buffer (`trim` removed nothing → same length) instead of copying the
/// bytes into a fresh one.
function trim_shared(s: string) -> string {
    if (root.std.trim(s).length() == s.length()) {
        s
    } else {
        root.std.trim(s)
    }
}

/// The segments [`split_commas`] found. The overwhelmingly common shape has no
/// top-level comma at all, and that case is the whole reason this type exists:
/// it keeps the single segment inline instead of putting it in a one-element
/// `Vec`. Both variants deref to a slice, so a caller reads either shape as
/// `&[&str]`.
interface Segments {
    function deref(self) -> string[] throws never {
        match (self) {
            let one: Segments_One => [one._0],
            let many: Segments_Many => many._0,
            _ => root.std.unreachable(),
        }
    }
}

class Segments_One {
    _0: string,
    implements Segments {}
}

class Segments_Many {
    _0: string[],
    implements Segments {}
}

/// Split `s` on top-level commas (paren/bracket depth 0), returning borrowed
/// slices of `s` — no per-part allocation. Commas inside `(...)`/`[...]` stay
/// within their part. Each part is a contiguous substring of `s`, so callers
/// that need an owned `String` call `.to_string()` themselves.
function split_commas(s: string) -> Segments {
    // No comma anywhere means one segment, whatever the nesting structure.
    if (!s.includes(",")) {
        return Segments_One { _0: s };
    }
    let out: string[] = [];
    let paren = 0;
    let bracket = 0;
    let start = 0;
    let escaped = false;
    // PORT: `char_indices()` → char offsets (the parts are sliced by char
    // offsets too, so they are the same substrings).
    let next_idx = 0;
    for (let c in s.chars()) {
        let idx = next_idx;
        next_idx += 1;
        // `\,` is a comma IN AN IDENTIFIER, not a list separator.
        if (escaped) {
            escaped = false;
            continue;
        }
        match (c) {
            "\\" => {
                escaped = true;
            },
            "(" => {
                paren += 1;
            },
            ")" => {
                paren -= 1;
            },
            "[" => {
                bracket += 1;
            },
            "]" => {
                bracket -= 1;
            },
            "," if paren == 0 && bracket == 0 => {
                out.push(s.slice(start, idx));
                start = idx + 1; // ',' is one character
            },
            _ => {},
        }
    }
    out.push(s.slice(start, s.length()));
    Segments_Many { _0: out }
}

/// Collapse whitespace and put single spaces around `>`/`+`/`~`
/// combinators (at bracket depth 0), matching dart-sass's selector
/// serialization. Also separates adjacent compounds: a bare type/element
/// selector appearing mid-compound (`[a]b`, `:not(.x)b`) is joined to the
/// preceding simple with a descendant combinator (`[a] b`), matching
/// dart-sass's `[adjacent-compounds]` normalization.
function normalize_selector(s: string) -> string {
    normalize_selector_facts(s).sel
}

/// A normalized selector plus the two facts its canonical scan yielded **for
/// free**. `canonical` is a *proof* that the selector carries no
/// bogus-combinator trigger, because [`canonical_plain`]'s byte set is disjoint
/// from `has_bogus_trigger`'s `> + ~ (`; `percent` is the placeholder probe the
/// emitter would otherwise repeat per selector. Both fall out of a loop that had
/// to run anyway to decide the fast path, which is the entire reason they are
/// collected here instead of scanned for downstream.
class Normalized {
    sel: string,
    /// The selector was *proved* canonical. `false` means "not proved" — it
    /// says nothing about whether a trigger byte is actually present.
    canonical: bool,
    /// The normalized selector contains a `%`.
    percent: bool,
}

/// [`normalize_selector`], reporting what the canonical scan saw.
function normalize_selector_facts(s: string) -> Normalized {
    // Fast path: already-canonical selectors skip the two char-vector
    // materializations below. The `debug_assert`s ARE the proof of that: every
    // debug-built test run and every debug spec run re-checks fast == slow on
    // every call, which is the harness this fast path was originally validated
    // against and is cheaper to keep than to rebuild.
    match (canonical_plain(s)) {
        let percent: bool => {
            debug_assert_canonical(s, percent);
            Normalized { sel: s, canonical: true, percent: percent }
        },
        null => {
            let sel = normalize_selector_slow(s);
            let percent = sel.includes("%");
            Normalized { sel: sel, canonical: false, percent: percent }
        },
    }
}

/// The three invariants the canonical fast path rests on, checked on every call
/// in a debug build and compiled out of release: the normalizer would have
/// returned the selector unchanged, the scan's `%` answer matches a plain
/// search, and the accepted byte set really is disjoint from the
/// bogus-combinator triggers — the last one so that widening
/// [`canonical_plain`] cannot silently break `ResolvedSelectors::maybe_bogus`.
function debug_assert_canonical(s: string, percent: bool) -> void {
    // PORT: `debug_assert*!` are compiled out of release builds; kept as comments.
    // debug_assert_eq!(
    //     normalize_selector_slow(s),
    //     s,
    //     "canonical_plain accepted a selector the normalizer would rewrite"
    // );
    // debug_assert_eq!(percent, s.contains('%'), "canonical scan missed a `%`");
    // debug_assert!(
    //     !has_bogus_trigger(s),
    //     "the canonical byte set overlaps a bogus-combinator trigger"
    // );
}

/// Whether `s` is already in canonical form without running the normalizer:
/// only plain compound characters (ASCII letters/digits, `_-.#%:`) separated
/// by single descendant spaces, with no leading/trailing space. `None` means
/// not canonical; `Some(percent)` means canonical, and reports whether the scan
/// passed a `%` — the same loop over the same bytes answers both questions,
/// which is what makes [`ResolvedSelectors::any_percent`] free. Every rewrite
/// `normalize_selector` performs — whitespace collapse, hex-escape handling,
/// attribute/pseudo/combinator canonicalization — is triggered by a character
/// outside this set.
///
/// `:` is in the set, which is what admits the overwhelmingly common
/// `.btn:hover` / `a::before` shape, and it is sound for a reason worth writing
/// down because the set cannot be widened by eye. On input drawn from this set
/// the slow path is the *identity*, in three steps:
///
/// 1. The whitespace-collapse pass rewrites nothing: there is no `\`, no
///    whitespace other than single interior spaces, and no leading or trailing
///    space to trim.
/// 2. A `:` is consumed by `copy_pseudo`, which copies the colon(s) and then
///    the name via `copy_name` — verbatim, since `has_escape` is false — and
///    skips its argument branch entirely because there is no `(`. Both canon
///    probes then decline on their first line: `normalize_nth` and
///    `normalize_pseudo_arg` each open with `text.find('(')?`.
/// 3. The adjacent-compound rewrite (the one that inserts a descendant space
///    mid-compound) cannot fire. It needs `type_selector_starts_at` to be true
///    while `mid_compound` is set, and every boundary character in this set
///    consumes its own name through `copy_name`, whose `is_name_char` excludes
///    `. # % :` — so after any simple selector the next character is one of
///    `. # % :` or a space, and none of those starts a type selector.
///
/// Do **not** add `> + ~` here on the strength of the same argument: the slow
/// path rewrites `>a` to `> a`, so those need a separate proof about spacing
/// and the trailing-combinator case. The set is also deliberately disjoint from
/// `has_bogus_trigger`'s `> + ~ (`, so passing this predicate proves a selector
/// carries no bogus-combinator trigger — an invariant
/// [`ResolvedSelectors::maybe_bogus`] now depends on and
/// [`debug_assert_canonical`] pins.
function canonical_plain(s: string) -> bool? {
    let b = s.to_utf8();
    // b' ' = 32
    if (b.length() == 0 || b[0] == 32 || b[b.length() - 1] == 32) {
        return null;
    }
    let prev_space = false;
    let percent = false;
    // PORT: `for &c in b` → an index loop (a `uint8array` is not iterable).
    let bi = 0;
    while (bi < b.length()) {
        let c = b[bi];
        bi += 1;
        match (c) {
            // b'%'
            37 => {
                percent = true;
                prev_space = false;
            },
            // b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_' | b'-' | b'.' | b'#' | b':'
            let x
                if x >= 97
                && x <= 122
                || x >= 65
                && x <= 90
                || x >= 48
                && x <= 57
                || x == 95
                || x == 45
                || x == 46
                || x == 35
                || x == 58 => {
                prev_space = false;
            },
            // b' '
            32 => {
                if (prev_space) {
                    return null;
                }
                prev_space = true;
            },
            _ => {
                return null;
            },
        }
    }
    percent
}

/// [`normalize_selector`] for a string the caller already owns: hands the
/// buffer back untouched when it is already canonical, instead of copying its
/// bytes into a fresh `String`. Every selector this module builds by
/// substituting a parent (`format!("{parent} {part}")`, `replace_parent_refs`)
/// is owned and canonical, which is the common shape of a nested rule.
function normalize_selector_owned_facts(s: string) -> Normalized {
    match (canonical_plain(s)) {
        let percent: bool => {
            debug_assert_canonical(s, percent);
            Normalized { sel: s, canonical: true, percent: percent }
        },
        null => {
            let sel = normalize_selector_slow(s);
            let percent = sel.includes("%");
            Normalized { sel: sel, canonical: false, percent: percent }
        },
    }
}

function normalize_selector_slow(s: string) -> string {
    // Collapse runs of whitespace to single spaces (and trim) — but a hex
    // escape's single terminating whitespace is PART of the token
    // (`selector\9 ` keeps its trailing space; dart emits `selector\9  {`).
    // Inside pseudo parens, a run that follows a comma and contains a
    // newline collapses to '\n' instead: dart's arg complexes carry their
    // source lineBreak and the serializer honors it anywhere
    // (`:is(a,\n[type=color])` keeps its lines — quasar's field selectors).
    let cs_buf = CharBuf_of(s);
    let cs = cs_buf.deref();
    let collapsed = root.std.StrBuf.with_capacity(s.length());
    let prev_space = true; // trims leading whitespace
    let paren = 0;
    let ci = 0;
    while (ci < cs.length()) {
        let c = cs[ci];
        if (c == "\\" && ci + 1 < cs.length() && cs[ci + 1].is_ascii_hex()) {
            collapsed.push("\\");
            ci += 1;
            let digits = 0;
            while (digits < 6 && ci < cs.length() && cs[ci].is_ascii_hex()) {
                collapsed.push(cs[ci]);
                ci += 1;
                digits += 1;
            }
            if (ci < cs.length() && cs[ci].is_whitespace()) {
                collapsed.push(" ");
                ci += 1;
            }
            prev_space = false;
            continue;
        }
        // A literal escape: the next character — even whitespace (`sp\ `) —
        // is part of the token, never a separator to collapse or trim.
        if (c == "\\" && ci + 1 < cs.length()) {
            collapsed.push("\\");
            collapsed.push(cs[ci + 1]);
            ci += 2;
            prev_space = false;
            continue;
        }
        if (c.is_whitespace()) {
            let has_nl = c == "\n";
            ci += 1;
            while (ci < cs.length() && cs[ci].is_whitespace()) {
                has_nl = has_nl || cs[ci] == "\n";
                ci += 1;
            }
            if (!prev_space) {
                if (paren > 0 && has_nl && collapsed.ends_with(",")) {
                    collapsed.push("\n");
                } else {
                    collapsed.push(" ");
                }
            }
            prev_space = true;
            continue;
        }
        match (c) {
            "(" => {
                paren += 1;
            },
            ")" => {
                paren -= 1;
            },
            _ => {},
        }
        collapsed.push(c);
        prev_space = false;
        ci += 1;
    }
    // Trim a PLAIN trailing space (one belonging to an escape stays).
    if (prev_space && collapsed.ends_with(" ")) {
        let _ = collapsed.pop();
    }
    let chars_buf = CharBuf_of(collapsed.as_str());
    let chars = chars_buf.deref();
    let out = root.std.StrBuf.new();
    // PORT: `&mut i` for the `copy_*` helpers → a `Cell` round-trip (`ic`).
    let i = 0;
    // True when the current top-level compound already holds a simple selector.
    let mid_compound = false;
    while (i < chars.length()) {
        let c = chars[i];
        if (c == "[") {
            let end = matching_bracket(chars, i);
            if (end < chars.length()) {
                let whole = root.std.join(chars.slice(i, end + 1), "");
                out.push_str(root.selector.parse.normalize_attribute(whole));
            } else {
                let inner = root.std.join(chars.slice(i + 1, chars.length()), "");
                out.push("[");
                out.push_str(normalize_attribute_text(inner));
            }
            i = end + 1;
            mid_compound = true;
            continue;
        } else if (c == "." || c == "#" || c == "%") {
            // A class/id/placeholder sigil plus its name (one simple).
            out.push(c);
            i += 1;
            let ic = root.std.Cell.new(i);
            copy_name(chars, ic, out);
            i = ic.value;
            mid_compound = true;
            continue;
        } else if (c == ":") {
            // A pseudo-class/element (with any `(...)` argument). A
            // selector-argument pseudo re-serializes canonically.
            let start = out.len();
            let ic = root.std.Cell.new(i);
            copy_pseudo(chars, ic, out);
            i = ic.value;
            let text = out.slice_from(start);
            // An `:nth-child`/`:nth-last-child` An+B argument
            // canonicalizes (whitespace drops, lowercase `n`); a
            // selector-argument pseudo re-serializes canonically.
            let canon = root.selector.normalize_nth(text) ?? root.selector.normalize_pseudo_arg(text);
            if (canon != null) {
                out.truncate(start);
                out.push_str(canon);
            }
            mid_compound = true;
            continue;
        } else if (c == "*" && (chars.at(i + 1) != "|" || chars.at(i + 2) == "=")) {
            // A bare universal `*` (not a `*|...` namespace prefix). It does
            // not start a new adjacent compound on its own.
            out.push("*");
            i += 1;
            mid_compound = true;
            continue;
        } else if (c == ">" || c == "~" || c == "+") {
            while (out.ends_with(" ")) {
                let _ = out.pop();
            }
            out.push(" ");
            out.push(c);
            out.push(" ");
            i += 1;
            while (i < chars.length() && chars[i] == " ") {
                i += 1;
            }
            mid_compound = false;
            continue;
        } else if (c == " " || c == "\t" || c == "\n" || c == "\r") {
            out.push(c);
            i += 1;
            mid_compound = false;
            continue;
        } else if (type_selector_starts_at(chars, i)) {
            // A type/namespaced-type selector. Mid-compound, it is a
            // separate adjacent compound: join with a descendant space.
            if (mid_compound && !out.ends_with(" ")) {
                out.push(" ");
            }
            let ic = root.std.Cell.new(i);
            copy_type_selector(chars, ic, out);
            i = ic.value;
            mid_compound = true;
            continue;
        } else {
            // Any other character (e.g. a digit or `%` in a keyframe stop
            // like `1e2%`, which is not a real selector). It does NOT make a
            // following identifier an adjacent compound, so clear the flag.
            out.push(c);
            i += 1;
            mid_compound = false;
        }
    }
    let out = out.as_str();
    let t = root.std.trim(out);
    // dart keeps an escape's trailing space: a hex escape's terminator
    // (`selector\9 `) and an escaped literal space (`sp\ `) both survive;
    // only plain trailing whitespace trims.
    let start = out.length() - root.std.trim_start(out).length();
    let end = start + t.length();
    if (
        out.slice(end, out.length()).starts_with(" ")
            && (ends_with_hex_escape(t) || ends_with_escaping_backslash(t))
    ) {
        out.slice(start, end + 1)
    } else {
        t
    }
}

/// Whether `t` ends in a `\<hex>{1,6}` escape whose terminating space must
/// survive trimming.
function ends_with_hex_escape(t: string) -> bool {
    let b = t.to_utf8();
    let i = b.length();
    let digits = 0;
    while (i > 0 && root.std.chr_unchecked(b[i - 1]).is_ascii_hex() && digits < 6) {
        i -= 1;
        digits += 1;
    }
    digits > 0 && i > 0 && b[i - 1] == root.std.ord("\\")
}

/// Whether `t` ends in an ODD run of backslashes, so the character after it
/// (an escaped literal space, `sp\ `) is part of the identifier.
function ends_with_escaping_backslash(t: string) -> bool {
    let b = t.to_utf8();
    let n = 0;
    while (n < b.length() && b[b.length() - 1 - n] == root.std.ord("\\")) {
        n += 1;
    }
    n % 2 == 1
}

/// Trim a selector part's surrounding whitespace, keeping the one character
/// that belongs to a trailing escape — a hex escape's terminator (`\9 `) or
/// an escaped literal space (`sp\ `).
function trim_selector_part(p: string) -> string {
    let t0 = root.std.trim_start(p);
    let t = root.std.trim_end(t0);
    if (t.length() < t0.length() && (ends_with_hex_escape(t) || ends_with_escaping_backslash(t))) {
        t0.slice(0, t.length() + 1)
    } else {
        t
    }
}

/// One token of a complex selector split at the top level (paren/bracket depth
/// 0): either a combinator or a compound selector (a borrowed slice of the
/// input, trimmed).
interface SelToken {}

class SelToken_Combinator {
    implements SelToken {}
}

class SelToken_Compound {
    _0: string,
    implements SelToken {}
}

/// Tokenize a complex selector into combinators and compounds at the top level,
/// honouring `[...]`, `(...)`, strings, and escapes so combinators inside a
/// pseudo argument or attribute aren't split out here. Compounds borrow `s`
/// (no per-token allocation): each is a contiguous, trimmed substring.
function tokenize_complex(s: string) -> SelToken[] {
    let tokens: SelToken[] = [];
    let paren = 0;
    let bracket = 0;
    let start = 0; // char start of the compound being accumulated
    // PORT: the `char_indices()` iterator → an index cursor `k` over the
    // characters (offsets are char offsets); `it.next()` → `k += 1`.
    let cs = s.chars();
    let k = 0;
    while (k < cs.length()) {
        let idx = k;
        let c = cs[k];
        k += 1;
        if (c == "\\") {
            // An escape consumes the following character verbatim.
            k += 1;
        } else if (c == "\"" || c == "'") {
            // Skip a quoted string (honouring `\` escapes) so combinators
            // inside it aren't split out. Mirrors `skip_string`.
            while (k < cs.length()) {
                let c2 = cs[k];
                k += 1;
                if (c2 == "\\") {
                    k += 1;
                } else if (c2 == c) {
                    break;
                }
            }
        } else if (c == "(") {
            paren += 1;
        } else if (c == ")") {
            paren -= 1;
        } else if (c == "[") {
            bracket += 1;
        } else if (c == "]") {
            bracket -= 1;
        } else if ((c == ">" || c == "+" || c == "~") && paren == 0 && bracket == 0) {
            let t = trim_selector_part(s.slice(start, idx));
            if (t != "") {
                tokens.push(SelToken_Compound { _0: t });
            }
            tokens.push(SelToken_Combinator {  });
            start = idx + 1; // combinator char is one character
        }
    }
    let t = trim_selector_part(s.slice(start, s.length()));
    if (t != "") {
        tokens.push(SelToken_Compound { _0: t });
    }
    tokens
}

/// Whether a resolved complex selector is a "bogus combinator" that dart-sass
/// omits from the generated CSS: two combinators in a row anywhere, or — inside
/// a pseudo argument (`in_pseudo`) — a trailing combinator, or a leading
/// combinator unless `allow_leading` (true only for `:has`, a relative selector
/// list). A single leading/trailing combinator at the top level is NOT bogus
/// here (it is kept, or handled separately by the nesting rules). The check
/// recurses into selector pseudo arguments (`:is()`, `:not()`, …).
function complex_selector_is_bogus(s: string, in_pseudo: bool, allow_leading: bool) -> bool {
    // Bogus-ness needs a combinator (`>`/`+`/`~`) or a selector-pseudo
    // argument (which needs a `(`); a selector containing none of those
    // bytes cannot be bogus, so skip the tokenization entirely.
    if (!has_bogus_trigger(s)) {
        return false;
    }
    let tokens = tokenize_complex(s);
    if (tokens.length() == 0) {
        return false;
    }
    // Two adjacent combinators (no compound between) is always invalid.
    let prev_combinator = false;
    for (let t in tokens) {
        match (t) {
            SelToken_Combinator {} => {
                if (prev_combinator) {
                    return true;
                }
                prev_combinator = true;
            },
            _ => {
                prev_combinator = false;
            },
        }
    }
    if (in_pseudo) {
        if (!allow_leading && tokens.at(0) is SelToken_Combinator) {
            return true;
        }
        if (root.std.last(tokens) is SelToken_Combinator) {
            return true;
        }
    }
    // Recurse into selector pseudo arguments of each compound.
    for (let t in tokens) {
        if let comp: SelToken_Compound = t {
            if (compound_has_bogus_pseudo(comp._0)) {
                return true;
            }
        }
    }
    false
}

/// Whether a resolved complex selector should be dropped from its own emitted
/// declaration block. This is [`complex_selector_is_bogus`] (double combinators,
/// pseudo leading/trailing combinators) PLUS a top-level trailing combinator
/// (`a >`): a trailing combinator is valid only for nesting, so the leaf block
/// it would head is omitted while the selector still serves as a parent.
/// Source span of one comma-separated entry of a rule's selector list, for a
/// diagnostic that names that entry.
///
/// `sel_str` is the rule's own selector with its interpolations already
/// substituted, so an offset into it is not a position in the source. The
/// authored one is recovered by shifting across the interpolations that
/// precede the entry on its line — the same correction `interp_selector_error`
/// applies to a single column, extended to a list that may span lines
/// (`a,\nb`).
///
/// THREE UNITS MEET HERE and mixing them silently misplaces the caret:
/// [`InterpBounds`] and [`Pos::col`] count CHARACTERS, [`crate::diag::Span`]
/// takes its length in SOURCE BYTES, and `&str` indexing is in bytes. The
/// first version of this used byte offsets throughout and drew the underline
/// twelve columns late on `.日本語テスト, .a > + .b` — one column per
/// multi-byte character before the entry.
///
/// Returns the whole selector's start when the correction cannot be trusted
/// (the interpolation spans do not line up with the bounds), which keeps the
/// diagnostic on the right rule even when the column is approximate.
function selector_part_span(
    src: string,
    rule: root.ast.Rule,
    sel_str: string,
    interp_bounds: root.eval.expr.InterpBounds,
    part_index: int,
) -> root.std.Tuple2<root.scanner.Pos, int> {
    // PORT: lengths handed to a diag span are SOURCE BYTES → `byte_length()`.
    let fallback = root.std.Tuple2<root.scanner.Pos, int> { _0: rule.selector_pos, _1: sel_str.byte_length() };
    // PORT: `kept.as_ptr() - base` pointer arithmetic → the entry's offset is
    // carried explicitly: `split_commas`' parts are contiguous in `sel_str`,
    // separated by one-character commas. Offsets here are CHAR offsets.
    let chosen: root.std.Tuple2<int, int>? = null;
    let k = 0;
    let part_start = 0;
    for (let part in split_commas(sel_str).deref()) {
        if (k == part_index) {
            // `trim_selector_part`, not `trim`: a trailing space can be the
            // terminator of a hex escape (`.a\9 `) and belongs to the selector.
            let kept = trim_selector_part(part);
            let byte_start = part_start + (part.length() - root.std.trim_start(part).length());
            chosen = root.std.Tuple2<int, int> { _0: byte_start, _1: kept.length() };
            break;
        }
        part_start += part.length() + 1;
        k += 1;
    }
    if (chosen == null) {
        return fallback;
    }
    let byte_start = chosen._0;
    let part_chars = chosen._1;

    let spans = rule.selector_interp_spans;
    let interp = interp_bounds.as_slice();
    if (spans.length() != interp.length()) {
        return fallback;
    }

    // Char offset of the entry, and of the start of the line it sits on.
    let before = sel_str.slice(0, byte_start);
    let start = before.length();
    let newlines = before.split("\n").length() - 1;
    let line_start = match (before.last_index_of("\n")) {
        let i: int => sel_str.slice(0, i + 1).length(),
        _ => 0,
    };

    // `#{ … }` and what it produced are different widths, so every
    // interpolation shifts what follows it. One BEFORE the entry (on the same
    // line) moves its start column; one INSIDE it changes how wide the authored
    // text is — the entry dart underlines is `.#{$name} > + lines`, not the
    // `.inaccuracy > + lines` it resolved to.
    let shift = 0;
    let inner = 0;
    let ki = 0;
    for (let b in interp) {
        let out_start = b._0;
        let out_len = b._1;
        let col_start = spans[ki]._1;
        let col_end = spans[ki]._2;
        // `#{ … }` runs from two columns before the expression to the `}`.
        let src_total = col_end + 1 - (col_start - 2);
        let delta = src_total - out_len;
        if (out_start >= line_start && out_start + out_len <= start) {
            shift += delta;
        } else if (out_start >= start && out_start + out_len <= start + part_chars) {
            inner += delta;
        }
        ki += 1;
    }

    let col = if (newlines == 0) {
        rule.selector_pos.col + start + shift
    } else {
        // A later line of the list starts at column 1 of the source line.
        1 + (start - line_start) + shift
    };
    let col = root.std.imax(col, 1);
    let line = rule.selector_pos.line + newlines;
    // The caret length is SOURCE BYTES; everything above is characters.
    let authored_chars = root.std.imax(part_chars + inner, 1);
    let len = source_byte_len(src, line, col, authored_chars) ?? sel_str.byte_length();
    root.std.Tuple2<root.scanner.Pos, int> {
        _0: root.scanner.Pos { line: line, col: col },
        _1: len,
    }
}

/// Byte length of `chars` characters of `src` starting at 1-based `line`/`col`,
/// for a [`crate::diag::Span`] length. `None` when the position is past the end
/// of the source, which means the mapping above produced something the source
/// cannot back.
function source_byte_len(src: string, line: int, col: int, chars: int) -> int? {
    let cur_line = 1;
    let cur_col = 1;
    let start: int? = null;
    let taken = 0;
    // PORT: `char_indices()` → the characters with a running BYTE offset `i`
    // (the result is a byte length).
    let i = 0;
    for (let ch in src.chars()) {
        if (start == null && cur_line == line && cur_col == col) {
            start = i;
        }
        let from = start;
        if (from != null) {
            if (taken == chars) {
                return i - from;
            }
            taken += 1;
        }
        if (ch == "\n") {
            cur_line += 1;
            cur_col = 1;
        } else {
            cur_col += 1;
        }
        i += root.std.len_utf8(ch);
    }
    let b = start;
    if (b != null) {
        src.byte_length() - b
    } else {
        null
    }
}

function complex_selector_block_is_bogus(s: string) -> bool {
    if (!has_bogus_trigger(s)) {
        return false;
    }
    if (complex_selector_is_bogus(s, false, false)) {
        return true;
    }
    let tokens = tokenize_complex(s);
    root.std.last(tokens) is SelToken_Combinator
}

/// Whether `s` contains any byte that could make a complex selector bogus: a
/// combinator, or the `(` of a selector-pseudo argument to recurse into.
/// Escaped spellings (`\>`) still contain the trigger byte, so anything
/// suspicious takes the full tokenizing path.
function has_bogus_trigger(s: string) -> bool {
    // PORT: the byte scan → substring tests (all four triggers are ASCII).
    s.includes(">") || s.includes("+") || s.includes("~") || s.includes("(")
}

/// Whether `name` (a pseudo-class/element name, case-insensitive, without the
/// leading colon(s)) is one whose argument dart-sass parses as a selector list,
/// and so is subject to bogus-combinator checking. Mirrors dart-sass's
/// `_selectorPseudoClasses`/`_selectorPseudoElements`. Notably this EXCLUDES
/// `:global`/`:local` (CSS-modules pseudos kept verbatim).
function is_selector_pseudo(name: string) -> bool {
    match (root.std.ascii_lower(name)) {
        "not"
            | "is"
            | "matches"
            | "where"
            | "current"
            | "any"
            | "has"
            | "host"
            | "host-context"
            | "slotted" =>
        {
            true
        },
        _ => false,
    }
}

/// Whether any selector-pseudo argument (`:is(...)`, `:has(...)`, `:not(...)`,
/// `:where(...)`, …) inside a compound contains a bogus-combinator complex
/// selector. Only pseudos in [`is_selector_pseudo`] are scanned (others, like
/// `:nth-child(2n)` or `:global(> a)`, keep their argument verbatim). `:has` is
/// a relative selector list, so a leading combinator there is allowed.
function compound_has_bogus_pseudo(compound: string) -> bool {
    let chars_buf = CharBuf_of(compound);
    let chars = chars_buf.deref();
    let i = 0;
    while (i < chars.length()) {
        let c = chars[i];
        if (c == "\\") {
            i += 2;
            continue;
        }
        if (c == "[") {
            // Skip an attribute selector verbatim.
            i = matching_bracket(chars, i) + 1;
            continue;
        }
        if (c == ":") {
            // A pseudo with a `(...)` argument: extract and scan the argument as
            // a selector list (each comma part is one complex selector).
            let j = i + 1;
            if (j < chars.length() && chars[j] == ":") {
                j += 1;
            }
            let name_start = j;
            while (j < chars.length() && (is_name_char(chars[j]) || chars[j] == "\\")) {
                if (chars[j] == "\\") {
                    j += 1;
                }
                j += 1;
            }
            let name = root.std.join(chars.slice(name_start, root.std.imin(j, chars.length())), "");
            if (j < chars.length() && chars[j] == "(") {
                let open = j;
                let depth = 0;
                let k = open;
                while (k < chars.length()) {
                    let ck = chars[k];
                    if (ck == "\\") {
                        k += 2;
                        continue;
                    } else if (ck == "\"" || ck == "'") {
                        k = skip_string(chars, k);
                        continue;
                    } else if (ck == "(") {
                        depth += 1;
                    } else if (ck == ")") {
                        depth -= 1;
                        if (depth == 0) {
                            break;
                        }
                    }
                    k += 1;
                }
                if (is_selector_pseudo(name)) {
                    let allow_leading = root.std.eq_ignore_ascii_case(name, "has");
                    let arg = root.std.join(chars.slice(open + 1, root.std.imin(k, chars.length())), "");
                    for (let part in split_commas(arg).deref()) {
                        let part = root.std.trim(part);
                        if (part != "" && complex_selector_is_bogus(part, true, allow_leading)) {
                            return true;
                        }
                    }
                }
                i = k + 1;
                continue;
            }
            i = j;
            continue;
        }
        i += 1;
    }
    false
}

/// Copy a CSS name (the part after a `.`/`#`/`%` sigil or a type name) starting
/// at `*i`, honouring `\` escapes, advancing `*i` past it. The captured name is
/// canonicalized to dart-sass's escape form (a numeric escape of a printable
/// character becomes the escaped character, an inline digit drops its escape,
/// etc.).
function copy_name(chars: string[], i: root.std.Cell<int>, out: root.std.StrBuf) -> void {
    let start = i.value;
    let has_escape = false;
    while (i.value < chars.length()) {
        let c = chars[i.value];
        if (c == "\\") {
            has_escape = true;
            i.value += 1;
            if (i.value < chars.length()) {
                let esc = chars[i.value];
                i.value += 1;
                // A hex escape continues for up to six hex digits plus one
                // optional trailing whitespace; consume the rest of it so it
                // decodes as a single code point.
                if (esc.is_ascii_hex()) {
                    let digits = 1;
                    while (digits < 6 && i.value < chars.length() && chars[i.value].is_ascii_hex()) {
                        i.value += 1;
                        digits += 1;
                    }
                    if (i.value < chars.length() && chars[i.value].is_whitespace()) {
                        i.value += 1;
                    }
                }
            }
        } else if (is_name_char(c)) {
            i.value += 1;
        } else {
            break;
        }
    }
    // Fast path: a plain name (no escapes) round-trips through
    // `canonicalize_ident` unchanged, so copy the slice straight out with no
    // intermediate String allocation.
    if (has_escape) {
        let raw = root.std.join(chars.slice(start, i.value), "");
        out.push_str(root.selector.parse.canonicalize_ident(raw));
    } else {
        out.push_str(root.std.join(chars.slice(start, i.value), ""));
    }
}

/// Copy a pseudo-class/element selector (`:name` / `::name` plus any balanced
/// `(...)` argument) verbatim, advancing `*i` past it.
function copy_pseudo(chars: string[], i: root.std.Cell<int>, out: root.std.StrBuf) -> void {
    out.push(chars[i.value]); // first ':'
    i.value += 1;
    let is_element = i.value < chars.length() && chars[i.value] == ":";
    if (is_element) {
        out.push(":");
        i.value += 1;
    }
    let name_start = i.value;
    copy_name(chars, i, out);
    let name = root.std.join(chars.slice(name_start, i.value), "");
    if (i.value < chars.length() && chars[i.value] == "(") {
        out.push("(");
        i.value += 1;
        // dart-sass trims the whitespace immediately inside a pseudo's argument
        // parens (interior runs are already collapsed to a single space by
        // `normalize_selector`). Leading whitespace is always dropped; trailing
        // whitespace is dropped for a pseudo-CLASS or a selector-argument
        // pseudo-element (`::slotted`), but KEPT for a text-argument
        // pseudo-element such as `::part(foo )` / `::highlight(h )`.
        let trim_trailing = !is_element || is_selector_pseudo_element(name);
        while (i.value < chars.length() && chars[i.value] == " ") {
            i.value += 1;
        }
        let depth = 1;
        while (i.value < chars.length()) {
            let c = chars[i.value];
            if (c == "\\") {
                out.push(c);
                i.value += 1;
                if (i.value < chars.length()) {
                    out.push(chars[i.value]);
                    i.value += 1;
                }
                continue;
            } else if (c == "(") {
                depth += 1;
            } else if (c == ")") {
                depth -= 1;
                if (depth == 0) {
                    if (trim_trailing) {
                        while (out.ends_with(" ")) {
                            let _ = out.pop();
                        }
                    }
                    out.push(")");
                    i.value += 1;
                    break;
                }
            }
            out.push(c);
            i.value += 1;
        }
    }
}

/// Whether a `::name` pseudo-element takes a selector argument (so dart-sass
/// parses and re-serializes it, trimming the argument on both sides). Other
/// pseudo-elements (`::part`, `::highlight`) carry a raw text argument and keep
/// its trailing whitespace. Compared case-insensitively, ignoring a vendor
/// prefix, matching dart-sass's `_selectorPseudoElements`.
function is_selector_pseudo_element(name: string) -> bool {
    let lower = root.std.ascii_lower(name);
    let rest = root.std.strip_prefix(lower, "-");
    let unvendored = if (rest == null) {
        lower
    } else {
        match (rest.index_of("-")) {
            let idx: int => rest.slice(idx + 1, rest.length()),
            _ => lower,
        }
    };
    match (unvendored) {
        "slotted" | "cue" | "cue-region" => true,
        _ => false,
    }
}

/// Copy a type/element selector, including an optional `ns|`/`*|`/`|` namespace
/// prefix and the type name (or `*`), advancing `*i` past it.
function copy_type_selector(chars: string[], i: root.std.Cell<int>, out: root.std.StrBuf) -> void {
    // Optional namespace prefix.
    if (chars[i.value] == "*") {
        out.push("*");
        i.value += 1;
    } else if (chars[i.value] == "|") {
        // bare `|type` — no namespace, handled by falling through.
    } else {
        copy_name(chars, i, out);
    }
    if (i.value < chars.length() && chars[i.value] == "|" && chars.at(i.value + 1) != "=") {
        out.push("|");
        i.value += 1;
        if (i.value < chars.length() && chars[i.value] == "*") {
            out.push("*");
            i.value += 1;
        } else {
            copy_name(chars, i, out);
        }
    }
}

/// Whether a bare type/namespaced-type selector (an identifier, optionally
/// preceded by a `*|`/`ns|`/`|` namespace) begins at `chars[i]`. Used to detect
/// an adjacent compound (`[a]b` → `[a] b`). A `*` universal, the `.#%:` sigils,
/// an attribute `[`, and a combinator are NOT type-selector starts. `*|type`
/// and `|type` count as type starts.
function type_selector_starts_at(chars: string[], i: int) -> bool {
    let c = chars[i];
    // `*|...` is a namespaced type/universal (but not `*|=`, an operator).
    if (c == "*") {
        return chars.at(i + 1) == "|" && chars.at(i + 2) != "=";
    }
    // `|type` (empty namespace) is a type selector (but not `|=`).
    if (c == "|") {
        return chars.at(i + 1) != "=";
    }
    if (is_name_start(c)) {
        return true;
    }
    // A leading `-` of an identifier (`-foo`, `--foo`) or an escape `\` begins
    // an identifier-led type selector.
    if (c == "-") {
        return match (chars.at(i + 1)) {
            let n: string if is_name_start(n) || n == "-" || n == "\\" => true,
            _ => false,
        };
    }
    c == "\\"
}

// ---- media queries -----------------------------------------------------
/// Append an `and`/`or` media-query separator. dart-sass's compressed media
/// serializer omits the space BEFORE the keyword when the text so far ends in
/// `)` (`(a)and (b)`) but keeps it after an identifier (`screen and (a)`); the
/// trailing space is always present. Expanded always emits ` and `/` or `.
/// (`@supports` conditions are serialized elsewhere and are NOT tightened.)
function push_media_sep(s: root.std.StrBuf, is_and: bool, compressed: bool) -> void {
    let word = if (is_and) {
        "and"
    } else {
        "or"
    };
    if (compressed && s.ends_with(")")) {
        s.push_str(word);
    } else {
        s.push(" ");
        s.push_str(word);
    }
    s.push(" ");
}

/// Serialize a comma list of media queries.
/// Whether a parsed media query contains `#{}` interpolation anywhere.
function media_query_has_interp(q: root.ast.MediaQuery) -> bool {
    // PORT: the nested `tpl`/`expr`/`in_parens` fns are hoisted to
    // `media_query_has_interp__tpl` / `__expr` / `__in_parens` below.
    match (q) {
        let t: root.ast.MediaQuery_Type => {
            media_query_has_interp__tpl(t.mtype)
                || t.conditions.some((c) -> {
                    media_query_has_interp__in_parens(c)
                })
        },
        let c: root.ast.MediaQuery_Condition => {
            c.conditions.some((x) -> {
                media_query_has_interp__in_parens(x)
            })
        },
        _ => false,
    }
}

/// `media_query_has_interp`'s nested `fn tpl`.
function media_query_has_interp__tpl(t: root.ast.TplPiece[]) -> bool {
    t.some((p) -> {
        p is root.ast.TplPiece_Interp
    })
}

/// `media_query_has_interp`'s nested `fn expr`.
function media_query_has_interp__expr(e: root.ast.Expr) -> bool {
    match (e) {
        let _i: root.ast.Expr_Interp => true,
        let t: root.ast.Expr_Ident => media_query_has_interp__tpl(t._0),
        let t: root.ast.Expr_QuotedString => media_query_has_interp__tpl(t._0),
        let p: root.ast.Expr_Paren => media_query_has_interp__expr(p._0),
        let u: root.ast.Expr_Unary => media_query_has_interp__expr(u.operand),
        let b: root.ast.Expr_Binary => {
            media_query_has_interp__expr(b.lhs) || media_query_has_interp__expr(b.rhs)
        },
        let d: root.ast.Expr_Div => {
            media_query_has_interp__expr(d.lhs) || media_query_has_interp__expr(d.rhs)
        },
        let l: root.ast.Expr_List => {
            l.items.some((x) -> {
                media_query_has_interp__expr(x)
            })
        },
        _ => false,
    }
}

/// `media_query_has_interp`'s nested `fn in_parens`.
function media_query_has_interp__in_parens(c: root.ast.MediaInParens) -> bool {
    match (c) {
        let f: root.ast.MediaInParens_Feature => match (f._0) {
            let d: root.ast.MediaFeature_Decl => {
                let value = d.value;
                media_query_has_interp__expr(d.name)
                    || (
                        if (value != null) {
                            media_query_has_interp__expr(value)
                        } else {
                            false
                        }
                    )
            },
            let r: root.ast.MediaFeature_Range => {
                let rest = r.rest;
                media_query_has_interp__expr(r.first)
                    || media_query_has_interp__expr(r.second)
                    || (
                        if (rest != null) {
                            media_query_has_interp__expr(rest._1)
                        } else {
                            false
                        }
                    )
            },
            _ => false,
        },
        let n: root.ast.MediaInParens_Not => media_query_has_interp__in_parens(n._0),
        let g: root.ast.MediaInParens_Group => {
            g.conditions.some((x) -> {
                media_query_has_interp__in_parens(x)
            })
        },
        let _i: root.ast.MediaInParens_Interp => true,
        _ => false,
    }
}

/// Parse a RESOLVED (interpolation-free) media query list the way dart-sass's
/// `CssMediaQuery.parseList` does: identifiers and `and`/`or` keywords are
/// structural, while each parenthesised condition is kept as raw balanced
/// text (`((a) AnD (b))` survives verbatim).
function css_media_parse_list(text: string) -> ResolvedQuery[] {
    let out: ResolvedQuery[] = [];
    for (let part in split_top_level_media_commas(text)) {
        let part = root.std.trim(part);
        if (part == "") {
            continue;
        }
        let q = css_media_parse_one(part);
        // dart re-parses `(not (a))` as a negation and serializes it WITHOUT
        // the outer parentheses (`@media not (a)`).
        if (q.mtype == null && q.modifier == null && q.conditions.length() == 1) {
            let c = q.conditions[0];
            let opened = root.std.strip_prefix(c, "(");
            let inner = if (opened != null) {
                root.std.strip_suffix(opened, ")")
            } else {
                null
            };
            if (inner != null) {
                let t = root.std.trim(inner);
                let balanced = {
                    let d = 0;
                    let ok = true;
                    for (let ch in t.chars()) {
                        if (ch == "(") {
                            d += 1;
                        } else if (ch == ")") {
                            d -= 1;
                            if (d < 0) {
                                ok = false;
                                break;
                            }
                        }
                    }
                    ok && d == 0
                };
                // Only the exact lowercase `not` keyword re-parses as a
                // negation (dart keeps `(NoT (a))` verbatim).
                if (balanced && (t.starts_with("not ") || t.starts_with("not("))) {
                    q.conditions[0] = t;
                }
            }
        }
        out.push(q);
    }
    out
}

function split_top_level_media_commas(s: string) -> string[] {
    let parts: string[] = [];
    let cur = root.std.StrBuf.new();
    let depth = 0;
    for (let c in s.chars()) {
        if (c == "(" || c == "[") {
            depth += 1;
            cur.push(c);
        } else if (c == ")" || c == "]") {
            depth -= 1;
            cur.push(c);
        } else if (c == "," && depth == 0) {
            parts.push(cur.take());
        } else {
            cur.push(c);
        }
    }
    parts.push(cur.take());
    parts
}

function css_media_parse_one(t: string) -> ResolvedQuery {
    let chars_buf = CharBuf_of(t);
    let chars = chars_buf.deref();
    // PORT: `let mut i` passed to the closures as `&mut usize` → a `Cell`.
    let i = root.std.Cell.new(0);
    let skip_ws = (i: root.std.Cell<int>) -> void {
        while (i.value < chars.length() && chars[i.value].is_whitespace()) {
            i.value += 1;
        }
    };
    // A raw balanced `(...)` condition, kept verbatim.
    let take_paren = (i: root.std.Cell<int>) -> string {
        let start = i.value;
        let depth = 0;
        while (i.value < chars.length()) {
            let ch = chars[i.value];
            if (ch == "(") {
                depth += 1;
            } else if (ch == ")") {
                depth -= 1;
                if (depth == 0) {
                    i.value += 1;
                    return root.std.join(chars.slice(start, i.value), "");
                }
            }
            i.value += 1;
        }
        throw root.error.Error.unpositioned("expected \")\".");
    };
    let take_ident = (i: root.std.Cell<int>) -> string {
        let start = i.value;
        while (i.value < chars.length() && !chars[i.value].is_whitespace() && chars[i.value] != "(") {
            i.value += 1;
        }
        root.std.join(chars.slice(start, i.value), "")
    };
    skip_ws(i);
    // Condition-only form: `(c) [and|or (c)]*` (possibly `not (c)`).
    if (i.value < chars.length() && chars[i.value] == "(") {
        let conditions: string[] = [take_paren(i)];
        let conjunction_and = true;
        while (true) {
            skip_ws(i);
            if (i.value >= chars.length()) {
                break;
            }
            let word = take_ident(i);
            skip_ws(i);
            match (root.std.ascii_lower(word)) {
                "and" => {
                    conditions.push(take_paren(i));
                },
                "or" => {
                    conjunction_and = false;
                    conditions.push(take_paren(i));
                },
                _ => {
                    throw root.error.Error.unpositioned("expected \"and\" or \"or\".");
                },
            }
        }
        return ResolvedQuery {
            modifier: null,
            mtype: null,
            conditions: conditions,
            conjunction_and: conjunction_and,
        };
    }
    let id1 = take_ident(i);
    skip_ws(i);
    if (root.std.eq_ignore_ascii_case(id1, "not") && i.value < chars.length() && chars[i.value] == "(") {
        let cond = take_paren(i);
        return ResolvedQuery {
            modifier: null,
            mtype: null,
            conditions: [`not ${cond}`],
            conjunction_and: true,
        };
    }
    // `[modifier] type [and (c)]*` — a second identifier that isn't `and`
    // makes the first the modifier.
    let modifier: string? = null;
    let mtype = id1;
    if (i.value < chars.length() && chars[i.value] != "(") {
        let save = i.value;
        let id2 = take_ident(i);
        if (id2 != "" && !root.std.eq_ignore_ascii_case(id2, "and")) {
            // `std::mem::replace(&mut mtype, id2)`
            modifier = mtype;
            mtype = id2;
        } else {
            i.value = save;
        }
    }
    let conditions: string[] = [];
    while (true) {
        skip_ws(i);
        if (i.value >= chars.length()) {
            break;
        }
        let word = take_ident(i);
        if (!root.std.eq_ignore_ascii_case(word, "and")) {
            throw root.error.Error.unpositioned("expected \"and\".");
        }
        skip_ws(i);
        conditions.push(take_paren(i));
    }
    ResolvedQuery {
        modifier: modifier,
        mtype: mtype,
        conditions: conditions,
        conjunction_and: true,
    }
}

function serialize_media_queries(queries: ResolvedQuery[], compressed: bool) -> string {
    // Compressed drops the space after the comma between queries (`(a),(b)`).
    let sep = if (compressed) {
        ","
    } else {
        ", "
    };
    queries
        .map((q) -> {
            q.render(compressed)
        })
        .join(sep)
}

/// Serialize a media query list as dart's PARSER spells it into an `@import`'s
/// modifier interpolation (`_mediaQueryList`), which `visitCssImport` writes
/// verbatim. That spelling is not the media-rule serializer's: `_mediaQuery`
/// writes the space that would separate a media type from a following
/// identifier BEFORE it learns the identifier is `and`, then writes the whole
/// `" and "` separator anyway — so a bare `<type> and <condition>` query goes
/// out with TWO spaces. Only an `@import` can show it, since a real `@media`
/// rule re-serializes from the parsed queries.
function serialize_import_media_queries(queries: ResolvedQuery[]) -> string {
    queries
        .map((q) -> {
            let s = q.render(false);
            // A modifier absorbs the stray space (`only screen and`, and even
            // `not screen and`, are spelled with one), and a query that opens
            // on a condition has no type to be separated from.
            let t = q.mtype;
            if (q.modifier == null && q.conditions.length() > 0) {
                if (t != null) {
                    // PORT: `s.insert(t.len(), ' ')` (char offset: `s` starts with `t`).
                    s = s.slice(0, t.length()) + " " + s.slice(t.length(), s.length());
                }
            }
            s
        })
        .join(", ")
}

/// Merge an enclosing query list with a nested query list (dart-sass
/// `_mergeMediaQueries`). Returns `None` if any pair is unrepresentable (keep
/// the nested rule in place); otherwise the merged list, which is empty when
/// every pair is mutually exclusive (the rule is dropped).
function merge_media_query_lists(
    outer: ResolvedQuery[],
    inner: ResolvedQuery[],
) -> ResolvedQuery[]? {
    let merged: ResolvedQuery[] = [];
    for (let a in outer) {
        for (let b in inner) {
            match (merge_media_query(a, b)) {
                MergeResult_Empty {} => {
                    continue;
                },
                MergeResult_Unrepresentable {} => {
                    return null;
                },
                let q: MergeResult_Query => {
                    merged.push(q._0);
                },
                _ => {},
            }
        }
    }
    merged
}

/// Merge two media queries (dart-sass `CssMediaQuery.merge`).
function merge_media_query(this: ResolvedQuery, other: ResolvedQuery) -> MergeResult {
    if (!this.conjunction_and || !other.conjunction_and) {
        return MergeResult_Unrepresentable {  };
    }
    let our_modifier = match (this.modifier) {
        let s: string => root.std.ascii_lower(s),
        _ => null,
    };
    let our_type = match (this.mtype) {
        let s: string => root.std.ascii_lower(s),
        _ => null,
    };
    let their_modifier = match (other.modifier) {
        let s: string => root.std.ascii_lower(s),
        _ => null,
    };
    let their_type = match (other.mtype) {
        let s: string => root.std.ascii_lower(s),
        _ => null,
    };

    if (our_type == null && their_type == null) {
        let conditions = root.std.clone_vec(this.conditions);
        root.std.extend(conditions, other.conditions);
        return MergeResult_Query {
            _0: ResolvedQuery {
                modifier: null,
                mtype: null,
                conditions: conditions,
                conjunction_and: true,
            },
        };
    }

    let our_not = our_modifier == "not";
    let their_not = their_modifier == "not";
    let is_all = (t: string?) -> bool {
        t == "all"
    };

    // PORT: the deferred-init tuple `(modifier, mtype, conditions)` → three
    // locals with placeholder initial values, each assigned on every path.
    let modifier: string? = null;
    let mtype: string? = null;
    let conditions: string[] = [];
    if (our_not != their_not) {
        if (our_type == their_type) {
            let neg = if (our_not) {
                this.conditions
            } else {
                other.conditions
            };
            let pos = if (our_not) {
                other.conditions
            } else {
                this.conditions
            };
            if (
                neg.every((c) -> {
                    pos.includes(c)
                })
            ) {
                return MergeResult_Empty {  };
            }
            return MergeResult_Unrepresentable {  };
        } else if (our_type == null || is_all(our_type) || their_type == null || is_all(their_type)) {
            return MergeResult_Unrepresentable {  };
        }
        if (our_not) {
            modifier = their_modifier;
            mtype = their_type;
            conditions = root.std.clone_vec(other.conditions);
        } else {
            modifier = our_modifier;
            mtype = our_type;
            conditions = root.std.clone_vec(this.conditions);
        }
    } else if (our_not) {
        if (our_type != their_type) {
            return MergeResult_Unrepresentable {  };
        }
        let more = if (this.conditions.length() > other.conditions.length()) {
            this.conditions
        } else {
            other.conditions
        };
        let fewer = if (this.conditions.length() > other.conditions.length()) {
            other.conditions
        } else {
            this.conditions
        };
        if (
            !fewer.every((c) -> {
                more.includes(c)
            })
        ) {
            return MergeResult_Unrepresentable {  };
        }
        modifier = our_modifier;
        mtype = our_type;
        conditions = root.std.clone_vec(more);
    } else if (our_type == null || is_all(our_type)) {
        mtype
            = if ((their_type == null || is_all(their_type)) && our_type == null) {
                null
            } else {
                their_type
            };
        let c = root.std.clone_vec(this.conditions);
        root.std.extend(c, other.conditions);
        conditions = c;
        modifier = their_modifier;
    } else if (their_type == null || is_all(their_type)) {
        let c = root.std.clone_vec(this.conditions);
        root.std.extend(c, other.conditions);
        conditions = c;
        modifier = our_modifier;
        mtype = our_type;
    } else if (our_type != their_type) {
        return MergeResult_Empty {  };
    } else {
        modifier = our_modifier ?? their_modifier;
        let c = root.std.clone_vec(this.conditions);
        root.std.extend(c, other.conditions);
        conditions = c;
        mtype = our_type;
    }

    // dart-sass keeps the raw (original-case) type of whichever query
    // contributed it.
    let final_type = if (mtype == null) {
        null
    } else if (mtype == our_type) {
        this.mtype
    } else {
        other.mtype
    };
    MergeResult_Query {
        _0: ResolvedQuery {
            modifier: modifier,
            mtype: final_type,
            conditions: conditions,
            conjunction_and: true,
        },
    }
}

// ---- modern if() condition evaluation ----------------------------------
/// The tri-state outcome of evaluating a modern `if()` condition: a static
/// boolean, or a residual non-evaluable CSS condition kept for verbatim
/// serialization.
interface CondEval {}

class CondEval_Bool {
    _0: bool,
    implements CondEval {}
}

class CondEval_Css {
    _0: RCond,
    implements CondEval {}
}

/// A residual (non-evaluable) modern `if()` condition tree. The raw text of
/// each `Css` leaf already has interpolation resolved; the tree is preserved
/// so `and`/`or`/`not`/parentheses serialize canonically.
interface RCond {
    function to_css(self) -> string throws never {
        match (self) {
            let s: RCond_Css => s._0,
            let c: RCond_Not => `not ${c._0.to_css()}`,
            let items: RCond_And => {
                root.std.join(
                    items._0.map((x) -> {
                        x.to_css()
                    }),
                    " and ",
                )
            },
            let items: RCond_Or => {
                root.std.join(
                    items._0.map((x) -> {
                        x.to_css()
                    }),
                    " or ",
                )
            },
            let c: RCond_Paren => `(${c._0.to_css()})`,
            _ => root.std.unreachable(),
        }
    }
}

/// A serialized raw substitution sequence (`css(...)`, `var(...)`, ...).
class RCond_Css {
    _0: string,
    implements RCond {}
}

class RCond_Not {
    _0: RCond,
    implements RCond {}
}

class RCond_And {
    _0: RCond[],
    implements RCond {}
}

class RCond_Or {
    _0: RCond[],
    implements RCond {}
}

class RCond_Paren {
    _0: RCond,
    implements RCond {}
}

/// Combine the residual operands of an `and`/`or` whose statically-known
/// operands were already folded away. When a single residual remains, the
/// operation collapses to it (and a redundant outer paren is dropped, as in
/// dart-sass); otherwise it stays an `and`/`or` chain.
function combine_residuals(residuals: RCond[], is_and: bool) -> CondEval {
    match (residuals.length()) {
        // No residuals: every operand was statically known. An `and` that
        // reached here had no false operand (all true) -> true; an `or`
        // that reached here had no true operand (all false) -> false.
        0 => CondEval_Bool { _0: is_and },
        1 => {
            let single = residuals.pop() ?? RCond_Css { _0: "" };
            // A single surviving operand drops a redundant outer paren.
            let unwrapped: RCond = match (single) {
                let inner: RCond_Paren => inner._0,
                let other => other,
            };
            CondEval_Css { _0: unwrapped }
        },
        _ => {
            if (is_and) {
                CondEval_Css { _0: RCond_And { _0: residuals } }
            } else {
                CondEval_Css { _0: RCond_Or { _0: residuals } }
            }
        },
    }
}

/// Serialize a value for the modern `if()` value position. dart-sass 1.101.4
/// switched this from the `meta.inspect()` format to plain CSS serialization
/// (`serializeValue`, evaluate.dart `visitIfExpression`): lists lose their
/// parens (invisible items drop out), `null` serializes to nothing, and a
/// value with no CSS form (the empty list, a map, a function/mixin reference)
/// is an error. dart's own error here carries no source span, so ours is
/// unpositioned too.
function serialize_if_value(v: root.value.Value) -> string {
    match (v) {
        root.value.Value_Null {} => "",
        let l: root.value.Value_List if l._0.items.length() == 0 && !l._0.bracketed => {
            throw root.error.Error.unpositioned("() isn't a valid CSS value.");
        },
        let f: root.value.Value_Function => {
            throw root.error.Error.unpositioned(`${f._0.inspect()} isn't a valid CSS value.`);
        },
        let m: root.value.Value_Mixin => {
            throw root.error.Error.unpositioned(`${m._0.inspect()} isn't a valid CSS value.`);
        },
        let other => match (find_map(other)) {
            let m: root.value.Map => {
                throw root.error.Error.unpositioned(`${m.to_css(false)} isn't a valid CSS value.`);
            },
            _ => other.to_css(false),
        },
    }
}

/// The material one deprecation probe was made from, retained by
/// [`Evaluator::dep_memo`] so a fingerprint hit can be VERIFIED with `==`
/// rather than trusted. Lives on the evaluator and dies with it, so nothing
/// here outlives the arena scope of a single compile.
///
/// Every field is a bounded constant plus the current file's URL:
/// [`Evaluator::probe_arg_memoizable`] is what keeps `pos_args` and `named` from
/// holding a `Value` graph, so this struct's size does not depend on the size of
/// the sheet that produced it.
class DepProbe {
    url: string,
    name: string,
    module: string?,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
}

/// Which question a [`DepProbe`] answered. Part of the memo's key, because two
/// probes made at one span from the same arguments still ask different things —
/// `color.grayscale(1)` is asked about `[global-builtin]`, about
/// `[color-functions]` and about `[color-module-compat]`, and one answering for
/// another would silently drop a warning.
enum DepProbePath {
    /// [`Evaluator::emit_call_deprecations`] — the name-only ids.
    Call,
    /// [`Evaluator::emit_color_function_deprecation`]'s `[color-functions]`
    /// half, whose suggestions come from the argument VALUES.
    ColorFunction,
    /// Its `[color-module-compat]` half, gated on which overload the argument
    /// took.
    ColorModuleCompat,
}
