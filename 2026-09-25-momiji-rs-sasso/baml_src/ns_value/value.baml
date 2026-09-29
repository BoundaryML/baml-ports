// Ported from sasso `src/value.rs` (namespace `root.value`).
//
// The Sass value model and its CSS serialization.
//
// Numbers carry a unit, colors keep full `f64` channel precision (so
// computed colors serialize exactly like current dart-sass, e.g.
// `rgb(25%, 50%, 75%)` — dart re-spells a fractional triple as
// percentages), and colors remember their authored
// spelling so untransformed literals round-trip unchanged.

/// A fully-evaluated Sass value.
interface Value {
    /// Serialize as it would appear in a CSS declaration value, into `out`.
    ///
    /// This is the primitive for every caller that already has a buffer — a
    /// declaration's value, a list's elements, an interpolation — because the
    /// string a value serializes to is nearly always about to be copied into
    /// one. Every value a stylesheet can legally emit is written here without
    /// allocating; what falls through to [`Value::to_css`] is a map or a
    /// first-class function/mixin, none of which is a valid CSS value at all
    /// (a declaration rejects them before serializing) — they reach this only
    /// nested inside a list on an error path.
    function write_css(self, out: root.std.StrBuf, compressed: bool) -> void throws unknown {
        match (self) {
            Value_Number { _0: let n } => n.write_css(out, compressed),
            Value_Color { _0: let c } => c.write_css(out, compressed),
            Value_List { _0: let l } => l.write_css(out, compressed),
            Value_Str { _0: let s } => {
                if (s.quoted) {
                    push_quoted_styled(out, s.text, compressed);
                } else {
                    push_unquoted(out, s.text, compressed);
                }
            },
            Value_Bool { _0: let b } => {
                out.push_str(
                    if (b) {
                        "true"
                    } else {
                        "false"
                    },
                )
            },
            // The authored spelling of `12px/1.5`, already a string.
            Value_Slash { _0: _, _1: let repr } => out.push_str(repr),
            Value_Calc { _0: let node } => node.write_calc_value_css(out, compressed),
            Value_Null {} => {},
            let other => out.push_str(other.to_css(compressed)),
        }
    }

    /// [`Value::to_interp`] into `out`, on the same terms as
    /// [`Value::write_css`]: interpolating `#{$i}` or `#{$name}` writes the
    /// number or the string's raw text straight into the template's buffer.
    function write_interp(self, out: root.std.StrBuf) -> void throws unknown {
        match (self) {
            Value_Str { _0: let s } => out.push_str(s.text),
            Value_Null {} => {},
            Value_List { _0: let l } => l.write_interp(out),
            Value_Number { _0: let n } => n.write_css(out, false),
            Value_Color { _0: let c } => c.write_css(out, false),
            Value_Bool { _0: let b } => {
                out.push_str(
                    if (b) {
                        "true"
                    } else {
                        "false"
                    },
                )
            },
            Value_Slash { _0: _, _1: let repr } => out.push_str(repr),
            Value_Calc { _0: let node } => node.write_calc_value_css(out, false),
            let other => out.push_str(other.to_interp()),
        }
    }

    /// Serialize as it would appear in a CSS declaration value.
    function to_css(self, compressed: bool) -> string throws unknown {
        match (self) {
            Value_Number { _0: let n } => n.to_css(compressed),
            Value_Color { _0: let c } => c.to_css(compressed),
            Value_Str { _0: let s } => {
                if (s.quoted) {
                    serialize_quoted_styled(s.text, compressed)
                } else {
                    serialize_unquoted(s.text, compressed)
                }
            },
            Value_List { _0: let l } => l.to_css(compressed),
            Value_Map { _0: let m } => m.to_map_css(compressed),
            Value_Bool { _0: let b } => b.to_string(),
            Value_Null {} => "",
            Value_Slash { _0: _, _1: let repr } => repr,
            Value_Calc { _0: let node } => node.to_calc_value_css(compressed),
            // Not a valid CSS value; rendered for the "isn't a valid CSS value"
            // error and for `inspect`.
            Value_Function { _0: let func } => func.inspect(),
            Value_Mixin { _0: let m } => m.inspect(),
            _ => root.std.unreachable(),
        }
    }

    /// Serialize as it would appear inside `#{...}` interpolation, where
    /// strings lose their quotes.
    function to_interp(self) -> string throws unknown {
        match (self) {
            // A directly interpolated string contributes its RAW text (dart
            // `_performInterpolation` takes `result.text` verbatim); only a
            // string nested in a composite value goes through the unquoted
            // serializer (see `List::to_interp`).
            Value_Str { _0: let s } => s.text,
            Value_Null {} => "",
            Value_List { _0: let l } => l.to_interp(),
            Value_Map { _0: let m } => m.to_map_css(false),
            Value_Slash { _0: _, _1: let repr } => repr,
            Value_Calc { _0: let node } => node.to_calc_value_css(false),
            let other => other.to_css(false),
        }
    }

    /// The message text for `@warn` / `@debug`: a top-level string is shown
    /// **unquoted**, every other value (including strings nested in a list) is
    /// shown with the dart-sass `inspect()` serialization (`"a" "b"`, `a b c`,
    /// `(k: v)`). Matches dart-sass's `value.toString()`.
    function to_message(self) -> string throws unknown {
        match (self) {
            Value_Str { _0: let s } => s.text,
            let other => root.builtins.meta.inspect_value(other),
        }
    }

    /// dart-sass's `Value.toString()`: the spelling a value gets when a
    /// DIAGNOSTIC embeds it whole. It is `inspect()` plus one rule — an
    /// unbracketed, non-empty list is parenthesized, so the list's separator is
    /// never read as the sentence's own punctuation (`(1 2) is not a color.`).
    /// A string keeps its quotes. `inspect()` already parenthesizes the
    /// single-element comma and slash forms (`(1,)`, `(1/)`), which must not be
    /// wrapped a second time.
    ///
    /// Every message that embeds a whole value reads it from here, so the
    /// spellings cannot drift apart: `@error`, the legacy colour overloads'
    /// `$color: … is not a color.`, and the `Recommendation:` line of the
    /// removed `sass:color` members. Verified against dart-sass 1.104.1
    /// (2026-09-19), including the shapes where the three used to disagree: a
    /// one-element space list is `(1)`, not `1`.
    function to_inspect_message(self) -> string throws unknown {
        match (self) {
            Value_List { _0: let l } if !l.bracketed && l.items.length() != 0 => {
                if (l.items.length() == 1 && (l.sep == ListSep.Comma || l.sep == ListSep.Slash)) {
                    root.builtins.meta.inspect_value(self)
                } else {
                    `(${root.builtins.meta.inspect_value(self)})`
                }
            },
            let other => root.builtins.meta.inspect_value(other),
        }
    }

    function type_name(self) -> string throws never {
        match (self) {
            Value_Number {} => "number",
            Value_Color {} => "color",
            Value_Str {} => "string",
            // An argument list (`$args...`) reports as `arglist`, not `list`.
            Value_List { _0: let l } if l.keywords != null => "arglist",
            Value_List {} => "list",
            Value_Map {} => "map",
            Value_Bool {} => "bool",
            Value_Null {} => "null",
            Value_Slash {} => "number",
            Value_Calc {} => "calculation",
            Value_Function {} => "function",
            Value_Mixin {} => "mixin",
            _ => root.std.unreachable(),
        }
    }

    /// Collapse a top-level slash-division value to its plain `number`,
    /// matching dart-sass's `withoutSlash`. Numbers nested inside lists keep
    /// their slash spelling, so lists are returned unchanged.
    function without_slash(self) -> Value throws never {
        match (self) {
            Value_Slash { _0: let n, _1: _ } => Value_Number { _0: n },
            let other => other,
        }
    }

    /// Sass truthiness: everything except `false` and `null` is truthy.
    function is_truthy(self) -> bool throws never {
        let is_falsy = match (self) {
            Value_Bool { _0: false } | Value_Null {} => true,
            _ => false,
        };
        !is_falsy
    }

    /// Sass `==` equality. Numbers compare by value and unit; strings by
    /// text (quotedness is ignored); colors by channel; lists structurally.
    function sass_eq(self, other: Value) -> bool throws never {
        // A slash-division value compares as the plain number it wraps. Unwrap
        // only the slash operand(s) — the non-slash side is compared by
        // reference (no clone of a potentially large list/map).
        if (self is Value_Slash || other is Value_Slash) {
            // PORT: the `unwrap_num` temporaries are gone; the arms build the
            // wrapped number directly.
            let lhs: Value = match (self) {
                Value_Slash { _0: let n, _1: _ } => Value_Number { _0: n },
                let other => other,
            };
            let rhs: Value = match (other) {
                Value_Slash { _0: let n, _1: _ } => Value_Number { _0: n },
                let other => other,
            };
            return lhs.sass_eq(rhs);
        }
        // PORT: `match (self, other)` → a match on `self` whose arms match
        // `other`; the `(Map, List) | (List, Map)` arm is split between the Map
        // and List arms.
        match (self) {
            Value_Number { _0: let a } => match (other) {
                Value_Number { _0: let b } => numbers_eq(a, b),
                _ => false,
            },
            // PORT: derived `PartialEq` on `CalcNode` → structural `==` (which,
            // unlike Rust's f64 `==`, holds a NaN operand equal to itself).
            Value_Calc { _0: let a } => match (other) {
                Value_Calc { _0: let b } => a == b,
                _ => false,
            },
            Value_Str { _0: let a } => match (other) {
                Value_Str { _0: let b } => a.text == b.text,
                _ => false,
            },
            Value_Color { _0: let a } => match (other) {
                Value_Color { _0: let b } => color_sass_eq(a, b),
                _ => false,
            },
            Value_Bool { _0: let a } => match (other) {
                Value_Bool { _0: let b } => a == b,
                _ => false,
            },
            Value_Null {} => match (other) {
                Value_Null {} => true,
                _ => false,
            },
            Value_List { _0: let a } => match (other) {
                Value_List { _0: let b } => {
                    // PORT: `.zip().all()` → an index loop.
                    let all = a.sep == b.sep
                        && a.bracketed == b.bracketed
                        && a.items.length() == b.items.length();
                    let i = 0;
                    while (all && i < a.items.length()) {
                        all = a.items[i].sass_eq(b.items[i]);
                        i += 1;
                    }
                    all
                },
                // An empty map and an empty list are equal in dart-sass.
                Value_Map { _0: let m } => m.entries.length() == 0 && a.items.length() == 0,
                _ => false,
            },
            // Maps compare by content regardless of entry order.
            Value_Map { _0: let a } => match (other) {
                Value_Map { _0: let b } => {
                    a.entries.length() == b.entries.length()
                        && a.entries.every((e) -> {
                            let bv = b.get(e._0);
                            if (bv != null) {
                                bv.sass_eq(e._1)
                            } else {
                                false
                            }
                        })
                },
                // An empty map and an empty list are equal in dart-sass.
                Value_List { _0: let l } => a.entries.length() == 0 && l.items.length() == 0,
                _ => false,
            },
            // Function references: built-ins by name, user functions by the
            // identity of their captured definition (see `SassFunction`).
            Value_Function { _0: let a } => match (other) {
                Value_Function { _0: let b } => a == b,
                _ => false,
            },
            // Mixin references: built-ins by name, user mixins by the identity
            // of their captured definition (see `SassMixin`).
            Value_Mixin { _0: let a } => match (other) {
                Value_Mixin { _0: let b } => a == b,
                _ => false,
            },
            _ => false,
        }
    }
}

/// A number with an optional unit.
class Value_Number {
    _0: Number,
    implements Value {}
}

/// An sRGB color with an alpha channel.
class Value_Color {
    _0: Color,
    implements Value {}
}

/// A quoted or unquoted string.
class Value_Str {
    _0: SassStr,
    implements Value {}
}

/// A space- or comma-separated list.
class Value_List {
    _0: List,
    implements Value {}
}

/// A map of key/value pairs, preserving insertion order. Keys are
/// compared by Sass `==`. An empty map serializes (and inspects) as `()`.
class Value_Map {
    _0: Map,
    implements Value {}
}

/// A boolean.
class Value_Bool {
    _0: bool,
    implements Value {}
}

/// The `null` value.
class Value_Null {
    implements Value {}
}

/// A number produced by the deprecated `a / b` slash division of two
/// numeric literals. It behaves as `number` numerically (so arithmetic
/// and functions use `number`), but serializes as the original
/// `left/right` slash text. The slash is dropped (collapsing to
/// `number`) when the value crosses a variable, function/mixin, or
/// arithmetic boundary — matching dart-sass.
class Value_Slash {
    _0: Number,
    _1: string,
    implements Value {}
}

/// A `calc()` calculation that could not be reduced to a single number
/// (e.g. it contains `var()`, an interpolation, or incompatible units).
/// Stored as its simplified operand tree for canonical serialization.
class Value_Calc {
    _0: CalcNode,
    implements Value {}
}

/// A first-class function reference (`meta.get-function(...)`), invoked via
/// `meta.call`. Not a valid CSS value; `inspect` renders it as
/// `get-function("name")`.
class Value_Function {
    _0: SassFunction,
    implements Value {}
}

/// A first-class mixin reference (`meta.get-mixin(...)`), invoked via
/// `@include meta.apply(...)`. Not a valid CSS value; `inspect` renders it
/// as `get-mixin("name")`.
// Boxed: a first-class mixin carries an optional captured file context, so
// the inline struct is larger than Value's 64-byte budget. Mixins are never
// emitted as CSS, so the indirection is off every hot path.
class Value_Mixin {
    _0: SassMixin,
    implements Value {}
}

/// `Value` is moved/cloned constantly (every scope slot, every `Vec<Value>`
/// element, every `$var` read), so its size is a hot-path constant. `Color` was
/// the sole 128-byte variant (its 72-byte `ModernColor` is now boxed); keep
/// `Value` at one cache line. Bump this only with a deliberate measurement.
// PORT: compile-time assertion dropped: const _: () = assert!(std::mem::size_of::<Value>() <= 64)

/// One of the `sass:*` built-in modules, recorded as the provenance of a
/// first-class function reference. A `u8`-sized enum rather than a `String`
/// because it rides inside [`Value`], which is pinned to one cache line.
enum BuiltinModule {
    Color,
    List,
    Map,
    Math,
    Meta,
    Selector,
    String,
}

interface BuiltinModuleMethods {
    /// The module's name, as it is written after `sass:`.
    function name(self) -> string throws unknown;
}

implements BuiltinModuleMethods for BuiltinModule {
    /// The module's name, as it is written after `sass:`.
    function name(self) -> string {
        match (self) {
            BuiltinModule.Color => "color",
            BuiltinModule.List => "list",
            BuiltinModule.Map => "map",
            BuiltinModule.Math => "math",
            BuiltinModule.Meta => "meta",
            BuiltinModule.Selector => "selector",
            BuiltinModule.String => "string",
        }
    }

}

/// The module for a `sass:` namespace name, or `None` for anything that is
/// not a built-in module.
function BuiltinModule_from_name(name: string) -> BuiltinModule? {
    match (name) {
        "color" => BuiltinModule.Color,
        "list" => BuiltinModule.List,
        "map" => BuiltinModule.Map,
        "math" => BuiltinModule.Math,
        "meta" => BuiltinModule.Meta,
        "selector" => BuiltinModule.Selector,
        "string" => BuiltinModule.String,
        _ => {
            return null;
        },
    }
}

/// A first-class function reference. Built-in references compare equal by name
/// (and CSS flag, and the module they were taken from); user references compare
/// by identity of the captured definition (so a redefined `@function` yields a
/// distinct reference). The captured user definition is held as a type-erased
/// `Rc` (the concrete `Callable` lives in `ast`, which cannot be referenced
/// from this module without a dependency cycle); the evaluator downcasts it
/// when invoking.
class SassFunction {
    /// The function's name (for `inspect` and error messages).
    name: string,
    /// Whether this is a plain-CSS reference (`$css: true`), which is preserved
    /// verbatim instead of dispatched to a Sass builtin.
    css: bool,
    /// The built-in module this reference came from, for one taken through a
    /// module (`meta.get-function("get", $module: "map")`, or a bare name a
    /// `@use "sass:map" as *` exposes). A module member is NOT the global alias
    /// of the same function: dart keeps the member's own name, compares the two
    /// references unequal, and deprecates only the global spelling.
    module: BuiltinModule?,
    /// The captured user `@function` definition, or `None` for a built-in /
    /// plain-CSS reference. Type-erased to break the `ast` ↔ `value` cycle.
    user: unknown,
    /// The `inspect()` / debug form, `get-function("name")` (dart-sass).
    function inspect(self) -> string {
        `get-function("${self.name}")`
    }

    // PORT: `impl std::fmt::Debug` dropped (derive-like / not needed in BAML).

    implements baml.ops.Equals {
        function eq(self, other: SassFunction) -> bool {
            // PORT: `match (&self.user, &other.user)` → an `if` chain on presence.
            if (self.user != null && other.user != null) {
                // User references: identity of the captured definition.
                // PORT: `Rc::ptr_eq` → `==`: BAML has no reference identity. `==`
                // settles two references to the same object without inspecting it,
                // and otherwise compares the captured definitions structurally
                // (distinct definitions differ at least in their source span).
                self.user == other.user
            } else if (self.user == null && other.user == null) {
                // Built-in / plain-CSS references: same name, CSS flag and module.
                self.name == other.name && self.css == other.css && self.module == other.module
            } else {
                false
            }
        }
    }
}

/// A first-class mixin reference, analogous to [`SassFunction`]. Built-in
/// references (e.g. `meta.load-css`) compare equal by name; user references
/// compare by identity of the captured `@mixin` definition (so a redefined
/// `@mixin` yields a distinct reference). The captured user definition is held
/// as a type-erased `Rc` (the concrete `Callable` lives in `ast`, which cannot
/// be referenced from this module without a dependency cycle); the evaluator
/// downcasts it when invoking.
class SassMixin {
    /// The mixin's name (for `inspect` and error messages).
    name: string,
    /// The captured user `@mixin` definition, or `None` for a built-in
    /// reference. Type-erased to break the `ast` ↔ `value` cycle.
    user: unknown,
    /// The module the captured mixin came from, when it was resolved from
    /// another `@use`d module (so its body runs in that module's environment).
    /// `None` for a same-module reference. Type-erased to break the cycle.
    module: unknown,
    /// The `inspect()` / debug form, `get-mixin("name")` (dart-sass).
    function inspect(self) -> string {
        `get-mixin("${self.name}")`
    }

    // PORT: `impl std::fmt::Debug` dropped (derive-like / not needed in BAML).

    implements baml.ops.Equals {
        function eq(self, other: SassMixin) -> bool {
            // PORT: `match (&self.user, &other.user)` → an `if` chain on presence.
            if (self.user != null && other.user != null) {
                // User references: identity of the captured definition.
                // PORT: `Rc::ptr_eq` → `==` (see `SassFunction::eq`).
                self.user == other.user
            } else if (self.user == null && other.user == null) {
                // Built-in references: same name.
                self.name == other.name
            } else {
                false
            }
        }
    }
}

/// The file a callable was written in, captured with it. Its body runs against
/// this file: diagnostics name it, output maps to it, and a relative
/// `meta.load-css` inside it resolves against its directory — wherever the
/// callable is later called from. Held as plain strings (plus the text itself)
/// to keep `value` free of `eval`/`ast` types.
class MixinOrigin {
    /// The diagnostic display URL of the defining file (e.g. `src/_mod.scss`).
    diag_url: string,
    /// The defining file's directory (the legacy `@import` resolution base);
    /// empty when there is none.
    file_dir: string,
    /// The defining file's canonical URL (the importer resolution base).
    canonical: string,
    /// The defining file's text, for snippets. Carried here rather than looked
    /// up by `diag_url`: display names are not unique across custom importers
    /// (two canonical URLs may share a last segment), the canonical URL is.
    source: string,
}

/// A node in a simplified `calc()` tree. Numeric subtrees are folded during
/// evaluation; everything else (variables, interpolations, percentages with
/// incompatible neighbours) is preserved for canonical serialization.
interface CalcNode {
    /// Serialize this node's interior (without the enclosing `calc(`...`)`) into
    /// `out`, adding parentheses only where operator precedence/associativity
    /// requires them, matching dart-sass's canonical form.
    ///
    /// This is the primitive, and it allocates nothing: a calculation is a tree,
    /// so building each node's text as a string of its own meant one allocation
    /// per node plus one per operator gap, all of them immediately concatenated
    /// into the parent's. Writing into the caller's buffer is the same walk
    /// without the intermediate strings. [`CalcNode::to_calc_css`] wraps it for
    /// callers that want a string.
    function write_calc_css(self, out: root.std.StrBuf, compressed: bool) -> void throws never {
        match (self) {
            CalcNode_Number { _0: let n } => write_calc_number(out, n, compressed),
            CalcNode_Str { _0: let s } => out.push_str(s),
            CalcNode_Op { op: let op, left: let left, right: let right } => {
                self.write_operand(out, left, op, false, compressed);
                // A `+ -n` / `- -n` numeric right operand flips the operator,
                // in every output style: dart-sass does this when it builds the
                // operation (`SassCalculation._operateInternal`: `right.value <
                // 0` → negate the operand and swap the operator), so the flip
                // is already baked into the tree it serializes. The test is
                // exactly `< 0`, which excludes `-0` and NaN but INCLUDES
                // `-infinity` (`+ -infinity * 1em` → `- infinity * 1em`).
                //
                // `write_calc_number`, not `write_css`, because a non-finite or
                // complex-unit operand renders as a `*`/`/` chain here rather
                // than a `calc()` constant. It needs no parentheses under an
                // add/sub parent: `write_operand` would only parenthesize a
                // `Mul`-precedence child of a *higher*-precedence parent.
                if (op == CalcOp.Add || op == CalcOp.Sub) {
                    if let CalcNode_Number { _0: let n } = right {
                        if (n.value < 0.0) {
                            out.push(" ");
                            out.push_str(
                                if (op == CalcOp.Add) {
                                    "-"
                                } else {
                                    "+"
                                },
                            );
                            out.push(" ");
                            write_calc_number(out, n.copy_units(-n.value), compressed);
                            return;
                        }
                    }
                }
                // PORT: `match (op, compressed)` → an `if`.
                if ((op == CalcOp.Mul || op == CalcOp.Div) && compressed) {
                    out.push_str(op.symbol());
                } else {
                    out.push(" ");
                    out.push_str(op.symbol());
                    out.push(" ");
                }
                self.write_operand(out, right, op, true, compressed);
            },
            CalcNode_Func { name: let name, args: let args } => {
                out.push_str(name);
                out.push("(");
                let i = 0;
                for (let arg in args) {
                    if (i > 0) {
                        out.push_str(
                            if (compressed) {
                                ","
                            } else {
                                ", "
                            },
                        );
                    }
                    arg.write_calc_css(out, compressed);
                    i += 1;
                }
                out.push(")");
            },
            _ => root.std.unreachable(),
        }
    }

    /// Serialize this node's interior (without the enclosing `calc(`...`)`),
    /// adding parentheses only where operator precedence/associativity
    /// requires them, matching dart-sass's canonical form.
    function to_calc_css(self, compressed: bool) -> string throws never {
        let out = root.std.StrBuf.new();
        self.write_calc_css(out, compressed);
        out.as_str()
    }

    /// [`CalcNode::to_calc_value_css`] into `out`.
    function write_calc_value_css(
        self,
        out: root.std.StrBuf,
        compressed: bool,
    ) -> void throws never {
        match (self) {
            CalcNode_Func {} => self.write_calc_css(out, compressed),
            _ => {
                out.push_str("calc(");
                self.write_calc_css(out, compressed);
                out.push(")");
            },
        }
    }

    /// Serialize as the top-level `Value::Calc` holding this node would: a
    /// calculation-function node renders bare as `name(args)`, while any other
    /// node is wrapped in `calc(...)`.
    function to_calc_value_css(self, compressed: bool) -> string throws never {
        let out = root.std.StrBuf.new();
        self.write_calc_value_css(out, compressed);
        out.as_str()
    }

    /// Write `operand` as a child of a parent `op`, wrapping in parens when
    /// the child binds more loosely (or equally on the right of `-`/`/`).
    function write_operand(
        self,
        out: root.std.StrBuf,
        operand: CalcNode,
        parent: CalcOp,
        is_right: bool,
        compressed: bool,
    ) -> void throws never {
        // A unit-carrying non-finite number renders as a `*` operation
        // (`infinity * 1px`), so it parenthesizes like a `Mul`-precedence
        // child rather than a bare leaf number.
        let child_op: CalcOp? = match (operand) {
            CalcNode_Op { op: let op } => op,
            CalcNode_Number { _0: let n } if !n.value.is_finite() && !n.is_unitless() => CalcOp.Mul,
            _ => null,
        };
        if (child_op != null) {
            let needs_paren = child_op.precedence() < parent.precedence()
                || (
                    child_op.precedence() == parent.precedence()
                        && is_right
                        && (parent == CalcOp.Sub || parent == CalcOp.Div)
                );
            if (needs_paren) {
                out.push("(");
                operand.write_calc_css(out, compressed);
                out.push(")");
                return;
            }
        }
        operand.write_calc_css(out, compressed);
    }
}

/// A resolved number operand.
class CalcNode_Number {
    _0: Number,
    implements CalcNode {}
}

/// An opaque operand: `var(--x)`, an interpolation result, a nested
/// unknown function — anything kept verbatim.
class CalcNode_Str {
    _0: string,
    implements CalcNode {}
}

/// A binary operation `left <op> right`.
class CalcNode_Op {
    op: CalcOp,
    left: CalcNode,
    right: CalcNode,
    implements CalcNode {}
}

/// A calculation function call that could not be reduced to a number
/// (`min`/`max`/`clamp`/`hypot`/…). The `Value::Calc` holding this serializes
/// as `name(arg, …)` (no `calc()` wrapper).
class CalcNode_Func {
    name: string,
    args: CalcNode[],
    implements CalcNode {}
}

/// A `calc()` binary operator.
enum CalcOp {
    Add,
    Sub,
    Mul,
    Div,
}

interface CalcOpMethods {
    function symbol(self) -> string throws unknown;

    /// Precedence: `*`/`/` bind tighter than `+`/`-`.
    function precedence(self) -> int throws unknown;
}

implements CalcOpMethods for CalcOp {
    function symbol(self) -> string {
        match (self) {
            CalcOp.Add => "+",
            CalcOp.Sub => "-",
            CalcOp.Mul => "*",
            CalcOp.Div => "/",
        }
    }

    /// Precedence: `*`/`/` bind tighter than `+`/`-`.
    function precedence(self) -> int {
        match (self) {
            CalcOp.Add | CalcOp.Sub => 1,
            CalcOp.Mul | CalcOp.Div => 2,
        }
    }

}

/// Write a number as it appears inside a `calc()` interior. Finite single-unit
/// numbers use their ordinary CSS form. Non-finite numbers use dart-sass's
/// canonical lowercase constants — `infinity` / `-infinity` / `NaN`, with units
/// spelled out as operands (`infinity * 1px`). Multi-unit numbers spell every
/// unit as an operand: a finite value attaches to the first numerator
/// (`1000px * 1rad / 1Hz`), a numerator-less one stays bare (`1 / 1px`).
function write_calc_number(out: root.std.StrBuf, n: Number, compressed: bool) -> void {
    if (n.value.is_finite() && !n.has_complex_units()) {
        n.write_css(out, compressed);
        return;
    }
    let star = if (compressed) {
        "*"
    } else {
        " * "
    };
    let slash = if (compressed) {
        "/"
    } else {
        " / "
    };
    // PORT: the `numer` iterator is the unit array plus a cursor.
    let numer = n.numer_units();
    let numer_pos = 0;
    if (n.value.is_finite()) {
        // A finite value rides on the first numerator unit when there is one.
        push_num(out, n.value, compressed);
        let u = numer.at(numer_pos);
        if (u != null) {
            numer_pos += 1;
            out.push_str(u);
        }
    } else {
        out.push_str(
            if (n.value.is_nan()) {
                "NaN"
            } else if (n.value > 0.0) {
                "infinity"
            } else {
                "-infinity"
            },
        );
    }
    for (let u in numer.slice(numer_pos, numer.length())) {
        out.push_str(star);
        out.push("1");
        out.push_str(u);
    }
    for (let u in n.denom_units()) {
        out.push_str(slash);
        out.push("1");
        out.push_str(u);
    }
}

/// A number with its units (dart-sass `SassNumber`: a list of numerator units
/// and a list of denominator units). The representation keeps the two
/// overwhelmingly common cases — unitless and a single numerator unit — free of
/// any unit list; multi-unit numbers (`px*px`, `px/s`) box their unit lists.
class Number {
    value: float,
    units: Units,
    function unitless(value: float) -> Number {
        Number { value: value, units: Units_None {  } }
    }

    /// A number with zero or one numerator unit (`""` means unitless).
    ///
    /// The unit comes in BORROWED: unitless is the common case and it must not
    /// allocate, and a caller that has to spell the unit out (`"deg"`, a
    /// literal's suffix) should pay for exactly one buffer, not a `String` it
    /// then copies into an `Rc`.
    function with_unit(value: float, unit: string) -> Number {
        Number {
            value: value,
            units: if (unit == "") {
                Units_None {  }
            } else {
                Units_Single { _0: unit }
            },
        }
    }

    /// A number reusing an existing unit name — a numeric literal's, spelled
    /// out once by the parser — so that evaluating the literal again costs a
    /// refcount bump and nothing else.
    function with_shared_unit(value: float, unit: string) -> Number {
        Number {
            value: value,
            units: if (unit == "") {
                Units_None {  }
            } else {
                Units_Single { _0: unit }
            },
        }
    }

    /// A number with full numerator/denominator unit lists, normalized to the
    /// compact representation when possible. No unit cancellation happens
    /// here — callers cancel before constructing (dart-sass keeps whatever
    /// lists arithmetic produces).
    function with_units(value: float, numer: string[], denom: string[]) -> Number {
        let units: Units = if (denom.length() == 0 && numer.length() <= 1) {
            // PORT: `numer.pop()` → the last element, read without popping: the
            // argument may be an array another number still holds.
            match (root.std.last(numer)) {
                null => Units_None {  },
                let u: string => Units_Single { _0: u },
            }
        } else {
            Units_Complex { _0: ComplexUnits { numer: numer, denom: denom } }
        };
        Number { value: value, units: units }
    }

    /// A new number carrying this number's units (the common "derive a result
    /// from an operand" pattern; preserves multi-unit lists).
    function copy_units(self, value: float) -> Number {
        // PORT: `self.units.clone()` → shared: units are never mutated in place.
        Number { value: value, units: self.units }
    }

    function is_unitless(self) -> bool {
        self.units is Units_None
    }

    /// The single unit for the common path: `""` when unitless, the unit of a
    /// single-numerator number, or the FIRST numerator unit of a multi-unit
    /// number (callers that can meet multi-unit numbers must check
    /// [`Number::has_complex_units`] first).
    function unit(self) -> string {
        match (self.units) {
            Units_None {} => "",
            Units_Single { _0: let u } => u,
            Units_Complex { _0: let c } => c.numer.at(0) ?? "",
            _ => root.std.unreachable(),
        }
    }

    function has_complex_units(self) -> bool {
        self.units is Units_Complex
    }

    function numer_units(self) -> string[] {
        match (self.units) {
            Units_None {} => [],
            Units_Single { _0: let u } => [u],
            Units_Complex { _0: let c } => c.numer,
            _ => root.std.unreachable(),
        }
    }

    function denom_units(self) -> string[] {
        match (self.units) {
            Units_None {} | Units_Single {} => [],
            Units_Complex { _0: let c } => c.denom,
            _ => root.std.unreachable(),
        }
    }

    /// Serialize as it would appear in a CSS declaration value, into `out`.
    /// This is the hottest serialization path in the compiler — every dimension
    /// in every declaration — and it allocates nothing: the digits and the unit
    /// are generated where they belong.
    function write_css(self, out: root.std.StrBuf, compressed: bool) -> void {
        // A non-finite number serializes as a `calc()` constant, matching
        // dart-sass: a unitless `infinity`/`-infinity`/`NaN` prints as
        // `calc(infinity)` etc., and a unit-bearing one as `calc(infinity * 1px)`.
        // A multi-unit number likewise has no plain CSS form and serializes as
        // a calc with its units spelled out (`calc(1px * 1em)`, `calc(1 / 1px)`)
        // — dart-sass uses this form everywhere, including `meta.inspect`,
        // interpolation, and error messages.
        if (!self.value.is_finite() || self.has_complex_units()) {
            out.push_str("calc(");
            write_calc_number(out, self, compressed);
            out.push(")");
            return;
        }
        push_num(out, self.value, compressed);
        push_unit_escaped(out, self.unit());
    }

    function to_css(self, compressed: bool) -> string {
        let s = root.std.StrBuf.new();
        self.write_css(s, compressed);
        s.as_str()
    }

    /// dart-sass `unitString`: the human-readable unit list — `px`, `px*em`,
    /// `px/em`, `px*em/(rad*s)`, `px^-1`, `(px*em)^-1`, or `""` for unitless.
    /// Used by `math.unit()`.
    function unit_string(self) -> string {
        let numer = self.numer_units();
        let denom = self.denom_units();
        // PORT: `match (numer.is_empty(), denom.is_empty())` → an `if` chain.
        if (denom.length() == 0) {
            root.std.join(numer, "*")
        } else if (numer.length() == 0) {
            if (denom.length() == 1) {
                `${denom[0]}^-1`
            } else {
                `(${denom.join("*")})^-1`
            }
        } else {
            if (denom.length() == 1) {
                `${numer.join("*")}/${denom[0]}`
            } else {
                `${numer.join("*")}/(${denom.join("*")})`
            }
        }
    }

    /// Multiply by `other` with dart-sass `multiplyUnits` cancellation: each
    /// numerator cancels the first convertible denominator on the other side
    /// (scaling the value by the conversion), leftovers concatenate.
    function mul(self, other: Number) -> Number {
        // Fast path: a unitless operand has nothing to cancel or concatenate,
        // so the result carries the other side's units verbatim — no unit-list
        // materialization (the general path builds four unit vectors).
        if (other.units is Units_None) {
            return self.copy_units(self.value * other.value);
        }
        if (self.units is Units_None) {
            return other.copy_units(self.value * other.value);
        }
        multiply_units(
            self.value * other.value,
            root.std.clone_vec(self.numer_units()),
            root.std.clone_vec(self.denom_units()),
            root.std.clone_vec(other.numer_units()),
            root.std.clone_vec(other.denom_units()),
        )
    }

    /// Divide by `other` (multiplication with `other`'s units inverted).
    function div(self, other: Number) -> Number {
        // Fast paths mirroring `mul`: a unitless divisor leaves the units
        // untouched, and same-named single units cancel exactly (`px/px`).
        if (other.units is Units_None) {
            return self.copy_units(self.value / other.value);
        }
        if let Units_Single { _0: let a } = self.units {
            if let Units_Single { _0: let b } = other.units {
                if (a == b) {
                    return Number.unitless(self.value / other.value);
                }
            }
        }
        multiply_units(
            self.value / other.value,
            root.std.clone_vec(self.numer_units()),
            root.std.clone_vec(self.denom_units()),
            root.std.clone_vec(other.denom_units()),
            root.std.clone_vec(other.numer_units()),
        )
    }
}

/// A unit name is held as `Rc<str>`, like [`SassStr`]'s text, so that cloning
/// a number — which happens on every `$var` read, every operand copied out of
/// an operation and every value handed to a builtin — is a refcount bump rather
/// than a heap copy of `px`. Units are immutable: a number never edits its own
/// unit name, it builds a new one, so the sharing is invisible.
interface Units {}

class Units_None {
    implements Units {}
}

class Units_Single {
    _0: string,
    implements Units {}
}

class Units_Complex {
    _0: ComplexUnits,
    implements Units {}
}

/// The unit lists of a multi-unit number. Invariant (kept by
/// [`Number::with_units`]): not representable as `None`/`Single` — there is a
/// denominator unit, or more than one numerator unit.
class ComplexUnits {
    numer: string[],
    denom: string[],
}

/// A string value; `quoted` controls whether it serializes with quotes.
///
/// The payload is held as `Rc<str>` so cloning a `Value::Str` (e.g. on every
/// read-only `$var` lookup) is an O(1) refcount bump rather than a heap copy of
/// the text. Strings are immutable Sass values, so the sharing is invisible:
/// any "mutating" string builtin builds a fresh `Rc<str>`.
class SassStr {
    text: string,
    quoted: bool,
}

/// A private-use code point per dart-sass `isPrivateUseCharacter`: the BMP
/// private-use area plus the whole of planes 15 and 16 (so `\e000`, `\f0000`,
/// `\10fffd` escape, while a non-character like `\fdd0` or `\f900` stays raw).
function is_private_use(cp: int) -> bool {
    (cp >= 0xE000 && cp <= 0xF8FF) || (cp >= 0xF0000 && cp <= 0x10FFFF)
}

/// Serialize a string as a quoted CSS string, matching dart-sass's
/// `_visitQuotedString`. The text holds decoded code points; this re-escapes
/// only what it must: the chosen quote character, backslashes, control
/// characters (everything `0x00..=0x1F` except tab, plus `0x7F`), and
/// private-use characters. Double quotes are preferred; a string that contains
/// `"` but no `'` is wrapped in `'`.
function serialize_quoted(text: string) -> string {
    serialize_quoted_styled(text, false)
}

/// [`serialize_quoted`] for CSS OUTPUT, which depends on the style: dart
/// escapes a private-use character in expanded output — they are not rendered
/// consistently, so the escape is the safer spelling — but writes it raw when
/// compressing, where the escape costs more bytes than the character. (The
/// output then holds non-ASCII text, and picks up the `@charset`/BOM that
/// comes with it.) Everything else escapes the same either way.
function serialize_quoted_styled(text: string, compressed: bool) -> string {
    let out = root.std.StrBuf.with_capacity(text.length() + 2);
    push_quoted_styled(out, text, compressed);
    out.as_str()
}

/// [`serialize_quoted_styled`] into the caller's buffer.
function push_quoted_styled(out: root.std.StrBuf, text: string, compressed: bool) -> void {
    let has_double = text.includes("\"");
    let has_single = text.includes("'");
    // Use single quotes only when the text has a `"` and no `'`.
    let quote = if (has_double && !has_single) {
        "'"
    } else {
        "\""
    };
    push_quoted_with_styled(out, text, quote, compressed);
}

/// The same, with the quote character already chosen — for a string whose
/// quote depends on more than this fragment (an interpolated one, whose pieces
/// are escaped separately but must share one quote).
function serialize_quoted_with(text: string, quote: string) -> string {
    serialize_quoted_with_styled(text, quote, false)
}

/// [`serialize_quoted_with`] for CSS output — see [`serialize_quoted_styled`]
/// for what the style changes.
function serialize_quoted_with_styled(text: string, quote: string, compressed: bool) -> string {
    let out = root.std.StrBuf.with_capacity(text.length() + 2);
    push_quoted_with_styled(out, text, quote, compressed);
    out.as_str()
}

/// [`serialize_quoted_with_styled`] into the caller's buffer: a quoted string
/// in a list or a declaration value is written where it belongs instead of into
/// a string of its own.
function push_quoted_with_styled(
    out: root.std.StrBuf,
    text: string,
    quote: string,
    compressed: bool,
) -> void {
    // A private-use character is escaped only when NOT compressing.
    let escapes_private_use = !compressed;
    // Fast path: when no character needs escaping, the body is `text` verbatim
    // between the quotes — skip the `Vec<char>` and the per-char loop. The
    // predicate mirrors the loop's two escape branches exactly.
    let needs_escape = text.chars().some((c) -> {
        let cp = root.std.ord(c);
        c == quote
            || c == "\\"
            || (cp <= 0x1F && c != "\t")
            || cp == 0x7F
            || (escapes_private_use && is_private_use(cp))
    });
    if (!needs_escape) {
        // PORT: `out.reserve(..)` dropped (capacity hint).
        out.push(quote);
        out.push_str(text);
        out.push(quote);
        return;
    }
    let chars: string[] = text.chars();
    // PORT: `out.reserve(..)` dropped (capacity hint).
    out.push(quote);
    let i = 0;
    while (i < chars.length()) {
        let c = chars[i];
        let cp = root.std.ord(c);
        if (c == quote || c == "\\") {
            out.push("\\");
            out.push(c);
        } else if ((cp <= 0x1F && c != "\t") || cp == 0x7F || (escapes_private_use && is_private_use(cp))) {
            // A control character, DEL, or a private-use character: `\<hex>`
            // with a trailing space only when the next character would otherwise
            // extend the escape (a hex digit, space, or tab).
            out.push("\\");
            out.push_str(root.std.hex_lower(cp));
            let n = chars.at(i + 1);
            let needs_space = root.std.is_ascii_hexdigit(n) || n == " " || n == "\t";
            if (needs_space) {
                out.push(" ");
            }
        } else {
            out.push(c);
        }
        i += 1;
    }
    out.push(quote);
}

/// Serialize an unquoted string for CSS / interpolation output (dart-sass
/// `_visitUnquotedString`): a newline becomes a space, and a space directly
/// after a newline is dropped so `"\a "`-style line breaks collapse to a single
/// space; a private-use character is escaped as `\<hex>` in every style BUT
/// compressed (control characters, unlike in a quoted string, are written
/// verbatim here); every other code point is written verbatim.
function serialize_unquoted(text: string, compressed: bool) -> string {
    let out = root.std.StrBuf.new();
    push_unquoted(out, text, compressed);
    out.as_str()
}

/// [`serialize_unquoted`] into the caller's buffer. Almost every unquoted
/// string is written verbatim — `bold`, `solid`, `inherit`, a url — so this
/// costs nothing beyond the copy the caller was going to make anyway.
function push_unquoted(out: root.std.StrBuf, text: string, compressed: bool) -> void {
    // dart's `_tryPrivateUseCharacter` gives up immediately when compressing:
    // an escape is for a READER, who cannot tell two unrendered glyphs apart,
    // and compressed output has no reader. The character then goes out as its
    // own UTF-8 bytes, which is what makes the file non-ASCII and earns it the
    // BOM `emit` prepends.
    let escapes_private_use = !compressed;
    // Fast path: nothing to rewrite unless a newline or private-use char is
    // present. Scan without allocating; only collect into a `Vec<char>` (needed
    // for the escape look-ahead) on the rare slow path.
    if (
        !text.chars().some((c) -> {
            c == "\n" || (escapes_private_use && is_private_use(root.std.ord(c)))
        })
    ) {
        out.push_str(text);
        return;
    }
    let chars: string[] = text.chars();
    // PORT: `out.reserve(..)` dropped (capacity hint).
    let after_newline = false;
    for (let i in baml.iter.Range.new(0, chars.length())) {
        let c = chars[i];
        let cp = root.std.ord(c);
        if (escapes_private_use && is_private_use(cp)) {
            out.push("\\");
            out.push_str(root.std.hex_lower(cp));
            let n = chars.at(i + 1);
            let needs_space = root.std.is_ascii_hexdigit(n) || n == " " || n == "\t";
            if (needs_space) {
                out.push(" ");
            }
            after_newline = false;
            continue;
        }
        match (c) {
            "\n" => {
                out.push(" ");
                after_newline = true;
            },
            " " => {
                if (!after_newline) {
                    out.push(" ");
                }
            },
            _ => {
                out.push(c);
                after_newline = false;
            },
        }
    }
}

/// A list value.
///
/// `items` is held as `Rc<[Value]>` so cloning a `Value::List` (e.g. on every
/// read-only `$var` lookup, or passing a list through a function) is an O(1)
/// refcount bump rather than a deep element copy. Lists are immutable Sass
/// values; every "mutating" list builtin (`append`, `join`, `set-nth`, …)
/// builds a fresh `Vec<Value>` and re-wraps it in a new `Rc`, so the sharing is
/// invisible.
class List {
    items: Value[],
    sep: ListSep,
    /// Whether the list was written with square brackets (`[a b]`); such
    /// lists serialize wrapped in `[`...`]` and report `true` from
    /// `list.is-bracketed`.
    bracketed: bool,
    /// `Some` when this list is an *argument list* (`$args...`): it carries the
    /// caller's leftover keyword arguments (name -> value), which `meta.keywords`
    /// reads and a `$args...` splat forwards as named arguments. `None` for an
    /// ordinary list. The positional arguments are the list's `items`.
    keywords: root.std.Tuple2<Value, Value>[]?,
    /// An ordinary (non-argument) list.
    function new(items: Value[], sep: ListSep, bracketed: bool) -> List {
        List { items: items, sep: sep, bracketed: bracketed, keywords: null }
    }

    /// Serialize into `out`, element by element. A shorthand value such as
    /// `0 auto` used to cost a string per element, a vector of them, a joined
    /// buffer and — bracketed — a fourth for the brackets; it now costs none of
    /// those, because every element writes where it belongs.
    function write_css(self, out: root.std.StrBuf, compressed: bool) -> void {
        // PORT: `match (self.sep, compressed)` → a match on `sep` with `if`s.
        let sep = match (self.sep) {
            // An undecided list has at most one element, so its separator
            // string is never actually used; serialize it like a space list.
            ListSep.Space | ListSep.Undecided => " ",
            ListSep.Comma => {
                if (compressed) {
                    ","
                } else {
                    ", "
                }
            },
            ListSep.Slash => {
                if (compressed) {
                    "/"
                } else {
                    " / "
                }
            },
        };
        if (self.bracketed) {
            out.push("[");
        }
        // PORT: `.filter(..).enumerate()` → a loop that skips blanks and counts
        // the written elements.
        let i = 0;
        for (let v in self.items) {
            if (value_is_blank(v)) {
                continue;
            }
            if (i > 0) {
                out.push_str(sep);
            }
            v.write_css(out, compressed);
            i += 1;
        }
        if (self.bracketed) {
            out.push("]");
        }
    }

    function to_css(self, compressed: bool) -> string {
        let s = root.std.StrBuf.new();
        self.write_css(s, compressed);
        s.as_str()
    }

    function write_interp(self, out: root.std.StrBuf) -> void {
        let sep = match (self.sep) {
            ListSep.Space | ListSep.Undecided => " ",
            ListSep.Comma => ", ",
            ListSep.Slash => " / ",
        };
        if (self.bracketed) {
            out.push("[");
        }
        // PORT: `.filter(..).enumerate()` → a loop that skips blanks and counts
        // the written elements.
        let i = 0;
        for (let v in self.items) {
            if (value_is_blank(v)) {
                continue;
            }
            if (i > 0) {
                out.push_str(sep);
            }
            match (v) {
                // A string INSIDE a composite value serializes through dart's
                // quote-less serializer (`_visitUnquotedString`): its newlines
                // collapse to single spaces (issue_1786 `"#{a $str-with-lf}"`),
                // unlike a directly interpolated string's raw text.
                // Interpolation is serialized in the EXPANDED style in
                // dart-sass whatever the output style is (`_serialize` takes
                // the default), so a private-use character still escapes here.
                Value_Str { _0: let s } => push_unquoted(out, s.text, false),
                let other => other.write_interp(out),
            }
            i += 1;
        }
        if (self.bracketed) {
            out.push("]");
        }
    }

    function to_interp(self) -> string {
        let s = root.std.StrBuf.new();
        self.write_interp(s);
        s.as_str()
    }
}

/// A map value: an ordered list of key/value entries. Insertion order is
/// preserved (dart-sass maps are ordered); duplicate keys are resolved by the
/// constructor so at most one entry exists per Sass-equal key.
///
/// `entries` is held as `Rc<Vec<…>>` so cloning a `Value::Map` (e.g. on every
/// read-only `$var` lookup) is an O(1) refcount bump rather than a deep copy of
/// every entry. Maps are immutable Sass values; `Map::insert` and the mutating
/// map builtins (`map.merge`, `map.set`, `map.remove`, …) use copy-on-write
/// (`Rc::make_mut` on a uniquely-owned `Rc`, or build a fresh `Vec`), so the
/// sharing never lets one binding observe another's mutation.
class Map {
    entries: root.std.Tuple2<Value, Value>[],
    /// Construct a map from an owned entry vector.
    function new(entries: root.std.Tuple2<Value, Value>[]) -> Map {
        Map { entries: entries }
    }

    /// Look up a value by key (Sass `==`), or `None` when absent.
    function get(self, key: Value) -> Value? {
        let e = self.entries.find((e) -> {
            e._0.sass_eq(key)
        });
        if (e != null) {
            e._1
        } else {
            null
        }
    }

    /// Insert or overwrite an entry, preserving the position of an existing
    /// key (matching dart-sass map ordering). Copy-on-write: if the entry
    /// vector is shared, `Rc::make_mut` clones it first so no other `Map`
    /// observes the change.
    function insert(self, key: Value, value: Value) -> void {
        // PORT: `Rc::make_mut` → always copy the entry vector (BAML cannot tell
        // whether it is shared), and replace a matching slot's tuple instead of
        // mutating it (the copy shares its tuples with the original).
        let entries = root.std.clone_vec(self.entries);
        let slot = entries.find_index((e) -> {
            e._0.sass_eq(key)
        });
        if (slot != null) {
            entries[slot] = root.std.Tuple2 { _0: entries[slot]._0, _1: value };
        } else {
            entries.push(root.std.Tuple2 { _0: key, _1: value });
        }
        self.entries = entries;
    }

    /// Serialize the map for CSS / error messages: `(k1: v1, k2: v2)`, with
    /// the empty map rendered as `()`.
    function to_css(self, compressed: bool) -> string {
        self.to_map_css(compressed)
    }

    /// Serialize the map as dart-sass does: `(k1: v1, k2: v2)`, with the empty
    /// map rendered as `()`. Keys and values use their inspect form so nested
    /// quoted strings keep their quotes.
    function to_map_css(self, compressed: bool) -> string {
        if (self.entries.length() == 0) {
            return "()";
        }
        let sep = if (compressed) {
            ","
        } else {
            ", "
        };
        let pair_sep = if (compressed) {
            ":"
        } else {
            ": "
        };
        let inner = root.std.join(
            self.entries.map((e) -> {
                `${map_key_css(e._0)}${pair_sep}${map_val_css(e._1)}`
            }),
            sep,
        );
        `(${inner})`
    }
}

/// Serialize a map key (dart-sass uses the inspect form for keys/values).
function map_key_css(v: Value) -> string {
    match (v) {
        Value_Str { _0: let s } if s.quoted => serialize_quoted(s.text),
        Value_Map { _0: let m } => m.to_map_css(false),
        let other => other.to_css(false),
    }
}

/// Serialize a map value entry. A bare comma list inside a map is wrapped in
/// parentheses to disambiguate from the entry separators.
function map_val_css(v: Value) -> string {
    match (v) {
        Value_Str { _0: let s } if s.quoted => serialize_quoted(s.text),
        Value_Map { _0: let m } => m.to_map_css(false),
        Value_List { _0: let l }
            if l.sep == ListSep.Comma && !l.bracketed && l.items.length() >= 2 => {
            `(${l.to_css(false)})`
        },
        let other => other.to_css(false),
    }
}

/// List separator.
enum ListSep {
    /// Space-separated (`1px 2px`).
    Space,
    /// Comma-separated (`1px, 2px`).
    Comma,
    /// Slash-separated (`1px / 2px`), produced by `list.slash()`.
    Slash,
    /// Not yet decided: an empty or single-element list that has no explicit
    /// separator. It serializes like a space list but defers to the other
    /// operand's separator in `list.join`/`list.append`, and `list.separator`
    /// reports it as `space`. Only ever held by a list with fewer than two
    /// elements (two elements force a real separator).
    Undecided,
}

/// An sRGB color. Channels are `0..=255` and may be fractional; alpha is
/// `0..=1`.
///
/// A color may also carry a *modern* color-space representation in
/// [`Color::modern`]. When present, the color belongs to a non-legacy CSS
/// Color 4 space (or a legacy space stored in canonical units, e.g. `hsl`),
/// and serialization/channel access use that representation. The legacy
/// `r`/`g`/`b`/`a` fields still hold an sRGB-byte approximation so the large
/// body of legacy color builtins keep working unchanged.
class Color {
    r: float,
    g: float,
    b: float,
    a: float,
    /// The authored spelling (`"red"`, `"#336699"`). Used verbatim when
    /// the color is emitted unchanged; `None` for computed colors. SHARED
    /// (`Rc<str>`) because a color literal lives in the AST and is cloned out
    /// of it on every evaluation: the clone bumps a refcount instead of
    /// copying the handful of bytes into a fresh allocation. Nothing ever
    /// mutates a spelling in place — a color that changes gets a new spelling
    /// or none at all — so no holder needs to unshare it. The thin handle is
    /// also 8 bytes narrower than a `String`, which takes `Color` from 64
    /// down to 56 bytes — `Value` itself stays 64 for now, its width set by
    /// `Slash`'s own 56-byte payload.
    repr: string?,
    /// Modern CSS Color 4 representation. `None` for plain legacy sRGB
    /// colors (the common case); `Some` once the color is space-aware. BOXED so
    /// the 72-byte `ModernColor` doesn't inflate every `Color` (and thus every
    /// `Value`, since `Color` is the widest variant): inline it would DOUBLE
    /// `Value` to 128 bytes, and every scope slot / `Vec<Value>` element /
    /// lookup clone with it.
    modern: ModernColor?,
    function rgb(r: float, g: float, b: float, a: float) -> Color {
        Color {
            r: without_negative_zero(r),
            g: without_negative_zero(g),
            b: without_negative_zero(b),
            a: without_negative_zero(a),
            repr: null,
            modern: null,
        }
    }

    /// Parse the hex digits following a `#` (3/4/6/8 long). Returns `None`
    /// on an invalid length or digit.
    function from_hex(digits: string) -> Color? {
        // PORT: `u8::from_str_radix(s, 16).ok().map(|v| v as f64)` — an optional
        // leading `+`, then hex digits whose value fits a `u8`; `None` otherwise.
        let parse = (s: string) -> float? {
            let body = root.std.strip_prefix(s, "+") ?? s;
            if (body == "") {
                return null;
            }
            let v = 0;
            for (let c in body.chars()) {
                let d = root.std.to_digit(c, 16);
                if (d == null) {
                    return null;
                }
                v = v * 16 + d;
                if (v > 255) {
                    return null;
                }
            }
            v * 1.0
        };
        // PORT: each `parse(..)?` is an explicit early `return null`; the match is
        // on the BYTE length, as Rust's `digits.len()` is.
        let t: root.std.Tuple4<float, float, float, float> = match (digits.byte_length()) {
            3 => {
                let d = digits.chars();
                let r = parse(`${d[0]}${d[0]}`);
                if (r == null) {
                    return null;
                }
                let g = parse(`${d[1]}${d[1]}`);
                if (g == null) {
                    return null;
                }
                let b = parse(`${d[2]}${d[2]}`);
                if (b == null) {
                    return null;
                }
                root.std.Tuple4 { _0: r, _1: g, _2: b, _3: 255.0 }
            },
            4 => {
                let d = digits.chars();
                let r = parse(`${d[0]}${d[0]}`);
                if (r == null) {
                    return null;
                }
                let g = parse(`${d[1]}${d[1]}`);
                if (g == null) {
                    return null;
                }
                let b = parse(`${d[2]}${d[2]}`);
                if (b == null) {
                    return null;
                }
                let a = parse(`${d[3]}${d[3]}`);
                if (a == null) {
                    return null;
                }
                root.std.Tuple4 { _0: r, _1: g, _2: b, _3: a }
            },
            6 => {
                let r = parse(root.std.byte_slice(digits, 0, 2));
                if (r == null) {
                    return null;
                }
                let g = parse(root.std.byte_slice(digits, 2, 4));
                if (g == null) {
                    return null;
                }
                let b = parse(root.std.byte_slice(digits, 4, 6));
                if (b == null) {
                    return null;
                }
                root.std.Tuple4 { _0: r, _1: g, _2: b, _3: 255.0 }
            },
            8 => {
                let r = parse(root.std.byte_slice(digits, 0, 2));
                if (r == null) {
                    return null;
                }
                let g = parse(root.std.byte_slice(digits, 2, 4));
                if (g == null) {
                    return null;
                }
                let b = parse(root.std.byte_slice(digits, 4, 6));
                if (b == null) {
                    return null;
                }
                let a = parse(root.std.byte_slice(digits, 6, 8));
                if (a == null) {
                    return null;
                }
                root.std.Tuple4 { _0: r, _1: g, _2: b, _3: a }
            },
            _ => {
                return null;
            },
        };
        let r = t._0;
        let g = t._1;
        let b = t._2;
        let a = t._3 / 255.0;
        let opaque = (a - 1.0).abs() < root.std.F64_EPSILON();
        // dart-sass preserves the *authored* spelling of an opaque 3- or
        // 6-digit hex literal verbatim — `#fff` stays `#fff`, `#FFAA00` keeps
        // its uppercase. The alpha-channel forms (4/8 digits) are always
        // canonicalized: opaque ones round-trip as lowercase 6-digit hex
        // (`#abcf` -> `#aabbcc`), while partial-alpha ones fall back to a
        // computed `rgba()`.
        let repr: string? = if (opaque) {
            match (digits.byte_length()) {
                3 | 6 => hex_repr(digits.to_utf8()),
                _ => {
                    let HEX = "0123456789abcdef".to_utf8();
                    // PORT: `six` is filled in index order, so it is built by
                    // pushing onto an empty byte array.
                    let six = "".to_utf8();
                    for (let channel in [r, g, b]) {
                        let byte = root.std.f64_to_u8(channel.round());
                        six.push(HEX[byte >> 4]);
                        six.push(HEX[byte & 15]);
                    }
                    hex_repr(six)
                },
            }
        } else {
            null
        };
        Color { r: r, g: g, b: b, a: a, repr: repr, modern: null }
    }

    /// Convert to HSL: hue in degrees `[0,360)`, saturation/lightness in
    /// `[0,1]`.
    function to_hsl(self) -> root.std.Tuple3<float, float, float> {
        let r = self.r / 255.0;
        let g = self.g / 255.0;
        let b = self.b / 255.0;
        let max = root.std.fmax(root.std.fmax(r, g), b);
        let min = root.std.fmin(root.std.fmin(r, g), b);
        let l = (max + min) / 2.0;
        let d = max - min;
        let s = if (d == 0.0) {
            0.0
        } else {
            d / (1.0 - (2.0 * l - 1.0).abs())
        };
        let h = if (d == 0.0) {
            0.0
        } else if (max == r) {
            60.0 * root.std.f_rem_euclid((g - b) / d, 6.0)
        } else if (max == g) {
            60.0 * ((b - r) / d + 2.0)
        } else {
            60.0 * ((r - g) / d + 4.0)
        };
        root.std.Tuple3 { _0: root.std.f_rem_euclid(h, 360.0), _1: s, _2: l }
    }

    /// Build a color from HSL (hue degrees, sat/light `[0,1]`) + alpha.
    function from_hsl(h: float, s: float, l: float, a: float) -> Color {
        // The conversion below has no answer for a non-finite channel — it
        // would pick the fallback sector and hand back a NaN component — and
        // dart-sass 1.104.0 does not ask it to: a polar HUE converts every
        // non-finite value to 0, and a NaN elsewhere converts too. That is why
        // `adjust-hue(red, NaN)`, which rotates the hue by NaN, is still red.
        let h = if (h.is_finite()) {
            without_negative_zero(h)
        } else {
            0.0
        };
        let s = if (s.is_nan()) {
            0.0
        } else {
            s
        };
        let l = if (l.is_nan()) {
            0.0
        } else {
            l
        };
        let h = root.std.f_rem_euclid(h, 360.0);
        let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
        let x = c * (1.0 - ((h / 60.0 % 2.0) - 1.0).abs());
        let m = l - c / 2.0;
        let t = if (h < 60.0) {
            root.std.Tuple3 { _0: c, _1: x, _2: 0.0 }
        } else if (h < 120.0) {
            root.std.Tuple3 { _0: x, _1: c, _2: 0.0 }
        } else if (h < 180.0) {
            root.std.Tuple3 { _0: 0.0, _1: c, _2: x }
        } else if (h < 240.0) {
            root.std.Tuple3 { _0: 0.0, _1: x, _2: c }
        } else if (h < 300.0) {
            root.std.Tuple3 { _0: x, _1: 0.0, _2: c }
        } else {
            root.std.Tuple3 { _0: c, _1: 0.0, _2: x }
        };
        let r1 = t._0;
        let g1 = t._1;
        let b1 = t._2;
        Color.rgb((r1 + m) * 255.0, (g1 + m) * 255.0, (b1 + m) * 255.0, a)
    }

    /// dart `_canUseHex` (serialize.dart:860): every channel a FUZZY integer
    /// inside `[0, 256)`. The bound is part of the rule — an out-of-gamut
    /// channel has no two-digit hex spelling, and clamping one into range would
    /// print a different color — and `meta.inspect`, which does not reroute an
    /// out-of-gamut color through hsl, is where a color can reach here with
    /// one.
    function can_use_hex(self) -> bool {
        let ok = (v: float) -> bool {
            fuzzy_is_int(v) && (v > 0.0 || fuzzy_eq(v, 0.0)) && v < 256.0 && !fuzzy_eq(v, 256.0)
        };
        ok(self.r) && ok(self.g) && ok(self.b)
    }

    function to_css(self, compressed: bool) -> string {
        let s = root.std.StrBuf.new();
        self.write_css(s, compressed);
        s.as_str()
    }

    /// Serialize into `out`. A color is written where it belongs: the source
    /// spelling a literal keeps, a hex triple, and the `rgb()`/`rgba()` form all
    /// go straight into the caller's buffer, digits included.
    function write_css(self, out: root.std.StrBuf, compressed: bool) -> void {
        self.write_css_mode(out, compressed, false);
    }

    /// [`write_css`] with dart's `_inspect` flag, which changes one rule: a
    /// channel's integrality is tested fuzzily for `meta.inspect` and exactly
    /// for CSS output (see [`push_rgb_channels`]).
    function write_css_mode(self, out: root.std.StrBuf, compressed: bool, inspect: bool) -> void {
        if let m: ModernColor = self.modern {
            out.push_str(m.to_css_mode(compressed, inspect));
            return;
        }
        if (!compressed) {
            if let repr: string = self.repr {
                out.push_str(repr);
                return;
            }
        }
        let opaque = fuzzy_eq(self.a, 1.0);
        if (opaque && self.can_use_hex()) {
            let r = root.std.f64_to_u8(root.std.fclamp(self.r.round(), 0.0, 255.0));
            let g = root.std.f64_to_u8(root.std.fclamp(self.g.round(), 0.0, 255.0));
            let b = root.std.f64_to_u8(root.std.fclamp(self.b.round(), 0.0, 255.0));
            if (compressed) {
                // `#aabbcc` shortens to `#abc` when each channel's nibbles
                // match, so the shortest hex is four characters wide instead of
                // seven — the width a name has to beat, decided without either
                // spelling being built.
                let halvable = (v: int) -> bool {
                    (v >> 4) == (v & 15)
                };
                let hex_len = if (halvable(r) && halvable(g) && halvable(b)) {
                    4
                } else {
                    7
                };
                // dart-sass compressed: emit whichever is shorter, the shortest
                // hex or the color's canonical CSS name (name wins ties — e.g.
                // `aqua` == `#0ff`). `compressed_color_name` is the value-keyed
                // reverse table of exactly the names that are no longer than the
                // hex; absent => hex is shorter.
                if let name: string = compressed_color_name(r, g, b) {
                    if (name.length() <= hex_len) {
                        out.push_str(name);
                        return;
                    }
                }
                if (hex_len == 4) {
                    out.push("#");
                    for (let v in [r, g, b]) {
                        out.push(root.std.chr_unchecked(HEX_DIGITS()[v & 15]));
                    }
                    return;
                }
            }
            out.push("#");
            for (let v in [r, g, b]) {
                out.push(root.std.chr_unchecked(HEX_DIGITS()[v >> 4]));
                out.push(root.std.chr_unchecked(HEX_DIGITS()[v & 15]));
            }
            return;
        }
        // PORT: the rgb()/rgba() form is written into a scratch buffer `buf` (so
        // `start` is 0) and appended to `out` at the end: swapping it for the
        // shorter hsl form below then never truncates the (possibly long) output
        // buffer, which costs O(len) in BAML.
        let buf = root.std.StrBuf.new();
        let start = buf.len();
        let sep = if (compressed) {
            ","
        } else {
            ", "
        };
        buf.push_str(
            if (opaque) {
                "rgb("
            } else {
                "rgba("
            },
        );
        push_rgb_channels(buf, self.r, self.g, self.b, compressed, sep, inspect);
        if (!opaque) {
            buf.push_str(sep);
            push_num(buf, self.a, compressed);
        }
        buf.push(")");
        // dart-sass compressed output emits whichever legacy form is SHORTER:
        // the rgb()/rgba() form or the equivalent hsl()/hsla() form. A computed
        // color such as `darken(#336699, 10%)` -> `rgb(38.25,76.5,114.75)` is
        // therefore written as the shorter `hsl(210,50%,30%)`. Only an in-gamut
        // color has an exact legacy hsl equivalent; an out-of-gamut channel (or
        // any expanded output) keeps the rgb form. The hsl candidate is derived
        // FROM the rgb channels, so float noise can only lengthen it (never
        // shorten the rgb past it), keeping the choice safe.
        if (compressed) {
            let in_gamut = (v: float) -> bool {
                (v > 0.0 || fuzzy_eq(v, 0.0)) && (v < 255.0 || fuzzy_eq(v, 255.0))
            };
            if (in_gamut(self.r) && in_gamut(self.g) && in_gamut(self.b)) {
                // The candidate is built rather than written: it only replaces
                // what is already in `out` if it turns out to be shorter, and
                // compressed output is the one style where the comparison —
                // not the copy — is what costs.
                let hsl = root.builtins.colorspace.srgb_to_hsl(
                    [self.r / 255.0, self.g / 255.0, self.b / 255.0],
                );
                // dart nulls the hue when saturation is fuzzy-zero (srgb.dart:
                // `fuzzyEquals(saturation, 0) ? null : hue`), and a missing hue
                // serializes as 0 — float dust in a gray triple must not leak
                // a phantom hue. It is `fuzzyEquals` and not a bare epsilon: a
                // saturation of 6e-12 KEEPS its hue, which lengthens the hsl bid
                // past the rgb one. `[measured]`:
                // `color.change(hsl(90, 50%, 50%), $saturation: -0.000000000006%)`
                // compresses to `rgb(50%,50%,50%)`, not `hsl(0,0%,50%)`.
                let hue = if (fuzzy_eq(hsl[1], 0.0)) {
                    0.0
                } else {
                    hsl[0]
                };
                let hh = fmt_num(hue, true);
                let ss = fmt_num(hsl[1], true);
                let ll = fmt_num(hsl[2], true);
                let hsl_css = if (opaque) {
                    `hsl(${hh},${ss}%,${ll}%)`
                } else {
                    `hsla(${hh},${ss}%,${ll}%,${fmt_num(self.a, true)})`
                };
                // dart gives HSL a TWO-CHARACTER handicap
                // (serialize.dart:775, `rgbString.length <= hslString.length + 2`)
                // — its comment: "Add two characters for HSL for the %s on
                // saturation and lightness." So rgb wins ties AND wins when it is
                // up to two characters longer.
                if (buf.len() - start > hsl_css.length() + 2) {
                    buf.truncate(start);
                    buf.push_str(hsl_css);
                }
            }
        }
        out.push_str(buf.as_str());
    }

    /// The `inspect: true` serialization of this color.
    ///
    /// dart's `Value.toString()` is `serializeValue(this, inspect: true)`
    /// (lib/src/value.dart:439), so EVERY color interpolated into an error
    /// message (`"Color $color ..."`) renders with inspect semantics, not CSS
    /// output semantics. The two differ for a space-aware color: `hwb(200 20%
    /// 30%)` inspects as itself but writes as `hsl(200, 55.5555555556%, 45%)`.
    /// Delegates to `ModernColor::inspect_css` when the color is space-aware;
    /// a plain legacy sRGB color serializes identically either way.
    function inspect_css(self) -> string {
        match (self.modern) {
            let m: ModernColor => m.inspect_css(),
            _ => {
                let out = root.std.StrBuf.new();
                self.write_css_mode(out, false, true);
                out.as_str()
            },
        }
    }
}

/// A color CHANNEL never holds a negative zero: dart-sass 1.104.0 converts
/// one to `0` "as per the CSS spec", so `rgb(-0, 0, 0)` is `rgb(0, 0, 0)` and
/// `hsl(-0, …)` is `hsl(0, …)`. (A negative zero is otherwise preserved —
/// `math.div(0, -1)` is `-0` — so this is the color model's own rule, not the
/// number serializer's.)
function without_negative_zero(v: float) -> float {
    if (v == 0.0) {
        0.0
    } else {
        v
    }
}

/// A CSS Color 4 color space.
enum ColorSpace {
    Rgb,
    Hsl,
    Hwb,
    Srgb,
    SrgbLinear,
    DisplayP3,
    DisplayP3Linear,
    A98Rgb,
    ProphotoRgb,
    Rec2020,
    XyzD65,
    XyzD50,
    Lab,
    Lch,
    Oklab,
    Oklch,
}

interface ColorSpaceMethods {
    function name(self) -> string throws unknown;

    /// Whether this is a legacy space (`rgb`/`hsl`/`hwb`).
    function is_legacy(self) -> bool throws unknown;

    /// The three channel names for this space (in storage order).
    function channel_names(self) -> string[] throws unknown;
}

implements ColorSpaceMethods for ColorSpace {
    function name(self) -> string {
        match (self) {
            ColorSpace.Rgb => "rgb",
            ColorSpace.Hsl => "hsl",
            ColorSpace.Hwb => "hwb",
            ColorSpace.Srgb => "srgb",
            ColorSpace.SrgbLinear => "srgb-linear",
            ColorSpace.DisplayP3 => "display-p3",
            ColorSpace.DisplayP3Linear => "display-p3-linear",
            ColorSpace.A98Rgb => "a98-rgb",
            ColorSpace.ProphotoRgb => "prophoto-rgb",
            ColorSpace.Rec2020 => "rec2020",
            ColorSpace.XyzD65 => "xyz",
            ColorSpace.XyzD50 => "xyz-d50",
            ColorSpace.Lab => "lab",
            ColorSpace.Lch => "lch",
            ColorSpace.Oklab => "oklab",
            ColorSpace.Oklch => "oklch",
        }
    }

    /// Whether this is a legacy space (`rgb`/`hsl`/`hwb`).
    function is_legacy(self) -> bool {
        match (self) {
            ColorSpace.Rgb | ColorSpace.Hsl | ColorSpace.Hwb => true,
            _ => false,
        }
    }

    /// The three channel names for this space (in storage order).
    function channel_names(self) -> string[] {
        match (self) {
            ColorSpace.Rgb
            | ColorSpace.Srgb
            | ColorSpace.SrgbLinear
            | ColorSpace.DisplayP3
            | ColorSpace.DisplayP3Linear
            | ColorSpace.A98Rgb
            | ColorSpace.ProphotoRgb
            | ColorSpace.Rec2020 => ["red", "green", "blue"],
            ColorSpace.Hsl => ["hue", "saturation", "lightness"],
            ColorSpace.Hwb => ["hue", "whiteness", "blackness"],
            ColorSpace.XyzD65 | ColorSpace.XyzD50 => ["x", "y", "z"],
            ColorSpace.Lab | ColorSpace.Oklab => ["lightness", "a", "b"],
            ColorSpace.Lch | ColorSpace.Oklch => ["lightness", "chroma", "hue"],
        }
    }

}

function ColorSpace_from_name(s: string) -> ColorSpace? {
    // Color-space names are ASCII case-insensitive (`sRGB`, `Display-P3`,
    // `XYZ` all resolve); callers keep the original spelling for errors and
    // serialization always uses the canonical lower-case `name()`.
    match (root.std.ascii_lower(s)) {
        "rgb" => ColorSpace.Rgb,
        "hsl" => ColorSpace.Hsl,
        "hwb" => ColorSpace.Hwb,
        "srgb" => ColorSpace.Srgb,
        "srgb-linear" => ColorSpace.SrgbLinear,
        "display-p3" => ColorSpace.DisplayP3,
        "display-p3-linear" => ColorSpace.DisplayP3Linear,
        "a98-rgb" => ColorSpace.A98Rgb,
        "prophoto-rgb" => ColorSpace.ProphotoRgb,
        "rec2020" => ColorSpace.Rec2020,
        "xyz" | "xyz-d65" => ColorSpace.XyzD65,
        "xyz-d50" => ColorSpace.XyzD50,
        "lab" => ColorSpace.Lab,
        "lch" => ColorSpace.Lch,
        "oklab" => ColorSpace.Oklab,
        "oklch" => ColorSpace.Oklch,
        _ => {
            return null;
        },
    }
}

/// A color-space-aware color. Channels are stored in CSS Color 4 canonical
/// units (e.g. lab lightness `0..=100`, oklab lightness `0..=1`, hues in
/// degrees, rgb channels `0..=1`). A `None` channel is a missing channel.
class ModernColor {
    space: ColorSpace,
    channels: (float?)[],
    alpha: float?,
    /// Whether any of the three channels (or alpha) is a missing channel.
    function has_missing(self) -> bool {
        self.channels.some((c) -> {
            c == null
        })
            || self.alpha == null
    }

    function is_opaque(self) -> bool {
        match (self.alpha) {
            let a: float if fuzzy_eq(a, 1.0) => true,
            _ => false,
        }
    }

    /// Serialize a single channel, rendering a missing channel as `none`. A
    /// non-finite value (from a degenerate `calc()`, e.g. a lab a/b channel)
    /// serializes as a `calc()` constant like dart-sass (`calc(infinity)`).
    function chan(self, i: int, compressed: bool) -> string {
        match (self.channels[i]) {
            null => "none",
            let v: float if !v.is_finite() => Number.unitless(v).to_css(compressed),
            let v: float => fmt_num(v, compressed),
        }
    }

    /// Serialize a channel as a percentage of `denom` (e.g. lab lightness over
    /// 100, oklab lightness over 1). Missing → `none`; non-finite → a `%`-unit
    /// `calc()` constant (`calc(infinity * 1%)`).
    ///
    /// Compressed output drops the `%` of a *finite* channel and writes the
    /// channel's own stored value instead, which is the same number for lab/lch
    /// (0–100) but the unscaled one for oklab/oklch (0–1). A non-finite channel
    /// keeps its `%` in either style, because the unit is what makes the
    /// `calc()` constant a percentage. dart-sass writes the unit-less form
    /// unconditionally here rather than picking the shorter of the two:
    /// `[measured]` against dart-sass 1.104.1, `oklab(33.333333% .1 -0.1)`
    /// compresses to `oklab(.33333333 .1 -0.1)` — the same length — and
    /// `oklab(1% 0 0)` to `oklab(.01 0 0)`, which is longer.
    function chan_pct(self, i: int, denom: float, compressed: bool) -> string {
        match (self.channels[i]) {
            null => "none",
            let v: float if !v.is_finite() => Number.with_unit(v, "%").to_css(compressed),
            let v: float if compressed => fmt_num(v, true),
            let v: float => `${fmt_num(v / denom * 100.0, false)}%`,
        }
    }

    /// Serialize a hue channel with the `deg` suffix. Missing → `none`;
    /// non-finite → a `deg`-unit `calc()` constant (`calc(NaN * 1deg)`).
    ///
    /// Compressed output drops the `deg` of a *finite* hue: an unadorned number
    /// means degrees in every function that takes one, so the suffix is three
    /// bytes of nothing. This applies to the modern form of hsl/hwb as well as
    /// to lch/oklch. A non-finite hue keeps its `deg` in either style, since
    /// the unit is part of the `calc()` constant.
    function chan_hue(self, i: int, compressed: bool) -> string {
        match (self.channels[i]) {
            null => "none",
            let v: float if !v.is_finite() => Number.with_unit(v, "deg").to_css(compressed),
            let v: float if compressed => fmt_num(v, true),
            let v: float => `${fmt_num(v, false)}deg`,
        }
    }

    /// The trailing `/ alpha` (modern form) or `, alpha` (handled by caller).
    function alpha_str(self, compressed: bool) -> string {
        match (self.alpha) {
            null => "none",
            let a: float => fmt_num(a, compressed),
        }
    }

    /// Serialize with dart's `_inspect` flag, which the legacy writer needs:
    /// inspect output shows an out-of-gamut color in its own space and tests a
    /// channel's integrality fuzzily, CSS output does neither.
    function to_css_mode(self, compressed: bool, inspect: bool) -> string {
        // PORT: `use ColorSpace::*` — the variants are written `ColorSpace.X`.
        let sp = if (compressed) {
            ""
        } else {
            " "
        };
        // Legacy spaces with no missing channel use the comma legacy form.
        if (self.space.is_legacy() && !self.has_missing()) {
            return self.legacy_css(compressed, inspect);
        }
        // A lab/lch/oklab/oklch lightness outside [0, 100%] cannot round-trip
        // through the space's own function syntax (the CSS parser clamps it),
        // so dart-sass serializes the exact value via a `color-mix()` whose
        // first color is the unclamped xyz-d65 conversion. Only when no
        // channel is missing (a missing channel uses a different fallback,
        // relative color syntax, not exercised by the spec suite and left
        // as-is here). NaN lightness also fails the range check.
        if (
            self.space == ColorSpace.Lab
                || self.space == ColorSpace.Lch
                || self.space == ColorSpace.Oklab
                || self.space == ColorSpace.Oklch
        ) {
            // PORT: `if let (Some(l), Some(_), Some(_)) = (…)` as nested checks.
            if let l: float = self.channels[0] {
                if (self.channels[1] != null && self.channels[2] != null) {
                    let max = if (self.space == ColorSpace.Lab || self.space == ColorSpace.Lch) {
                        100.0
                    } else {
                        1.0
                    };
                    // dart fuzzy compare (epsilon 1e-11): in range iff above 0 and
                    // below max, or fuzzy-EQUAL to a bound. NaN fails everything.
                    let fuzzy_eq = (a: float, b: float) -> bool {
                        (a - b).abs() < 1e-11
                    };
                    let in_range = (l > 0.0 || fuzzy_eq(l, 0.0)) && (l < max || fuzzy_eq(l, max));
                    if (!in_range) {
                        return self.out_of_range_css(compressed);
                    }
                }
            }
        }
        match (self.space) {
            ColorSpace.Rgb | ColorSpace.Hsl | ColorSpace.Hwb => {
                // Legacy space with a missing channel: modern space-separated
                // form keeping the space's own name. rgb channels are plain;
                // hsl/hwb use hue+deg and percentages for the other two.
                let body = match (self.space) {
                    ColorSpace.Hsl => {
                        `${self.chan_hue(0, compressed)} ${self.pct_or_none(1, compressed)} ${self.pct_or_none(2, compressed)}`
                    },
                    ColorSpace.Hwb => {
                        `${self.chan_hue(0, compressed)} ${self.pct_or_none(1, compressed)} ${self.pct_or_none(2, compressed)}`
                    },
                    _ => {
                        `${self.chan(0, compressed)} ${self.chan(1, compressed)} ${self.chan(2, compressed)}`
                    },
                };
                self.wrap_modern(self.space.name(), body, compressed)
            },
            ColorSpace.Lab => {
                let body = `${self.chan_pct(0, 100.0, compressed)} ${self.chan(1, compressed)} ${self.chan(2, compressed)}`;
                self.wrap_modern("lab", body, compressed)
            },
            ColorSpace.Lch => {
                let body = `${self.chan_pct(0, 100.0, compressed)} ${self.chan(1, compressed)} ${self.chan_hue(2, compressed)}`;
                self.wrap_modern("lch", body, compressed)
            },
            ColorSpace.Oklab => {
                let body = `${self.chan_pct(0, 1.0, compressed)} ${self.chan(1, compressed)} ${self.chan(2, compressed)}`;
                self.wrap_modern("oklab", body, compressed)
            },
            ColorSpace.Oklch => {
                let body = `${self.chan_pct(0, 1.0, compressed)} ${self.chan(1, compressed)} ${self.chan_hue(2, compressed)}`;
                self.wrap_modern("oklch", body, compressed)
            },
            // Predefined color() spaces. The space name and the three channels
            // are separated by MANDATORY whitespace — `color(display-p3 .5 .2
            // .9)` is one identifier followed by three numbers, so dropping
            // those spaces when compressed produced `color(display-p3.5.2.9)`,
            // which is not a color at all. Only the `/` before the alpha may
            // lose its spaces, so `sp` applies there and nowhere else.
            _ => {
                let space = self.space.name();
                let c0 = self.chan(0, compressed);
                let c1 = self.chan(1, compressed);
                let c2 = self.chan(2, compressed);
                if (self.is_opaque()) {
                    `color(${space} ${c0} ${c1} ${c2})`
                } else {
                    `color(${space} ${c0} ${c1} ${c2}${sp}/${sp}${self.alpha_str(compressed)})`
                }
            },
        }
    }

    /// The `meta.inspect`/`@debug` serialization (dart `_writeLegacyColor`
    /// with `inspect: true`): an hwb color with no missing channels prints
    /// its own `hwb(H W% B%[ / A])` form (hue without `deg`), and an
    /// out-of-gamut legacy rgb skips the hsl reroute, falling to the
    /// `rgb(...)` comma form (named/hex only apply in-gamut) written with the
    /// same channel rules CSS output uses. Everything else serializes exactly
    /// like CSS output.
    function inspect_css(self) -> string {
        // dart writes an hwb color as `hwb()` in inspect output and through
        // its sRGB form in CSS output (`_writeLegacyColor`: the `_inspect &&
        // color.space == .hwb` branch comes before the format and hex rules).
        if (self.space == ColorSpace.Hwb && !self.has_missing()) {
            let a = self.alpha ?? 0.0;
            let opaque = fuzzy_eq(a, 1.0);
            let h = fmt_num(self.channels[0] ?? 0.0, false);
            let w = fmt_num(self.channels[1] ?? 0.0, false);
            let b = fmt_num(self.channels[2] ?? 0.0, false);
            return if (opaque) {
                `hwb(${h} ${w}% ${b}%)`
            } else {
                `hwb(${h} ${w}% ${b}% / ${fmt_num(a, false)})`
            };
        }
        // Everything else — including an OUT-OF-GAMUT legacy rgb color, which
        // inspect output shows as `rgb()` rather than rerouting through hsl —
        // goes through the shared writer in inspect mode.
        self.to_css_mode(false, true)
    }

    /// Serialize an out-of-range lab/lch/oklab/oklch color as
    /// `color-mix(in <space>, color(xyz <x> <y> <z>[ / <alpha>]) 100%, black)`
    /// (dart-sass's fallback for a lightness the own-space syntax would clamp).
    /// Compressed form per dart: no space after commas or before `100%`, and
    /// the irrelevant base color is the shorter `red`:
    /// `color-mix(in lab,color(xyz x y z[/a])100%,red)`. A `none` alpha
    /// converts to `0` in this form.
    function out_of_range_css(self, compressed: bool) -> string {
        let xyz = root.builtins.color.math.convert_modern(self, ColorSpace.XyzD65);
        let x = xyz.chan(0, compressed);
        let y = xyz.chan(1, compressed);
        let z = xyz.chan(2, compressed);
        let alpha = self.alpha ?? 0.0;
        let opaque = self.alpha != null && fuzzy_eq(alpha, 1.0);
        let inner = if (opaque) {
            `color(xyz ${x} ${y} ${z})`
        } else if (compressed) {
            `color(xyz ${x} ${y} ${z}/${fmt_num(alpha, true)})`
        } else {
            `color(xyz ${x} ${y} ${z} / ${fmt_num(alpha, false)})`
        };
        let space = self.space.name();
        if (compressed) {
            `color-mix(in ${space},${inner}100%,red)`
        } else {
            `color-mix(in ${space}, ${inner} 100%, black)`
        }
    }

    /// A non-hue percentage channel for the legacy modern form (saturation,
    /// lightness, whiteness, blackness).
    function pct_or_none(self, i: int, compressed: bool) -> string {
        match (self.channels[i]) {
            null => "none",
            let v: float => `${fmt_num(v, compressed)}%`,
        }
    }

    /// Wrap a function-form modern color (`lab(...)`, `hsl(none ...)`) adding a
    /// `/ alpha` when not opaque.
    function wrap_modern(self, name: string, body: string, compressed: bool) -> string {
        let sp = if (compressed) {
            ""
        } else {
            " "
        };
        if (self.is_opaque() && self.alpha != null) {
            `${name}(${body})`
        } else {
            `${name}(${body}${sp}/${sp}${self.alpha_str(compressed)})`
        }
    }

    /// Serialize a legacy color (rgb/hsl/hwb) with no missing channels in the
    /// classic comma form. rgb may collapse to hex; hwb routes through hsl.
    function legacy_css(self, compressed: bool, inspect: bool) -> string {
        let a = self.alpha ?? 1.0;
        // dart `_writeLegacyColor` opens with `fuzzyEquals(color.alpha, 1)`, so
        // an alpha 1e-13 short of 1 is opaque. `[measured]`:
        // `color.change(red, $alpha: 0.9999999999999)` is `red`, not
        // `rgba(255, 0, 0, 1)` — which is what a stricter test writes, alpha
        // and all.
        let opaque = fuzzy_eq(a, 1.0);
        // dart `_writeLegacyColor` (serialize.dart:753) opens with this rule:
        // an out-of-gamut color is written as hsl(), the one legacy form a
        // browser does not clamp at parse time. INSPECT output skips the
        // reroute and shows the color in its own space.
        if (!inspect && !self.is_in_gamut()) {
            let hsl = self.legacy_hsl_triple();
            let h = hsl._0;
            let s = hsl._1;
            let l = hsl._2;
            return self.hsl_comma_css(h, s, l, a, opaque, compressed);
        }
        match (self.space) {
            ColorSpace.Rgb => {
                let out = root.std.StrBuf.new();
                let c = Color {
                    r: self.channels[0] ?? 0.0,
                    g: self.channels[1] ?? 0.0,
                    b: self.channels[2] ?? 0.0,
                    a: a,
                    repr: null,
                    modern: null,
                };
                c.write_css_mode(out, compressed, inspect);
                out.as_str()
            },
            ColorSpace.Hsl => {
                let hsl = self.legacy_hsl_triple();
                let h = hsl._0;
                let s = hsl._1;
                let l = hsl._2;
                // Compressed output serializes through the rgb representation
                // (dart `_writeLegacyColor`, serialize.dart: `color.toSpace(.rgb)`
                // then hex/named, else the shorter of the rgb form and the hsl
                // form DERIVED from that rgb) — the stored hsl triple doesn't
                // participate, so a powerless authored hue collapses to the
                // round-trip's 0. The conversion is the engine's `hsl_to_srgb`,
                // dart's `HslColorSpace.convert` to the last bit, because the
                // rgb spelling turns on whether a channel is EXACTLY integral
                // and this conversion is where the dust that decides it comes
                // from.
                if (compressed) {
                    let srgb = root.builtins.colorspace.hsl_to_srgb([h, s, l]);
                    return Color.rgb(srgb[0] * 255.0, srgb[1] * 255.0, srgb[2] * 255.0, a).to_css(true);
                }
                self.hsl_comma_css(h, s, l, a, opaque, compressed)
            },
            ColorSpace.Hwb => {
                // hwb serializes through its sRGB representation: a hex-able
                // rgb becomes hex/named; otherwise the classic hsl comma form.
                let t = self.hwb_rgb_and_hsl();
                let rgb = t._0;
                let h = t._1;
                let s = t._2;
                let l = t._3;
                let shadow = Color.rgb(rgb[0], rgb[1], rgb[2], a);
                // Compressed hwb serializes through rgb like every legacy space
                // (dart `_writeLegacyColor`): hex/named/rgb()/derived-hsl,
                // whichever is shortest — rgba() included for a non-opaque
                // color.
                if (compressed) {
                    return shadow.to_css(true);
                }
                // Expanded: only a fully-OPAQUE hex-able hwb collapses to a
                // named color or hex; a non-opaque hwb uses the hsl comma form
                // (dart-sass never emits rgba() for an hwb color in expanded).
                if (opaque && shadow.can_use_hex()) {
                    if let name: string = rgb_name(rgb[0], rgb[1], rgb[2]) {
                        return name;
                    }
                    let out = root.std.StrBuf.new();
                    shadow.write_css_mode(out, false, inspect);
                    return out.as_str();
                }
                self.hsl_comma_css(h, s, l, a, opaque, compressed)
            },
            _ => "",
        }
    }

    /// dart `SassColor.isInGamut` (color.dart:201) for the legacy spaces: every
    /// LINEAR channel inside ITS OWN bounds, fuzzily; a polar hue is always in
    /// gamut.
    ///
    /// The bounds are the space's own, not sRGB's, and that is the whole point:
    /// `color.to-space(oklch(0.5 0.2 200), hsl)` carries a saturation of
    /// 6051.64% over an rgb conversion that is ordinary black, so testing the
    /// conversion calls it in gamut where dart calls it out. `[measured]`
    /// against dart-sass 1.104.1, compressed:
    /// `hsl(221.7487198664,266.6061126985%,0%)`, not `#000`.
    function is_in_gamut(self) -> bool {
        // dart `_isChannelInGamut`: `fuzzyGreaterThanOrEquals(v, min) &&
        // fuzzyLessThanOrEquals(v, max)`. A missing channel is in gamut, and
        // NaN fails both comparisons — which is how a color with an infinite
        // (or NaN) lightness keeps its hsl form in either style.
        let inside = (v: float?, max: float) -> bool {
            match (v) {
                null => true,
                let v: float => (v > 0.0 || fuzzy_eq(v, 0.0)) && (v < max || fuzzy_eq(v, max)),
            }
        };
        match (self.space) {
            ColorSpace.Rgb => {
                inside(self.channels[0], 255.0)
                    && inside(self.channels[1], 255.0)
                    && inside(self.channels[2], 255.0)
            },
            // hue is polar: only saturation/lightness and whiteness/blackness
            // are bounded, each to [0, 100].
            ColorSpace.Hsl | ColorSpace.Hwb => {
                inside(self.channels[1], 100.0) && inside(self.channels[2], 100.0)
            },
            // Only the legacy spaces reach the legacy writer.
            _ => true,
        }
    }

    /// Serialize the classic `hsl(h, s%, l%)` / `hsla(…)` comma form.
    function hsl_comma_css(
        self,
        h: float,
        s: float,
        l: float,
        a: float,
        opaque: bool,
        compressed: bool,
    ) -> string {
        // dart-sass normalizes a negative HSL saturation — which arises when an
        // out-of-range hwb color converts to hsl — by flipping the hue 180° and
        // taking the saturation's magnitude. A non-negative saturation (every
        // normal color) is untouched.
        let hs = if (s < 0.0) {
            root.std.Tuple2 { _0: root.std.f_rem_euclid(h + 180.0, 360.0), _1: -s }
        } else {
            root.std.Tuple2 { _0: h, _1: s }
        };
        let h = hs._0;
        let s = hs._1;
        // Writing this triple builds an hsl color, so dart-sass 1.104.0's
        // channel conversion applies: a NaN becomes 0. That is how an hwb color
        // with an infinite whiteness — which the hwb -> hsl conversion sends to
        // NaN — serializes as `hsl(0, 0%, 0%)`.
        let nan_zero = (v: float) -> float {
            if (v.is_nan()) {
                0.0
            } else {
                v
            }
        };
        let h = nan_zero(h);
        let s = nan_zero(s);
        let l = nan_zero(l);
        // An INFINITE channel survives that conversion and serializes in its
        // calc form: `calc(infinity)` for the hue, `calc(infinity * 1%)` for a
        // percentage.
        let hh = if (h.is_finite()) {
            fmt_num(h, compressed)
        } else {
            Number.unitless(h).to_css(compressed)
        };
        let pct = (v: float) -> string {
            if (v.is_finite()) {
                `${fmt_num(v, compressed)}%`
            } else {
                Number.with_unit(v, "%").to_css(compressed)
            }
        };
        let ss = pct(s);
        let ll = pct(l);
        let comma = if (compressed) {
            ","
        } else {
            ", "
        };
        if (opaque) {
            `hsl(${hh}${comma}${ss}${comma}${ll})`
        } else {
            let aa = fmt_num(a, compressed);
            `hsla(${hh}${comma}${ss}${comma}${ll}${comma}${aa})`
        }
    }

    /// The sRGB-byte triple and the (hue, sat%, light%) for an hwb color,
    /// via the engine's exact dart conversions. A fuzzy-zero saturation makes
    /// the hue powerless; the legacy fill renders it as 0.
    function hwb_rgb_and_hsl(self) -> root.std.Tuple4<float[], float, float, float> {
        let hwb = [self.channels[0] ?? 0.0, self.channels[1] ?? 0.0, self.channels[2] ?? 0.0];
        let rgb01 = root.builtins.colorspace.hwb_to_srgb(hwb);
        let hsl = root.builtins.colorspace.srgb_to_hsl(rgb01);
        let hue = if (hsl[1].abs() < 1e-11) {
            0.0
        } else {
            hsl[0]
        };
        root.std.Tuple4 {
            _0: [rgb01[0] * 255.0, rgb01[1] * 255.0, rgb01[2] * 255.0],
            _1: hue,
            _2: hsl[1],
            _3: hsl[2],
        }
    }

    /// The (hue, saturation%, lightness%) triple a legacy color writes as
    /// `hsl()`. An hsl color writes its own channels (dart's `toSpace(.hsl)` is
    /// the identity, so a powerless hue survives); rgb and hwb convert through
    /// sRGB.
    function legacy_hsl_triple(self) -> root.std.Tuple3<float, float, float> {
        match (self.space) {
            ColorSpace.Hsl => {
                root.std.Tuple3 {
                    _0: self.channels[0] ?? 0.0,
                    _1: self.channels[1] ?? 0.0,
                    _2: self.channels[2] ?? 0.0,
                }
            },
            ColorSpace.Rgb => {
                let hsl = root.builtins.colorspace.srgb_to_hsl(
                    [
                        (self.channels[0] ?? 0.0) / 255.0,
                        (self.channels[1] ?? 0.0) / 255.0,
                        (self.channels[2] ?? 0.0) / 255.0,
                    ],
                );
                // dart's srgb -> hsl conversion hands back a MISSING hue when
                // the saturation is fuzzy-zero, and a missing hue writes as 0,
                // so an out-of-gamut gray must not leak a phantom hue.
                // `[measured]` against dart-sass 1.104.1:
                // `color.to-space(color(srgb 2 0 0.5), rgb)` is
                // `hsl(0, 0%, 100%)`, not `hsl(345, 0%, 100%)`.
                let hue = if (hsl[1].abs() < 1e-11) {
                    0.0
                } else {
                    hsl[0]
                };
                root.std.Tuple3 { _0: hue, _1: hsl[1], _2: hsl[2] }
            },
            ColorSpace.Hwb => {
                // Share the hwb->hsl conversion (and its achromatic-hue
                // canonicalization) with hwb_rgb_and_hsl.
                let t = self.hwb_rgb_and_hsl();
                let h = t._1;
                let s = t._2;
                let l = t._3;
                root.std.Tuple3 { _0: h, _1: s, _2: l }
            },
            _ => root.std.Tuple3 { _0: 0.0, _1: 0.0, _2: 0.0 },
        }
    }
}

/// dart-sass's numeric tolerance for `==` comparisons. Two finite numbers are
/// equal when their difference is below this epsilon (so `1in == 96px` and a
/// color channel like `127.99999999999861` equals `128`), mirroring
/// dart-sass's `fuzzyEquals`.
function FUZZY_EPSILON() -> float {
    1e-11
}

/// `1 / FUZZY_EPSILON`, the scale dart-sass's `fuzzyEquals` rounds at.
function INVERSE_FUZZY_EPSILON() -> float {
    1e11
}

/// dart-sass `fuzzyEquals`: exact equality (so `Infinity == Infinity`), or a
/// difference within [`FUZZY_EPSILON`] **and** the same value after scaling
/// both sides by 1e11 and rounding. `NaN` is never equal to anything (matching
/// dart-sass and IEEE semantics).
///
/// The second clause is load-bearing, and it is the whole comparison, not an
/// optimization of the first: 19.999999999994987 is within the epsilon of 20
/// yet scaling disagrees (1999999999999 against 2000000000000), so dart calls
/// it unequal. Every classification built on this — is a channel an integer, is
/// a color in gamut, does a triple match a named color — inherits that, and
/// dart's `namesByColor` lookup inherits it through `fuzzyHashCode`, which is
/// the SAME rounding. `[measured]` against dart-sass 1.104.1:
/// `meta.inspect(color.to-space(hsl(210, 50%, 7.8431372549%), rgb))` is
/// `rgba(3.9215686274500006%, 7.843137254899995%, 11.764705882349999%, 0.4)`,
/// not `rgba(10, 20, 30, 0.4)`.
function fuzzy_eq(a: float, b: float) -> bool {
    // PORT: BAML's float `==` is total (`NaN == NaN`), Rust's is IEEE; the
    // `!a.is_nan()` keeps a NaN operand unequal to everything.
    (a == b && !a.is_nan())
        || (
            (a - b).abs() <= FUZZY_EPSILON()
                && (a * INVERSE_FUZZY_EPSILON()).round() == (b * INVERSE_FUZZY_EPSILON()).round()
        )
}

/// dart-sass `fuzzyIsInt`: whether a value is [`fuzzy_eq`] to its own rounding.
function fuzzy_is_int(v: float) -> bool {
    v.is_finite() && fuzzy_eq(v, v.round())
}

/// Sass `==` for two colors (dart-sass). Legacy colors with no missing channel
/// compare by their sRGB bytes, so they're space-agnostic
/// (`rgb(255 0 0) == hsl(0 100% 50%)`). Otherwise — a non-legacy space on either
/// side, or any missing (`none`) channel — they must share a color space and
/// have channel-by-channel equal (and equally-missing) channels and alpha.
function color_sass_eq(a: Color, b: Color) -> bool {
    let space = (c: Color) -> ColorSpace {
        let m = c.modern;
        if (m != null) {
            m.space
        } else {
            ColorSpace.Rgb
        }
    };
    let chan_eq = (x: float?, y: float?) -> bool {
        // PORT: `match (x, y)` → nested `if`s.
        if (x != null) {
            if (y != null) {
                fuzzy_eq(x, y)
            } else {
                false
            }
        } else {
            y == null
        }
    };
    // An untagged color is a plain legacy rgb with no missing channel.
    let channels = (c: Color) -> (float?)[] {
        let m = c.modern;
        if (m != null) {
            m.channels
        } else {
            let legacy: (float?)[] = [c.r, c.g, c.b];
            legacy
        }
    };
    let alpha = (c: Color) -> float? {
        let m = c.modern;
        if (m != null) {
            m.alpha
        } else {
            c.a
        }
    };
    let sa = space(a);
    let sb = space(b);
    if (sa != sb) {
        // Different spaces are equal only when BOTH are legacy, compared via
        // their sRGB bytes (with `none` resolved); a non-legacy space never
        // equals a different space.
        if (sa.is_legacy() && sb.is_legacy()) {
            return fuzzy_eq(a.r, b.r) && fuzzy_eq(a.g, b.g) && fuzzy_eq(a.b, b.b) && fuzzy_eq(a.a, b.a);
        }
        return false;
    }
    // Same space: compare channel-by-channel, where a missing (`none`) channel
    // equals only another missing channel.
    let ca = channels(a);
    let cb = channels(b);
    root.std.range(0, 3).every((i) -> {
        chan_eq(ca[i], cb[i])
    })
        && chan_eq(alpha(a), alpha(b))
}

/// Sass `==` for two numbers. Numbers with the *exact* same unit compare by
/// value; numbers with different but convertible units compare after
/// converting `b` into `a`'s unit (so `1in == 96px`, `100grad == 90deg`).
/// Units are case-sensitive in `==` (dart-sass: `1PX != 1px`), so conversion
/// only applies to canonical lowercase units. Unitless vs unit-bearing, or
/// incompatible units, are never equal. Value comparisons are fuzzy
/// ([`fuzzy_eq`]).
function numbers_eq(a: Number, b: Number) -> bool {
    if (a.unit() == b.unit()) {
        return fuzzy_eq(a.value, b.value);
    }
    // A unitless number is only equal to another unitless number; a differing
    // unit (handled above) is the only remaining same-emptiness case.
    if (a.is_unitless() || b.is_unitless()) {
        return false;
    }
    // Conversion is keyed on canonical lowercase units, matching dart-sass's
    // unit table; an authored uppercase unit (`IN`) is treated as unknown and
    // never converts.
    if (
        a.unit().chars().some((c) -> {
            c.is_ascii_uppercase()
        })
            || b.unit().chars().some((c) -> {
                c.is_ascii_uppercase()
            })
    ) {
        return false;
    }
    match (convert_factor(b.unit(), a.unit())) {
        let factor: float => fuzzy_eq(a.value, b.value * factor),
        null => false,
    }
}

/// Append a unit with dart's `_writeIdentifier` escaping: a control
/// character (a decoded `1\9` IE hack) re-serializes as a hex escape with
/// its terminating space (`1\9 `); ordinary units append verbatim.
function push_unit_escaped(out: root.std.StrBuf, unit: string) -> void {
    if (
        unit.chars().every((c) -> {
            root.std.ord(c) >= 0x20 && root.std.ord(c) != 0x7F
        })
    ) {
        out.push_str(unit);
        return;
    }
    for (let c in unit.chars()) {
        let cu = root.std.ord(c);
        if (cu < 0x20 || cu == 0x7F) {
            out.push("\\");
            out.push_str(root.std.hex_lower(cu));
            out.push(" ");
        } else {
            out.push(c);
        }
    }
}

/// The conversion factor used when a numerator unit cancels a denominator
/// unit: identical names (exact strings, like dart) cancel exactly (covering
/// unknown units like `foo/foo`), and units in the same dimension convert.
function cancel_factor(numerator: string, denominator: string) -> float? {
    if (numerator == denominator) {
        return 1.0;
    }
    convert_factor(numerator, denominator)
}

/// The factor converting a value with `from` unit lists into `to` unit lists,
/// or `None` when they are incompatible. Each `from` numerator must match a
/// distinct convertible `to` numerator (any order), and likewise for the
/// denominators (a denominator's factor divides). Mirrors dart-sass's
/// `coerce`/`convertValue` for multi-unit numbers.
function unit_lists_factor(
    from: root.std.Tuple2<string[], string[]>,
    to: root.std.Tuple2<string[], string[]>,
) -> float? {
    let numer = unit_lists_factor__match_lists(from._0, to._0);
    if (numer == null) {
        return null;
    }
    let denom = unit_lists_factor__match_lists(from._1, to._1);
    if (denom == null) {
        return null;
    }
    numer / denom
}

/// `unit_lists_factor::match_lists` (nested fn, hoisted).
function unit_lists_factor__match_lists(from: string[], to: string[]) -> float? {
    if (from.length() != to.length()) {
        return null;
    }
    let factor = 1.0;
    let remaining: string[] = root.std.clone_vec(to);
    for (let f in from) {
        let i = remaining.find_index((t) -> {
            cancel_factor(f, t) != null
        });
        if (i == null) {
            return null;
        }
        let fac = cancel_factor(f, remaining[i]);
        if (fac != null) {
            factor *= fac;
        }
        let _ = remaining.remove_at(i);
    }
    factor
}

/// dart-sass `multiplyUnits`: combine two numbers' unit lists, cancelling
/// each numerator against the first convertible denominator of the OTHER
/// operand (the value picks up the conversion factor — `1s` cancelling a
/// `/ms` denominator scales by 1000), and concatenating what remains.
function multiply_units(
    value: float,
    numer1: string[],
    denom1: string[],
    numer2: string[],
    denom2: string[],
) -> Number {
    let numer: string[] = [];
    let denom2 = denom2;
    for (let n in numer1) {
        match (
            denom2.find_index((d) -> {
                cancel_factor(n, d) != null
            })
        ) {
            let i: int => {
                let factor = cancel_factor(n, denom2[i]);
                if (factor != null) {
                    value *= factor;
                }
                let _ = denom2.remove_at(i);
            },
            null => numer.push(n),
        }
    }
    let denom1 = denom1;
    for (let n in numer2) {
        match (
            denom1.find_index((d) -> {
                cancel_factor(n, d) != null
            })
        ) {
            let i: int => {
                let factor = cancel_factor(n, denom1[i]);
                if (factor != null) {
                    value *= factor;
                }
                let _ = denom1.remove_at(i);
            },
            null => numer.push(n),
        }
    }
    root.std.extend(denom1, denom2);
    Number.with_units(value, numer, denom1)
}

/// A CSS dimension group whose units can be converted into one another.
///
/// Units in the same group are mutually convertible via [`convert_factor`];
/// units in different groups (or unknown units, `%`, etc.) are incompatible.
///
/// Note: dart-sass does NOT treat the frequency units `hz`/`khz` as
/// convertible in arithmetic (`1khz + 500hz` is an error), so frequency is
/// deliberately omitted here to match its behaviour byte-for-byte.
enum Dim {
    Length,
    Angle,
    Time,
    Frequency,
    Resolution,
}

/// The CONVERTIBLE dimension group a unit belongs to, or `None` for `%`, an
/// unknown unit, or a unitless number. dart-sass's conversion table matches
/// unit names case-SENSITIVELY (`1in + 1q` converts but `1in + 1Q` errors,
/// `PX` never converts to `px`), even though calc-class *classification* is
/// case-insensitive (see `known_calc_class`).
function unit_dimension(unit: string) -> Dim? {
    match (unit) {
        "px" | "in" | "cm" | "mm" | "q" | "pt" | "pc" => Dim.Length,
        "deg" | "grad" | "rad" | "turn" => Dim.Angle,
        "s" | "ms" => Dim.Time,
        "Hz" | "kHz" => Dim.Frequency,
        "dpi" | "dpcm" | "dppx" => Dim.Resolution,
        _ => null,
    }
}

/// The canonical factor for a unit: a value of `1<unit>` equals
/// `canonical_factor(unit)` canonical units of its group. `None` for any
/// unit not in a convertible dimension group.
///
/// Canonical bases (verified against dart-sass):
/// length → px, angle → deg, time → s, frequency → Hz, resolution → dpi.
/// Lookups are case-sensitive like dart's conversion table.
function canonical_factor(unit: string) -> float? {
    let PI = root.std.F64_PI();
    match (unit) {
        // length (canonical: px)
        "px" => 1.0,
        "in" => 96.0,
        "cm" => 96.0 / 2.54,
        "mm" => 96.0 / 25.4,
        "q" => 96.0 / 101.6,
        "pt" => 96.0 / 72.0,
        "pc" => 16.0,
        // angle (canonical: deg)
        "deg" => 1.0,
        "grad" => 9.0 / 10.0,
        "rad" => 180.0 / PI,
        "turn" => 360.0,
        // time (canonical: s)
        "s" => 1.0,
        "ms" => 1.0 / 1000.0,
        // frequency (canonical: Hz)
        "Hz" => 1.0,
        "kHz" => 1000.0,
        // resolution (canonical: dpi)
        "dpi" => 1.0,
        "dpcm" => 2.54,
        "dppx" => 96.0,
        _ => {
            return null;
        },
    }
}

/// The multiplier to convert a value in `from` units to `to` units
/// (`value_in_to = value_in_from * convert_factor(from, to)`). Returns
/// `None` when the two units are not in the same convertible group.
function convert_factor(from: string, to: string) -> float? {
    if (!units_compatible(from, to)) {
        return null;
    }
    let f = canonical_factor(from);
    if (f == null) {
        return null;
    }
    let t = canonical_factor(to);
    if (t == null) {
        return null;
    }
    f / t
}

/// Whether two units can be combined in arithmetic. Identical units (exact
/// strings — dart treats `PX` and `px` as DIFFERENT units) are always
/// compatible; otherwise both must share a convertible dimension group. An
/// empty unit (unitless) is handled by the caller, not here — this is the
/// strict "two real units" test, mirroring dart-sass's `isComparableTo`.
function units_compatible(a: string, b: string) -> bool {
    if (a == b) {
        return true;
    }
    // PORT: `match (unit_dimension(a), unit_dimension(b))` → an `if`.
    let da = unit_dimension(a);
    let db = unit_dimension(b);
    if (da != null && db != null) {
        da == db
    } else {
        false
    }
}

/// A relative CSS length unit (`em`, `vw`, `ch`, …). dart-sass knows these are
/// *lengths* (so `calc(1ch + 1deg)` is a cross-dimension error) even though
/// they are not convertible to absolute lengths (so `calc(1px + 1vw)` is
/// preserved). The list mirrors dart-sass's font/viewport/container relative
/// length units; `%` and `fr` are NOT lengths (they preserve against
/// everything), and unknown units stay unknown.
function is_relative_length(unit: string) -> bool {
    match (root.std.ascii_lower(unit)) {
        // font-relative
        "em"
            | "rem"
            | "ex"
            | "rex"
            | "cap"
            | "rcap"
            | "ch"
            | "rch"
            | "ic"
            | "ric"
            | "lh"
            | "rlh"
            // viewport-relative
            | "vw"
            | "svw"
            | "lvw"
            | "dvw"
            | "vh"
            | "svh"
            | "lvh"
            | "dvh"
            | "vi"
            | "svi"
            | "lvi"
            | "dvi"
            | "vb"
            | "svb"
            | "lvb"
            | "dvb"
            | "vmin"
            | "svmin"
            | "lvmin"
            | "dvmin"
            | "vmax"
            | "svmax"
            | "lvmax"
            | "dvmax"
            // container-relative
            | "cqw"
            | "cqh"
            | "cqi"
            | "cqb"
            | "cqmin"
            | "cqmax" =>
        {
            true
        },
        _ => false,
    }
}

/// The broad class a unit belongs to for `calc()` compatibility decisions.
/// Unlike [`Dim`] (the *convertible*, case-sensitive groups), classification
/// is case-INSENSITIVE (`calc(1PX + 1s)` and `calc(1Q + 1s)` error
/// cross-class even though `PX`/`Q` never convert) and includes the relative
/// length units. Returns `None` for `%`, `fr`, and genuinely unknown units,
/// which `calc()` preserves verbatim rather than rejecting.
function known_calc_class(unit: string) -> int? {
    if (is_relative_length(unit)) {
        return 0; // length class (relative, not convertible)
    }
    match (root.std.ascii_lower(unit)) {
        "px" | "in" | "cm" | "mm" | "q" | "pt" | "pc" => 0,
        "deg" | "grad" | "rad" | "turn" => 1,
        "s" | "ms" => 2,
        "dpi" | "dpcm" | "dppx" => 3,
        "hz" | "khz" => 4,
        _ => null,
    }
}

/// Whether two distinct real units make a `calc()` `+`/`-` an error rather
/// than a preserved expression. dart-sass errors only when BOTH units are
/// known absolute units of DIFFERENT classes (`calc(1px + 1s)`,
/// `calc(1px + 1hz)`); when either unit is relative/unknown
/// (`calc(1px + 1vw)`, `calc(100% - 10px)`) or they share a class but are
/// not convertible (`calc(1khz + 1hz)`), the expression is kept verbatim.
function calc_units_incompatible(a: string, b: string) -> bool {
    // PORT: `match (known_calc_class(a), known_calc_class(b))` → an `if`.
    let ca = known_calc_class(a);
    let cb = known_calc_class(b);
    if (ca != null && cb != null) {
        ca != cb
    } else {
        false
    }
}

/// dart `Value.isBlank`: `null`, an EMPTY unquoted string, or a list whose
/// every element is blank. Blank elements vanish from list serialization
/// (`foo #{""}` emits `foo`, separator included).
function value_is_blank(v: Value) -> bool {
    match (v) {
        Value_Null {} => true,
        Value_Str { _0: let s } => !s.quoted && s.text == "",
        // A BRACKETED list is never blank (`[[]]` and `foo []` survive).
        Value_List { _0: let l } => {
            !l.bracketed
                && l.items.every((x) -> {
                    value_is_blank(x)
                })
        },
        _ => false,
    }
}

/// `#` followed by ASCII hex `digits`, as a shared spelling. Built through a
/// stack buffer rather than `format!` so the `Rc` allocates ONCE: a hex literal
/// is parsed on every compile, and going through a `String` would copy the
/// bytes twice for a spelling that is at most nine of them.
function hex_repr(digits: uint8array) -> string {
    // PORT: the `[b'#'; 9]` stack buffer is gone: `buf.get_mut(1..end)`
    // succeeding is `end <= 9`, and the spelling is `#` plus the decoded
    // digits.
    let end = 1 + digits.length();
    if (end <= 9) {
        let text: string? = string.from_utf8(digits) catch (e) {
            let _e: baml.errors.InvalidArgument => null
        };
        if (text != null) {
            return "#" + text;
        }
    }
    // Unreachable for a parsed literal (3/4/6/8 ASCII hex digits) or a
    // canonicalized one (6): a correct fallback in place of a panic.
    `#${root.std.from_utf8_lossy(digits)}`
}

/// The CSS named-color spelling for an exact, fully-opaque integer RGB
/// triple (dart-sass canonical names). `None` if the triple has no name.
function rgb_name(r: float, g: float, b: float) -> string? {
    // PORT: named `int_` (`int` is a BAML type name).
    let int_ = (v: float) -> int? {
        // dart looks the color up in `namesByColor`, a map keyed by SassColor,
        // so a hit needs `fuzzyHashCode` — the same 1e11 rounding [`fuzzy_eq`]
        // does — to agree on every channel. A channel further off than that
        // has no name, however close it looks.
        let r = v.round();
        if (fuzzy_eq(v, r) && r >= 0.0 && r <= 255.0) {
            root.std.f64_to_int(r)
        } else {
            null
        }
    };
    let r = int_(r);
    if (r == null) {
        return null;
    }
    let g = int_(g);
    if (g == null) {
        return null;
    }
    let b = int_(b);
    if (b == null) {
        return null;
    }
    // PORT: the `(r, g, b)` tuple match is a match on an `"r,g,b"` key.
    match (`${r},${g},${b}`) {
        "0,0,0" => "black",
        "0,0,128" => "navy",
        "0,0,139" => "darkblue",
        "0,0,205" => "mediumblue",
        "0,0,255" => "blue",
        "0,100,0" => "darkgreen",
        "0,128,0" => "green",
        "0,128,128" => "teal",
        "0,139,139" => "darkcyan",
        "0,191,255" => "deepskyblue",
        "0,206,209" => "darkturquoise",
        "0,250,154" => "mediumspringgreen",
        "0,255,0" => "lime",
        "0,255,127" => "springgreen",
        "0,255,255" => "aqua",
        "25,25,112" => "midnightblue",
        "30,144,255" => "dodgerblue",
        "32,178,170" => "lightseagreen",
        "34,139,34" => "forestgreen",
        "46,139,87" => "seagreen",
        "47,79,79" => "darkslategray",
        "50,205,50" => "limegreen",
        "60,179,113" => "mediumseagreen",
        "64,224,208" => "turquoise",
        "65,105,225" => "royalblue",
        "70,130,180" => "steelblue",
        "72,61,139" => "darkslateblue",
        "72,209,204" => "mediumturquoise",
        "75,0,130" => "indigo",
        "85,107,47" => "darkolivegreen",
        "95,158,160" => "cadetblue",
        "100,149,237" => "cornflowerblue",
        "102,51,153" => "rebeccapurple",
        "102,205,170" => "mediumaquamarine",
        "105,105,105" => "dimgray",
        "106,90,205" => "slateblue",
        "107,142,35" => "olivedrab",
        "112,128,144" => "slategray",
        "119,136,153" => "lightslategray",
        "123,104,238" => "mediumslateblue",
        "124,252,0" => "lawngreen",
        "127,255,0" => "chartreuse",
        "127,255,212" => "aquamarine",
        "128,0,0" => "maroon",
        "128,0,128" => "purple",
        "128,128,0" => "olive",
        "128,128,128" => "gray",
        "135,206,235" => "skyblue",
        "135,206,250" => "lightskyblue",
        "138,43,226" => "blueviolet",
        "139,0,0" => "darkred",
        "139,0,139" => "darkmagenta",
        "139,69,19" => "saddlebrown",
        "143,188,143" => "darkseagreen",
        "144,238,144" => "lightgreen",
        "147,112,219" => "mediumpurple",
        "148,0,211" => "darkviolet",
        "152,251,152" => "palegreen",
        "153,50,204" => "darkorchid",
        "154,205,50" => "yellowgreen",
        "160,82,45" => "sienna",
        "165,42,42" => "brown",
        "169,169,169" => "darkgray",
        "173,216,230" => "lightblue",
        "173,255,47" => "greenyellow",
        "175,238,238" => "paleturquoise",
        "176,196,222" => "lightsteelblue",
        "176,224,230" => "powderblue",
        "178,34,34" => "firebrick",
        "184,134,11" => "darkgoldenrod",
        "186,85,211" => "mediumorchid",
        "188,143,143" => "rosybrown",
        "189,183,107" => "darkkhaki",
        "192,192,192" => "silver",
        "199,21,133" => "mediumvioletred",
        "205,92,92" => "indianred",
        "205,133,63" => "peru",
        "210,105,30" => "chocolate",
        "210,180,140" => "tan",
        "211,211,211" => "lightgray",
        "216,191,216" => "thistle",
        "218,112,214" => "orchid",
        "218,165,32" => "goldenrod",
        "219,112,147" => "palevioletred",
        "220,20,60" => "crimson",
        "220,220,220" => "gainsboro",
        "221,160,221" => "plum",
        "222,184,135" => "burlywood",
        "224,255,255" => "lightcyan",
        "230,230,250" => "lavender",
        "233,150,122" => "darksalmon",
        "238,130,238" => "violet",
        "238,232,170" => "palegoldenrod",
        "240,128,128" => "lightcoral",
        "240,230,140" => "khaki",
        "240,248,255" => "aliceblue",
        "240,255,240" => "honeydew",
        "240,255,255" => "azure",
        "244,164,96" => "sandybrown",
        "245,222,179" => "wheat",
        "245,245,220" => "beige",
        "245,245,245" => "whitesmoke",
        "245,255,250" => "mintcream",
        "248,248,255" => "ghostwhite",
        "250,128,114" => "salmon",
        "250,235,215" => "antiquewhite",
        "250,240,230" => "linen",
        "250,250,210" => "lightgoldenrodyellow",
        "253,245,230" => "oldlace",
        "255,0,0" => "red",
        "255,0,255" => "fuchsia",
        "255,20,147" => "deeppink",
        "255,69,0" => "orangered",
        "255,99,71" => "tomato",
        "255,105,180" => "hotpink",
        "255,127,80" => "coral",
        "255,140,0" => "darkorange",
        "255,160,122" => "lightsalmon",
        "255,165,0" => "orange",
        "255,182,193" => "lightpink",
        "255,192,203" => "pink",
        "255,215,0" => "gold",
        "255,218,185" => "peachpuff",
        "255,222,173" => "navajowhite",
        "255,228,181" => "moccasin",
        "255,228,196" => "bisque",
        "255,228,225" => "mistyrose",
        "255,235,205" => "blanchedalmond",
        "255,239,213" => "papayawhip",
        "255,240,245" => "lavenderblush",
        "255,245,238" => "seashell",
        "255,248,220" => "cornsilk",
        "255,250,205" => "lemonchiffon",
        "255,250,240" => "floralwhite",
        "255,250,250" => "snow",
        "255,255,0" => "yellow",
        "255,255,224" => "lightyellow",
        "255,255,240" => "ivory",
        "255,255,255" => "white",
        _ => null,
    }
}

/// Lowercase hex digits, for writing a color's channels without `core::fmt`.
function HEX_DIGITS() -> uint8array {
    "0123456789abcdef".to_utf8()
}

/// The canonical CSS name for an opaque RGB value, but ONLY for the colors whose
/// name is no longer than their shortest hex — i.e. the exact set dart-sass
/// prefers in compressed output (`red` over `#f00`, `aqua` over `#0ff`). Colors
/// whose hex is shorter (e.g. `magenta` -> `#f0f`) are deliberately absent.
/// Derived from the dart-sass oracle, so duplicate names resolve to dart's
/// canonical pick (cyan -> aqua, grey -> gray).
function compressed_color_name(r: int, g: int, b: int) -> string? {
    // PORT: the `(r, g, b)` tuple match is a match on an `"r,g,b"` key.
    match (`${r},${g},${b}`) {
        "0,255,255" => "aqua",
        "240,255,255" => "azure",
        "245,245,220" => "beige",
        "255,228,196" => "bisque",
        "0,0,255" => "blue",
        "165,42,42" => "brown",
        "255,127,80" => "coral",
        "220,20,60" => "crimson",
        "139,0,0" => "darkred",
        "105,105,105" => "dimgray",
        "255,215,0" => "gold",
        "128,128,128" => "gray",
        "0,128,0" => "green",
        "255,105,180" => "hotpink",
        "75,0,130" => "indigo",
        "255,255,240" => "ivory",
        "240,230,140" => "khaki",
        "0,255,0" => "lime",
        "250,240,230" => "linen",
        "128,0,0" => "maroon",
        "0,0,128" => "navy",
        "253,245,230" => "oldlace",
        "128,128,0" => "olive",
        "255,165,0" => "orange",
        "218,112,214" => "orchid",
        "205,133,63" => "peru",
        "255,192,203" => "pink",
        "221,160,221" => "plum",
        "128,0,128" => "purple",
        "255,0,0" => "red",
        "250,128,114" => "salmon",
        "160,82,45" => "sienna",
        "192,192,192" => "silver",
        "135,206,235" => "skyblue",
        "255,250,250" => "snow",
        "210,180,140" => "tan",
        "0,128,128" => "teal",
        "216,191,216" => "thistle",
        "255,99,71" => "tomato",
        "238,130,238" => "violet",
        "245,222,179" => "wheat",
        _ => {
            return null;
        },
    }
}

/// Write the three `rgb()` channel spellings dart-sass uses, separated by `sep`.
///
/// dart switches the WHOLE triple to percentages as soon as ANY channel is
/// non-integral: `mix(red, blue)` is `rgb(50%, 0%, 50%)`, not
/// `rgb(127.5, 0, 127.5)`. An all-integer triple keeps plain numbers
/// (`rgb(1, 2, 3)`).
///
/// Integrality is EXACT for CSS output and FUZZY for `meta.inspect` (dart
/// `_asInt`, serialize.dart:1202: `_inspect ? fuzzyAsInt(number) : (rounded ==
/// number ? rounded : null)` — note dart's own doc comment there describes the
/// opposite of what the code does). The same color therefore has two
/// spellings, and the dust an hsl conversion leaves behind is what separates
/// them: `[measured]` against dart-sass 1.104.1,
/// `color.to-space(hsl(180, 60%, 50%, 0.4), rgb)` has channels
/// (50.999999999999986, 203.99999999999997, 204), writes as
/// `rgba(20%, 80%, 80%, 0.4)` and inspects as `rgba(51, 204, 204, 0.4)`.
function push_rgb_channels(
    out: root.std.StrBuf,
    r: float,
    g: float,
    b: float,
    compressed: bool,
    sep: string,
    inspect: bool,
) -> void {
    // dart `_tryIntegerRgbChannels` -> `_asInt`: a non-integral channel sends
    // the WHOLE triple to percentages (serialize.dart:869-886). Integrality
    // alone decides it — there is no gamut bound, which only the INSPECT form
    // can observe, since CSS output writes an out-of-gamut legacy rgb through
    // its hsl spelling instead. `[measured]` against dart-sass 1.104.1:
    // `meta.inspect(color.to-space(color(srgb 2 0 0), rgb))` — channels
    // (510, 0, 0) — is `rgb(510, 0, 0)`, while `color(srgb 2 0 0.5)` —
    // (510, 0, 127.5) — is `rgb(200%, 0%, 50%)`. A non-finite channel is never
    // an integer, so it always takes the percentage branch below.
    let as_int = (v: float) -> bool {
        if (inspect) {
            fuzzy_is_int(v)
        } else {
            v.is_finite() && v == v.round()
        }
    };
    let ints = as_int(r) && as_int(g) && as_int(b);
    let i = 0;
    for (let v in [r, g, b]) {
        if (i > 0) {
            out.push_str(sep);
        }
        if (ints) {
            push_num(out, v, compressed);
        } else if (!v.is_finite()) {
            // A non-finite channel — which converting an infinite one produces
            // — is written as a `%`-unit `calc()` constant, `calc(NaN * 1%)`,
            // exactly as `ModernColor::chan_pct` writes one. `as_int` already
            // rejected it, so this IS the percentage branch; scaling a
            // non-finite number would change nothing.
            out.push_str(Number.with_unit(v, "%").to_css(compressed));
        } else {
            // `v * 100 / 255`, in dart's operand order — `v / 255.0 * 100.0`
            // differs in the last bit.
            push_num(out, v * 100.0 / 255.0, compressed);
            out.push("%");
        }
        i += 1;
    }
}

/// Write a number the way dart-sass does — round to 10 decimal places, trim
/// trailing zeros, and (when compressed) drop a leading `0` — into `out`.
///
/// This is the primitive; [`fmt_num`] wraps it for callers that want a string
/// of their own. Every spelling a stylesheet actually writes is generated
/// straight into `out`, so serializing a dimension into a declaration's value
/// allocates nothing at all. The rounding and the leading-zero trim work on
/// the tail of `out`: the spelling is the last thing in the buffer, so
/// truncating or inserting only ever moves bytes this call just wrote.
function push_num(out: root.std.StrBuf, n: float, compressed: bool) -> void {
    if (n.is_nan()) {
        out.push_str("NaN");
        return;
    }
    if (n.is_infinite()) {
        out.push_str(
            if (n > 0.0) {
                "Infinity"
            } else {
                "-Infinity"
            },
        );
        return;
    }
    // A NEGATIVE ZERO keeps its sign (dart-sass 1.104.0, "for greater
    // compatibility when using it in CSS calculations"). This is the IEEE sign
    // bit, not the printed text: `0 * -1` and `-0 + -0` are negative zeros and
    // print `-0`, while `0 - 0`, `0 + -0` and `-0 * -1` are POSITIVE zeros and
    // print `0`. A tiny negative that merely ROUNDS to zero is not a zero at
    // all and prints `0` too — that one is handled further down.
    if (n == 0.0) {
        out.push_str(
            if (root.std.is_sign_negative(n)) {
                "-0"
            } else {
                "0"
            },
        );
        return;
    }
    // PORT: the fraction spelling below is built in a scratch buffer `num`
    // (so `start` is 0) and appended to `out` at the end: the rounding and
    // leading-zero fix-ups edit it by char offset, which on a long output
    // `StrBuf` would cost O(len) per number.
    let num = root.std.StrBuf.new();
    let start = num.len();
    // Integers print the way the dart VM does: `fuzzyAsInt` converts the
    // double to a NATIVE int64 (saturating, exactly like Rust's `as i64`)
    // and prints its exact decimal expansion — `593644542057412224`, not the
    // shortest-roundtrip `…200`. A magnitude past int64 fails the round-trip
    // check (saturation changes the value) and falls back to the shortest
    // form, which never overflows into exponential notation.
    if (root.std.fract(n) == 0.0) {
        // PORT: BAML's `int` is 63-bit, so `n as i64` / `i as f64` are
        // computed in an `int` only below 2^62; a larger magnitude (where the
        // i64 cast still succeeds, or saturates) goes to `push_num__wide_i64`,
        // which reports whether the i64 round trip held.
        if (n.abs() < 4611686018427387904.0) {
            let i = root.std.f64_to_int(n);
            if (root.std.int_to_f64(i) == n) {
                push_i64(out, i);
            } else {
                // Integer-valued but past i64: Ryū prints the shortest form in
                // plain positional notation, exactly like Display.
                root.ryu.format64(n, out);
            }
        } else if (!push_num__wide_i64(out, n)) {
            // Integer-valued but past i64: Ryū prints the shortest form in
            // plain positional notation, exactly like Display.
            root.ryu.format64(n, out);
        }
        // An integer's spelling has no fraction to round, cannot be `-0` (a
        // true zero returned above) and cannot start `0.`, so both of the
        // fix-ups below are dead on this path.
        return;
    }
    // dart `_writeNumber`: serialize the SHORTEST round-trip decimal
    // (`double.toString()` + exponent removal), then round it AT THE
    // STRING LEVEL to 10 decimal places, looking only at the 11th digit
    // (half-up). This follows the shortest spelling, not the true value:
    // `2154.15598416745` (true value …44978) still rounds UP to
    // `…1675` because its shortest form ends in a literal `5`.
    push_ecma_shortest(num, n);
    // Which of dart's two writers handles this spelling. `_writeNumber` emits
    // anything shorter than `precision + 2` = 12 characters (sign included)
    // directly, because `0.` plus ten digits cannot overflow the precision;
    // everything longer goes to `_writeRounded`. The two disagree about the
    // leading zero when compressed, so the choice has to be made on the
    // UNROUNDED spelling, before `round_decimal_in_place` shortens it.
    let direct = num.len() - start < 12;
    let rounded = round_decimal_in_place(num, start);
    // A tiny negative ROUNDS to `-0` at the string level; dart prints `0` for
    // it. A true negative zero never reaches here — it returned above.
    if (num.slice_from(start) == "-0") {
        num.truncate(start);
        num.push("0");
    }
    // Compressed style drops the leading zero of a fraction, and which
    // fractions lose it depends on the writer — `[measured]` against dart-sass
    // 1.104.1 over `0.1` … `0.1234567891234` and their negations:
    //
    //   * the direct writer tests the rendered string for a literal `0.`
    //     prefix, which a minus sign has already pushed out of the way, so
    //     `0.5` loses its zero and `-0.5` keeps it;
    //   * `_writeRounded` only reaches the digit-by-digit path when it
    //     actually has digits to drop, and there it omits the integer `0` for
    //     either sign: `-0.00123456789` compresses to `-.0012345679`;
    //   * a long spelling that needs no rounding passes through verbatim, so
    //     it keeps the zero even when positive: `0.0123456789` stays as it is,
    //     one character longer than it has to be.
    if (compressed) {
        if (direct) {
            if (num.slice_from(start).starts_with("0.")) {
                let _ = num.remove(start);
            }
        } else if (rounded) {
            let zero_at = start
                + if (num.char_at(start) == "-") {
                    1
                } else {
                    0
                };
            if (num.slice_from(zero_at).starts_with("0.")) {
                let _ = num.remove(zero_at);
            }
        }
    }
    out.push_str(num.as_str());
}

/// PORT: helper for [`push_num`]'s integer path at magnitudes of 2^62 and
/// more, which BAML's 63-bit `int` cannot hold: `let i = n as i64; if i as f64
/// == n { push_i64(out, i) }` for an integral, finite `n`, with the saturating
/// i64 cast done on a `bigint`. Returns whether it wrote (the round trip held).
function push_num__wide_i64(out: root.std.StrBuf, n: float) -> bool {
    // At or past ±2^63 the cast saturates to i64::MAX / i64::MIN, and
    // `i64::MAX as f64` rounds back up to 2^63: exactly ±2^63 round-trips.
    if (n >= 9223372036854775808.0) {
        if (n == 9223372036854775808.0) {
            out.push_str("9223372036854775807");
            return true;
        }
        return false;
    }
    if (n <= -9223372036854775808.0) {
        if (n == -9223372036854775808.0) {
            out.push_str("-9223372036854775808");
            return true;
        }
        return false;
    }
    // Inside i64 the cast is exact: the integer is mantissa * 2^(exp - 1075)
    // (exp >= 1087 here, so the shift is positive).
    let bits = root.std.f64_to_bits(n.abs());
    let exp = root.std.int_of((bits >> 52) & 2047n);
    let mant = (bits & 4503599627370495n) | 4503599627370496n;
    let v: bigint = mant << (exp - 1075);
    if (n < 0.0) {
        out.push("-");
    }
    out.push_str(v.to_string());
    true
}

/// [`push_num`] into a string of its own, for the callers that want one.
function fmt_num(n: float, compressed: bool) -> string {
    let s = root.std.StrBuf.new();
    push_num(s, n, compressed);
    s.as_str()
}

/// Append an `i64`'s decimal spelling without the `core::fmt` machinery.
/// Numbers are the hottest serialization path (every dimension in every
/// declaration), and `format!("{i}")` spends most of its time in `Formatter`
/// dispatch, not in digit generation. Output is byte-identical to `i64`'s
/// `Display`.
function push_i64(out: root.std.StrBuf, v: int) -> void {
    // Longest spelling: "-9223372036854775808" = 20 bytes.
    // PORT: the byte buffer is an array of one-character strings.
    let buf: string[] = baml.Array.filled(20, "0");
    let neg = v < 0;
    // PORT: `unsigned_abs` is `abs`: BAML's `int` holds no i64::MIN.
    let u = v.abs();
    let at = buf.length();
    while (true) {
        at -= 1;
        // PORT: `b'0' + (u % 10) as u8` is the digit's own spelling.
        buf[at] = (u % 10).to_string();
        u = u / 10;
        if (u == 0) {
            break;
        }
    }
    if (neg) {
        at -= 1;
        buf[at] = "-";
    }
    // The buffer holds only ASCII digits and '-'.
    out.push_str(root.std.join(buf.slice(at, buf.length()), ""));
}

/// Append dart `double.toString()` (ECMA-262 Number::toString): the shortest
/// decimal that round-trips, breaking a tie between two equidistant
/// spellings by choosing the EVEN final digit. Rust's `{}` is also shortest
/// but ties differently (`657390374199289.25` prints `…289.3`, dart prints
/// `…289.2`), so re-round to the same significant-digit count through
/// `{:e}`'s half-to-even rounding and expand the exponent form.
function push_ecma_shortest(out: root.std.StrBuf, n: float) -> void {
    let start = out.len();
    // The zero-dep Ryū port: byte-identical to `format!("{n}")` (proven by
    // its differential fuzz) without the core::fmt machinery, writing into
    // the caller's buffer.
    root.ryu.format64(n, out);
    let rust = out.slice_from(start);
    // Count significant digits (skipping sign, dot, and leading zeros).
    // PORT: the `filter`/`skip_while`/`count` chain as a loop.
    let sig = 0;
    let leading = true;
    for (let c in rust.chars()) {
        if (!c.is_ascii_numeric()) {
            continue;
        }
        if (leading && c == "0") {
            continue;
        }
        leading = false;
        sig += 1;
    }
    if (sig == 0) {
        return;
    }
    if (!rust.includes("e") && n.abs() >= root.std.F64_MIN_POSITIVE()) {
        // A tie between two equidistant shortest spellings requires the
        // spacing of sig-digit decimals (relative, at least 10^-sig) to fit
        // inside the value's one-ulp round-trip window (relative at most
        // 2^-52 for normal doubles), which forces sig >= 16. At 15 or fewer
        // significant digits the shortest round-trip spelling is unique, so
        // Rust's `{}` already IS ECMA toString — skip the re-round and its
        // two parses. Subnormals (wider relative ulps) and exponent-form
        // spellings take the slow path.
        if (sig <= 15) {
            return;
        }
        // A tie can only flip the FINAL digit of the spelling: the two
        // candidates are same-length decimals one apart in the last place,
        // and a carry would end the higher one in `0` — a trailing zero
        // means a shorter spelling round-trips, contradicting shortest-form.
        // The caller rounds at the 10th fractional digit reading only the
        // 11th, so a final digit deeper than the 11th fractional place never
        // reaches the output and the tie-break is moot.
        let dot = rust.index_of(".");
        if (dot != null) {
            if (rust.length() - dot - 1 > 11) {
                return;
            }
        }
    }
    // The slow path is the only one that allocates, and it is reached by a
    // spelling of 16 significant digits or more — never by a hand-written
    // dimension, only by arithmetic that lands on one.
    // PORT: `format!("{:.*e}", sig - 1, n)` is `push_ecma_shortest__fmt_exp`.
    let sci = push_ecma_shortest__fmt_exp(n, sig - 1);
    let sci_value: float? = baml.Float.parse(sci) catch (e) {
        baml.errors.ParseError => null
    };
    if (sci_value != n) {
        return;
    }
    let expanded = expand_exponent(sci);
    let expanded_value: float? = baml.Float.parse(expanded) catch (e) {
        baml.errors.ParseError => null
    };
    if (expanded_value == n) {
        out.truncate(start);
        out.push_str(expanded);
    }
}

/// PORT: `format!("{:.*e}", prec, n)` for a finite, non-zero `n` (no BAML
/// equivalent): `prec + 1` significant digits in Rust's `d.ddde<exp>`
/// spelling, rounded half-to-even on the EXACT binary value as Rust's exact
/// float formatting does.
function push_ecma_shortest__fmt_exp(n: float, prec: int) -> string {
    let neg = root.std.is_sign_negative(n);
    let bits = root.std.f64_to_bits(n.abs());
    let exp = root.std.int_of((bits >> 52) & 2047n);
    let mant = bits & 4503599627370495n;
    let m: bigint = if (exp == 0) {
        mant
    } else {
        mant | 4503599627370496n
    };
    let e = if (exp == 0) {
        -1074
    } else {
        exp - 1075
    };
    // The value is exactly num / den.
    let num: bigint = if (e >= 0) {
        m << e
    } else {
        m
    };
    let den: bigint = if (e >= 0) {
        1n
    } else {
        1n << (0 - e)
    };
    let ten: bigint = 10n;
    // Decimal exponent k with 10^k <= value < 10^(k + 1): estimate, then fix.
    let at_least = (kk: int) -> bool {
        if (kk >= 0) {
            num >= den * ten.pow(root.std.bigint_of(kk))
        } else {
            num * ten.pow(root.std.bigint_of(0 - kk)) >= den
        }
    };
    let k = root.std.f64_to_int(n.abs().log10().floor());
    while (!at_least(k)) {
        k -= 1;
    }
    while (at_least(k + 1)) {
        k += 1;
    }
    // q = value * 10^(prec - k), rounded half-to-even.
    let shift = prec - k;
    let sn: bigint = if (shift >= 0) {
        num * ten.pow(root.std.bigint_of(shift))
    } else {
        num
    };
    let sd: bigint = if (shift >= 0) {
        den
    } else {
        den * ten.pow(root.std.bigint_of(0 - shift))
    };
    let q = sn / sd;
    let r = sn % sd;
    let twice = r * 2n;
    if (twice > sd || (twice == sd && (q & 1n) == 1n)) {
        q = q + 1n;
    }
    // Rounding up past the last digit (`9.99` -> `10.0`) bumps the exponent.
    if (q == ten.pow(root.std.bigint_of(prec + 1))) {
        q = q / ten;
        k += 1;
    }
    let digits = q.to_string();
    let mantissa = if (prec > 0) {
        digits.slice(0, 1) + "." + digits.slice(1, digits.length())
    } else {
        digits
    };
    let body = `${mantissa}e${k}`;
    if (neg) {
        "-" + body
    } else {
        body
    }
}

/// Expand `D.DDDDeK` scientific notation into a plain decimal string (dart
/// `_removeExponent`).
function expand_exponent(sci: string) -> string {
    let epos = sci.index_of("e");
    if (epos == null) {
        return sci;
    }
    let exp = baml.Int.parse(sci.slice(epos + 1, sci.length())) catch (e) {
        baml.errors.ParseError => 0
    };
    let mantissa = sci.slice(0, epos);
    let neg = mantissa.starts_with("-");
    let digits = root.std.join(
        mantissa.chars().filter((c) -> {
            c.is_ascii_numeric()
        }),
        "",
    );
    let sign = if (neg) {
        "-"
    } else {
        ""
    };
    // One digit sits before the dot in `{:e}` form, so the decimal point in
    // the digit string belongs after position `exp + 1`.
    let point = exp + 1;
    if (point <= 0) {
        let zeros = "0".repeat(0 - point);
        `${sign}0.${zeros}${digits}`
    } else if (point >= digits.length()) {
        let zeros = "0".repeat(point - digits.length());
        `${sign}${digits}${zeros}`
    } else {
        `${sign}${digits.slice(0, point)}.${digits.slice(point, digits.length())}`
    }
}

/// dart `_writeRounded`, in place: round the plain decimal spelling that
/// starts at `start` to 10 fractional digits by inspecting ONLY the 11th
/// digit (>= '5' carries up), then trim trailing fractional zeros. Ten or
/// fewer fractional digits pass verbatim.
///
/// Returns whether any digit was actually dropped, which is what decides
/// whether compressed output loses the leading zero of a negative fraction
/// (see [`push_num`]).
function round_decimal_in_place(out: root.std.StrBuf, start: int) -> bool {
    let found = out.slice_from(start).index_of(".");
    if (found == null) {
        return false;
    }
    let dot = start + found;
    let dropped = false;
    if (out.len() - dot - 1 > 10) {
        let round_up = (out.char_at(dot + 11) ?? "") >= "5";
        out.truncate(dot + 11);
        if (round_up) {
            carry_one(out, start);
        }
        dropped = true;
    }
    trim_fraction_in_place(out, start);
    dropped
}

/// Add one to the last digit of the decimal spelling at `start..`, carrying
/// leftwards: `1.29` -> `1.30`, `9.99` -> `10.00`, `-9.9` -> `-10.0`.
function carry_one(out: root.std.StrBuf, start: int) -> void {
    // Walk back over the digits a carry turns into zeros — the trailing `9`s
    // and the decimal point between them — stopping on the byte that absorbs
    // it: a digit below `9`, the sign, or the start of the spelling.
    let i = out.len();
    while (i > start && (out.char_at(i - 1) == "9" || out.char_at(i - 1) == ".")) {
        i -= 1;
    }
    // Everything from `i` on is `9`s with at most one `.` among them, and it
    // is the tail of the buffer, so the carry is one truncate and one push
    // instead of a byte edited in the middle of a string.
    let width = out.len() - i;
    let dot = out.slice_from(i).index_of(".");
    let prev: string? = if (i > start) {
        out.char_at(i - 1)
    } else {
        null
    };
    let cl = match (prev) {
        let d: string if d.is_ascii_numeric() => {
            root.std.Tuple2 { _0: i - 1, _1: root.std.chr_unchecked(root.std.ord(d) + 1) }
        },
        // Nothing left to absorb the carry — the spelling was all `9`s, or the
        // only thing before them is the sign — so it grows a leading `1`.
        _ => root.std.Tuple2 { _0: i, _1: "1" },
    };
    let cut = cl._0;
    let lead = cl._1;
    out.truncate(cut);
    out.push(lead);
    let k = 0;
    while (k < width) {
        out.push(
            if (dot == k) {
                "."
            } else {
                "0"
            },
        );
        k += 1;
    }
}

/// Trim trailing fractional zeros (and a then-trailing dot) from the spelling
/// at `start..`; `-0` and all-zero results collapse to `0` at the caller.
function trim_fraction_in_place(out: root.std.StrBuf, start: int) -> void {
    let text = out.slice_from(start);
    if (!text.includes(".")) {
        return;
    }
    let kept = root.std.trim_end_matches(root.std.trim_end_matches(text, "0"), ".").length();
    out.truncate(start + kept);
}

/// Look up a CSS named color. Covers the complete set of 148 CSS Color 4
/// named colors plus `transparent`; unknown identifiers stay unquoted strings.
function named_color(name: string) -> Color? {
    let t: root.std.Tuple4<int, int, int, float> = match (root.std.ascii_lower(name)) {
        "transparent" => root.std.Tuple4 { _0: 0, _1: 0, _2: 0, _3: 0.0 },
        "aliceblue" => root.std.Tuple4 { _0: 240, _1: 248, _2: 255, _3: 1.0 },
        "antiquewhite" => root.std.Tuple4 { _0: 250, _1: 235, _2: 215, _3: 1.0 },
        "aqua" | "cyan" => root.std.Tuple4 { _0: 0, _1: 255, _2: 255, _3: 1.0 },
        "aquamarine" => root.std.Tuple4 { _0: 127, _1: 255, _2: 212, _3: 1.0 },
        "azure" => root.std.Tuple4 { _0: 240, _1: 255, _2: 255, _3: 1.0 },
        "beige" => root.std.Tuple4 { _0: 245, _1: 245, _2: 220, _3: 1.0 },
        "bisque" => root.std.Tuple4 { _0: 255, _1: 228, _2: 196, _3: 1.0 },
        "black" => root.std.Tuple4 { _0: 0, _1: 0, _2: 0, _3: 1.0 },
        "blanchedalmond" => root.std.Tuple4 { _0: 255, _1: 235, _2: 205, _3: 1.0 },
        "blue" => root.std.Tuple4 { _0: 0, _1: 0, _2: 255, _3: 1.0 },
        "blueviolet" => root.std.Tuple4 { _0: 138, _1: 43, _2: 226, _3: 1.0 },
        "brown" => root.std.Tuple4 { _0: 165, _1: 42, _2: 42, _3: 1.0 },
        "burlywood" => root.std.Tuple4 { _0: 222, _1: 184, _2: 135, _3: 1.0 },
        "cadetblue" => root.std.Tuple4 { _0: 95, _1: 158, _2: 160, _3: 1.0 },
        "chartreuse" => root.std.Tuple4 { _0: 127, _1: 255, _2: 0, _3: 1.0 },
        "chocolate" => root.std.Tuple4 { _0: 210, _1: 105, _2: 30, _3: 1.0 },
        "coral" => root.std.Tuple4 { _0: 255, _1: 127, _2: 80, _3: 1.0 },
        "cornflowerblue" => root.std.Tuple4 { _0: 100, _1: 149, _2: 237, _3: 1.0 },
        "cornsilk" => root.std.Tuple4 { _0: 255, _1: 248, _2: 220, _3: 1.0 },
        "crimson" => root.std.Tuple4 { _0: 220, _1: 20, _2: 60, _3: 1.0 },
        "darkblue" => root.std.Tuple4 { _0: 0, _1: 0, _2: 139, _3: 1.0 },
        "darkcyan" => root.std.Tuple4 { _0: 0, _1: 139, _2: 139, _3: 1.0 },
        "darkgoldenrod" => root.std.Tuple4 { _0: 184, _1: 134, _2: 11, _3: 1.0 },
        "darkgray" | "darkgrey" => root.std.Tuple4 { _0: 169, _1: 169, _2: 169, _3: 1.0 },
        "darkgreen" => root.std.Tuple4 { _0: 0, _1: 100, _2: 0, _3: 1.0 },
        "darkkhaki" => root.std.Tuple4 { _0: 189, _1: 183, _2: 107, _3: 1.0 },
        "darkmagenta" => root.std.Tuple4 { _0: 139, _1: 0, _2: 139, _3: 1.0 },
        "darkolivegreen" => root.std.Tuple4 { _0: 85, _1: 107, _2: 47, _3: 1.0 },
        "darkorange" => root.std.Tuple4 { _0: 255, _1: 140, _2: 0, _3: 1.0 },
        "darkorchid" => root.std.Tuple4 { _0: 153, _1: 50, _2: 204, _3: 1.0 },
        "darkred" => root.std.Tuple4 { _0: 139, _1: 0, _2: 0, _3: 1.0 },
        "darksalmon" => root.std.Tuple4 { _0: 233, _1: 150, _2: 122, _3: 1.0 },
        "darkseagreen" => root.std.Tuple4 { _0: 143, _1: 188, _2: 143, _3: 1.0 },
        "darkslateblue" => root.std.Tuple4 { _0: 72, _1: 61, _2: 139, _3: 1.0 },
        "darkslategray" | "darkslategrey" => root.std.Tuple4 { _0: 47, _1: 79, _2: 79, _3: 1.0 },
        "darkturquoise" => root.std.Tuple4 { _0: 0, _1: 206, _2: 209, _3: 1.0 },
        "darkviolet" => root.std.Tuple4 { _0: 148, _1: 0, _2: 211, _3: 1.0 },
        "deeppink" => root.std.Tuple4 { _0: 255, _1: 20, _2: 147, _3: 1.0 },
        "deepskyblue" => root.std.Tuple4 { _0: 0, _1: 191, _2: 255, _3: 1.0 },
        "dimgray" | "dimgrey" => root.std.Tuple4 { _0: 105, _1: 105, _2: 105, _3: 1.0 },
        "dodgerblue" => root.std.Tuple4 { _0: 30, _1: 144, _2: 255, _3: 1.0 },
        "firebrick" => root.std.Tuple4 { _0: 178, _1: 34, _2: 34, _3: 1.0 },
        "floralwhite" => root.std.Tuple4 { _0: 255, _1: 250, _2: 240, _3: 1.0 },
        "forestgreen" => root.std.Tuple4 { _0: 34, _1: 139, _2: 34, _3: 1.0 },
        "fuchsia" | "magenta" => root.std.Tuple4 { _0: 255, _1: 0, _2: 255, _3: 1.0 },
        "gainsboro" => root.std.Tuple4 { _0: 220, _1: 220, _2: 220, _3: 1.0 },
        "ghostwhite" => root.std.Tuple4 { _0: 248, _1: 248, _2: 255, _3: 1.0 },
        "gold" => root.std.Tuple4 { _0: 255, _1: 215, _2: 0, _3: 1.0 },
        "goldenrod" => root.std.Tuple4 { _0: 218, _1: 165, _2: 32, _3: 1.0 },
        "gray" | "grey" => root.std.Tuple4 { _0: 128, _1: 128, _2: 128, _3: 1.0 },
        "green" => root.std.Tuple4 { _0: 0, _1: 128, _2: 0, _3: 1.0 },
        "greenyellow" => root.std.Tuple4 { _0: 173, _1: 255, _2: 47, _3: 1.0 },
        "honeydew" => root.std.Tuple4 { _0: 240, _1: 255, _2: 240, _3: 1.0 },
        "hotpink" => root.std.Tuple4 { _0: 255, _1: 105, _2: 180, _3: 1.0 },
        "indianred" => root.std.Tuple4 { _0: 205, _1: 92, _2: 92, _3: 1.0 },
        "indigo" => root.std.Tuple4 { _0: 75, _1: 0, _2: 130, _3: 1.0 },
        "ivory" => root.std.Tuple4 { _0: 255, _1: 255, _2: 240, _3: 1.0 },
        "khaki" => root.std.Tuple4 { _0: 240, _1: 230, _2: 140, _3: 1.0 },
        "lavender" => root.std.Tuple4 { _0: 230, _1: 230, _2: 250, _3: 1.0 },
        "lavenderblush" => root.std.Tuple4 { _0: 255, _1: 240, _2: 245, _3: 1.0 },
        "lawngreen" => root.std.Tuple4 { _0: 124, _1: 252, _2: 0, _3: 1.0 },
        "lemonchiffon" => root.std.Tuple4 { _0: 255, _1: 250, _2: 205, _3: 1.0 },
        "lightblue" => root.std.Tuple4 { _0: 173, _1: 216, _2: 230, _3: 1.0 },
        "lightcoral" => root.std.Tuple4 { _0: 240, _1: 128, _2: 128, _3: 1.0 },
        "lightcyan" => root.std.Tuple4 { _0: 224, _1: 255, _2: 255, _3: 1.0 },
        "lightgoldenrodyellow" => root.std.Tuple4 { _0: 250, _1: 250, _2: 210, _3: 1.0 },
        "lightgray" | "lightgrey" => root.std.Tuple4 { _0: 211, _1: 211, _2: 211, _3: 1.0 },
        "lightgreen" => root.std.Tuple4 { _0: 144, _1: 238, _2: 144, _3: 1.0 },
        "lightpink" => root.std.Tuple4 { _0: 255, _1: 182, _2: 193, _3: 1.0 },
        "lightsalmon" => root.std.Tuple4 { _0: 255, _1: 160, _2: 122, _3: 1.0 },
        "lightseagreen" => root.std.Tuple4 { _0: 32, _1: 178, _2: 170, _3: 1.0 },
        "lightskyblue" => root.std.Tuple4 { _0: 135, _1: 206, _2: 250, _3: 1.0 },
        "lightslategray" | "lightslategrey" => {
            root.std.Tuple4 { _0: 119, _1: 136, _2: 153, _3: 1.0 }
        },
        "lightsteelblue" => root.std.Tuple4 { _0: 176, _1: 196, _2: 222, _3: 1.0 },
        "lightyellow" => root.std.Tuple4 { _0: 255, _1: 255, _2: 224, _3: 1.0 },
        "lime" => root.std.Tuple4 { _0: 0, _1: 255, _2: 0, _3: 1.0 },
        "limegreen" => root.std.Tuple4 { _0: 50, _1: 205, _2: 50, _3: 1.0 },
        "linen" => root.std.Tuple4 { _0: 250, _1: 240, _2: 230, _3: 1.0 },
        "maroon" => root.std.Tuple4 { _0: 128, _1: 0, _2: 0, _3: 1.0 },
        "mediumaquamarine" => root.std.Tuple4 { _0: 102, _1: 205, _2: 170, _3: 1.0 },
        "mediumblue" => root.std.Tuple4 { _0: 0, _1: 0, _2: 205, _3: 1.0 },
        "mediumorchid" => root.std.Tuple4 { _0: 186, _1: 85, _2: 211, _3: 1.0 },
        "mediumpurple" => root.std.Tuple4 { _0: 147, _1: 112, _2: 219, _3: 1.0 },
        "mediumseagreen" => root.std.Tuple4 { _0: 60, _1: 179, _2: 113, _3: 1.0 },
        "mediumslateblue" => root.std.Tuple4 { _0: 123, _1: 104, _2: 238, _3: 1.0 },
        "mediumspringgreen" => root.std.Tuple4 { _0: 0, _1: 250, _2: 154, _3: 1.0 },
        "mediumturquoise" => root.std.Tuple4 { _0: 72, _1: 209, _2: 204, _3: 1.0 },
        "mediumvioletred" => root.std.Tuple4 { _0: 199, _1: 21, _2: 133, _3: 1.0 },
        "midnightblue" => root.std.Tuple4 { _0: 25, _1: 25, _2: 112, _3: 1.0 },
        "mintcream" => root.std.Tuple4 { _0: 245, _1: 255, _2: 250, _3: 1.0 },
        "mistyrose" => root.std.Tuple4 { _0: 255, _1: 228, _2: 225, _3: 1.0 },
        "moccasin" => root.std.Tuple4 { _0: 255, _1: 228, _2: 181, _3: 1.0 },
        "navajowhite" => root.std.Tuple4 { _0: 255, _1: 222, _2: 173, _3: 1.0 },
        "navy" => root.std.Tuple4 { _0: 0, _1: 0, _2: 128, _3: 1.0 },
        "oldlace" => root.std.Tuple4 { _0: 253, _1: 245, _2: 230, _3: 1.0 },
        "olive" => root.std.Tuple4 { _0: 128, _1: 128, _2: 0, _3: 1.0 },
        "olivedrab" => root.std.Tuple4 { _0: 107, _1: 142, _2: 35, _3: 1.0 },
        "orange" => root.std.Tuple4 { _0: 255, _1: 165, _2: 0, _3: 1.0 },
        "orangered" => root.std.Tuple4 { _0: 255, _1: 69, _2: 0, _3: 1.0 },
        "orchid" => root.std.Tuple4 { _0: 218, _1: 112, _2: 214, _3: 1.0 },
        "palegoldenrod" => root.std.Tuple4 { _0: 238, _1: 232, _2: 170, _3: 1.0 },
        "palegreen" => root.std.Tuple4 { _0: 152, _1: 251, _2: 152, _3: 1.0 },
        "paleturquoise" => root.std.Tuple4 { _0: 175, _1: 238, _2: 238, _3: 1.0 },
        "palevioletred" => root.std.Tuple4 { _0: 219, _1: 112, _2: 147, _3: 1.0 },
        "papayawhip" => root.std.Tuple4 { _0: 255, _1: 239, _2: 213, _3: 1.0 },
        "peachpuff" => root.std.Tuple4 { _0: 255, _1: 218, _2: 185, _3: 1.0 },
        "peru" => root.std.Tuple4 { _0: 205, _1: 133, _2: 63, _3: 1.0 },
        "pink" => root.std.Tuple4 { _0: 255, _1: 192, _2: 203, _3: 1.0 },
        "plum" => root.std.Tuple4 { _0: 221, _1: 160, _2: 221, _3: 1.0 },
        "powderblue" => root.std.Tuple4 { _0: 176, _1: 224, _2: 230, _3: 1.0 },
        "purple" => root.std.Tuple4 { _0: 128, _1: 0, _2: 128, _3: 1.0 },
        "rebeccapurple" => root.std.Tuple4 { _0: 102, _1: 51, _2: 153, _3: 1.0 },
        "red" => root.std.Tuple4 { _0: 255, _1: 0, _2: 0, _3: 1.0 },
        "rosybrown" => root.std.Tuple4 { _0: 188, _1: 143, _2: 143, _3: 1.0 },
        "royalblue" => root.std.Tuple4 { _0: 65, _1: 105, _2: 225, _3: 1.0 },
        "saddlebrown" => root.std.Tuple4 { _0: 139, _1: 69, _2: 19, _3: 1.0 },
        "salmon" => root.std.Tuple4 { _0: 250, _1: 128, _2: 114, _3: 1.0 },
        "sandybrown" => root.std.Tuple4 { _0: 244, _1: 164, _2: 96, _3: 1.0 },
        "seagreen" => root.std.Tuple4 { _0: 46, _1: 139, _2: 87, _3: 1.0 },
        "seashell" => root.std.Tuple4 { _0: 255, _1: 245, _2: 238, _3: 1.0 },
        "sienna" => root.std.Tuple4 { _0: 160, _1: 82, _2: 45, _3: 1.0 },
        "silver" => root.std.Tuple4 { _0: 192, _1: 192, _2: 192, _3: 1.0 },
        "skyblue" => root.std.Tuple4 { _0: 135, _1: 206, _2: 235, _3: 1.0 },
        "slateblue" => root.std.Tuple4 { _0: 106, _1: 90, _2: 205, _3: 1.0 },
        "slategray" | "slategrey" => root.std.Tuple4 { _0: 112, _1: 128, _2: 144, _3: 1.0 },
        "snow" => root.std.Tuple4 { _0: 255, _1: 250, _2: 250, _3: 1.0 },
        "springgreen" => root.std.Tuple4 { _0: 0, _1: 255, _2: 127, _3: 1.0 },
        "steelblue" => root.std.Tuple4 { _0: 70, _1: 130, _2: 180, _3: 1.0 },
        "tan" => root.std.Tuple4 { _0: 210, _1: 180, _2: 140, _3: 1.0 },
        "teal" => root.std.Tuple4 { _0: 0, _1: 128, _2: 128, _3: 1.0 },
        "thistle" => root.std.Tuple4 { _0: 216, _1: 191, _2: 216, _3: 1.0 },
        "tomato" => root.std.Tuple4 { _0: 255, _1: 99, _2: 71, _3: 1.0 },
        "turquoise" => root.std.Tuple4 { _0: 64, _1: 224, _2: 208, _3: 1.0 },
        "violet" => root.std.Tuple4 { _0: 238, _1: 130, _2: 238, _3: 1.0 },
        "wheat" => root.std.Tuple4 { _0: 245, _1: 222, _2: 179, _3: 1.0 },
        "white" => root.std.Tuple4 { _0: 255, _1: 255, _2: 255, _3: 1.0 },
        "whitesmoke" => root.std.Tuple4 { _0: 245, _1: 245, _2: 245, _3: 1.0 },
        "yellow" => root.std.Tuple4 { _0: 255, _1: 255, _2: 0, _3: 1.0 },
        "yellowgreen" => root.std.Tuple4 { _0: 154, _1: 205, _2: 50, _3: 1.0 },
        _ => {
            return null;
        },
    };
    let r = t._0;
    let g = t._1;
    let b = t._2;
    let a = t._3;
    Color { r: r * 1.0, g: g * 1.0, b: b * 1.0, a: a, repr: name, modern: null }
}
