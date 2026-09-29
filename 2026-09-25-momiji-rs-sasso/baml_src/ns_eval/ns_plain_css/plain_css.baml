// Ported from sasso `src/eval/plain_css.rs` (namespace `root.eval.plain_css`).

interface EvaluatorPlainCss {
    /// Emit a plain-CSS (`.css`) module's statements, preserving nesting (no
    /// Sass flattening), keeping `&` parent references literal, and resolving
    /// only `#{…}` interpolation. The parser has already rejected Sass-only
    /// constructs, so the remaining statements are plain CSS.
    function exec_css(
        self,
        stmts: root.ast.Stmt[],
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    function exec_css_inner(
        self,
        stmts: root.ast.Stmt[],
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Build the body of a top-level plain-CSS at-rule: style rules (with their
    /// own first-level bubbling), bare declarations, comments, and nested
    /// at-rules.
    function css_at_body(
        self,
        stmts: root.ast.Stmt[],
        frames: bool,
    ) -> root.eval.OutNode[] throws unknown;

    /// Build the children of a *top-level* plain-CSS style rule: declarations
    /// and nested rules stay in the block; a block at-rule (`@media` etc.)
    /// bubbles out wrapping a copy of the parent rule (dart-sass's standard
    /// at-rule bubbling — `a {@media b {c: d}}` → `@media b { a { c: d } }`).
    /// Deeper levels never bubble (see [`Evaluator::css_body`]).
    function css_rule_children(
        self,
        stmts: root.ast.Stmt[],
        parent_selectors: string[],
    ) -> root.std.Tuple2<root.eval.OutItem[], root.eval.OutNode[]> throws unknown;

    /// Build a plain-CSS custom at-rule's body as nested output items: each
    /// declaration is a custom property, which emits its value verbatim right
    /// after the colon, exactly as [`Self::eval_css_custom_at_rule`] writes it.
    function css_custom_decl_items(
        self,
        body: root.ast.CssCustomItem[],
    ) -> root.eval.OutItem[] throws unknown;

    /// Resolve a plain-CSS selector to its comma-separated parts, keeping `&`
    /// and combinators verbatim (no parent resolution), and rejecting the
    /// Sass-only selector forms that plain CSS forbids. The parts come back
    /// re-serialized the way dart's parser emits them (identifier attribute
    /// values lose their quotes, whitespace collapses), along with the
    /// source's per-complex line-break flags (`a,\nb` keeps its lines).
    function css_selectors(
        self,
        sel: root.ast.TplPiece[],
        top_level: bool,
    ) -> root.std.Tuple2<string[], bool[]> throws unknown;

    /// Convert a `@keyframes` frame's selector list. A frame selector is a list
    /// of keyframe STOPS (`from`, `50%`), not of CSS selectors, and dart
    /// re-serializes the stops joined with `", "`: the author's line breaks do
    /// not survive it, none of the selector normalization applies (`+5%` is a
    /// stop, not a sibling combinator), and `from`/`to` and a percentage's
    /// exponent marker come back lowercased.
    function css_frame_selectors(self, sel: root.ast.TplPiece[]) -> string[] throws unknown;

    /// Build the body of a `@keyframes` below the bubbling level: as
    /// [`Evaluator::css_body`], except that a rule at this level is a FRAME —
    /// its selector is a stop list, and its own body nests natively.
    function css_frames_body(self, stmts: root.ast.Stmt[]) -> root.eval.OutItem[] throws unknown;

    /// Build a plain-CSS rule body below the first nesting level: declarations
    /// and nested style rules with nesting preserved (`OutItem::NestedRule`),
    /// and block at-rules kept in place (`OutItem::NestedAtRule`) — dart-sass
    /// `_hasCssNesting` skips bubbling once nesting is already native.
    function css_body(self, stmts: root.ast.Stmt[]) -> root.eval.OutItem[] throws unknown;

    /// Process one plain-CSS statement into rule-body items (the shared body of
    /// [`Evaluator::css_body`] and the non-bubbling arm of
    /// [`Evaluator::css_rule_children`]).
    function css_body_stmt(
        self,
        stmt: root.ast.Stmt,
        items: root.eval.OutItem[],
    ) -> void throws unknown;
}

implements EvaluatorPlainCss for root.eval.Evaluator {
    /// Emit a plain-CSS (`.css`) module's statements, preserving nesting (no
    /// Sass flattening), keeping `&` parent references literal, and resolving
    /// only `#{…}` interpolation. The parser has already rejected Sass-only
    /// constructs, so the remaining statements are plain CSS.
    function exec_css(self, stmts: root.ast.Stmt[], parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        let saved = self.in_plain_css;
        self.in_plain_css = true;
        // PORT: the `Result` is caught so the flag is restored on both paths.
        self.exec_css_inner(stmts, parents, sink) catch (e) {
            let err: root.error.Error => {
                self.in_plain_css = saved;
                throw err;
            }
        };
        self.in_plain_css = saved;
    }

    function exec_css_inner(self, stmts: root.ast.Stmt[], parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // When the plain-CSS sheet is imported inside a style rule, top-level
        // rules whose selector contains a parent reference `&` keep native
        // CSS-nesting semantics: they are emitted VERBATIM as nested children
        // of one leading parent-selector shell (dart `nestWithin` with
        // `preserveParentSelectors`), while `&`-less rules get the descendant
        // join below.
        if (parents.length() != 0) {
            let preserved: root.eval.OutItem[] = [];
            for (let stmt in stmts) {
                if let rs: root.ast.Stmt_Rule = stmt {
                    let r = rs._0;
                    let own_t = self.css_selectors(r.selector, true);
                    let own = own_t._0;
                    let own_lbs = own_t._1;
                    if (own.some((s: string) -> bool { root.eval.part_has_parent_ref(s) })) {
                        let inner = self.css_body(r.body);
                        if (inner.length() != 0) {
                            let lines = self.map_only_lines(r.selector_pos);
                            preserved.push(root.eval.OutItem_NestedRule {
                                selectors: own,
                                linebreaks: own_lbs,
                                items: inner,
                                lines: lines,
                            });
                        }
                    }
                }
            }
            if (preserved.length() != 0) {
                sink.value.push_at_rule(root.eval.OutNode_plain_rule(
                    root.std.clone_vec(parents),
                    preserved,
                    root.ast.SrcLines.default(),
                ));
            }
        }
        for (let stmt in stmts) {
            match (stmt) {
                let rs: root.ast.Stmt_Rule => {
                    let r = rs._0;
                    // When the plain-CSS sheet is imported inside a style rule,
                    // its outermost rules nest under the Sass parent (descendant
                    // join); inner nesting stays native (dart-sass `nestWithin`
                    // with `preserveParentSelectors`). The sheet's own top level
                    // always rejects leading combinators — also when merged
                    // under a Sass parent (dart checks in the merge branch).
                    let own_t = self.css_selectors(r.selector, true);
                    let own = own_t._0;
                    let own_lbs = own_t._1;
                    // A `&`-bearing rule was already emitted in the leading
                    // parent shell above.
                    if (parents.length() != 0 && own.some((s: string) -> bool { root.eval.part_has_parent_ref(s) })) {
                        continue;
                    }
                    // Line structure carries through only for the sheet's own
                    // top level; the descendant join under a Sass parent
                    // re-shapes the list.
                    let linebreaks: bool[] = if (parents.length() == 0) {
                        own_lbs
                    } else {
                        []
                    };
                    let selectors: string[] = if (parents.length() == 0) {
                        own
                    } else {
                        parents
                            .flat_map((p: string) -> string[] { own.map((s: string) -> string { `${p} ${s}` }) })
                    };
                    let ib = self.css_rule_children(r.body, selectors);
                    let items = ib._0;
                    let bubbled = ib._1;
                    // A childless rule is invisible (dart-sass skips it when
                    // serializing) — e.g. when its whole body bubbled out.
                    if (items.length() != 0) {
                        sink.value.push_at_rule(root.eval.OutNode_Rule {
                            selectors: root.eval.RuleSelectors_Raw { _0: selectors },
                            linebreaks: linebreaks,
                            items: items,
                            lines: self.stamp(root.ast.SrcLines {
                                file: 0,
                                start: r.brace_line,
                                end: r.end_line,
                                col: 0,
                                start_col: root.std.saturating_sub_u(r.selector_pos.col, 1),
                                map_file: 0,
                                // Source-map: the selector's own line.
                                map_line: r.selector_pos.line,
                            }),
                            extend_base: root.std.INT_MAX(),
                        });
                    }
                    for (let node in bubbled) {
                        sink.value.push_at_rule(node);
                    }
                },
                let cs: root.ast.Stmt_Comment => {
                    let text = self.eval_template(cs._0);
                    let lines = self.stamp(cs._1);
                    sink.value.push_at_rule(root.eval.OutNode_Comment { _0: text, _1: lines });
                },
                // A plain CSS file never inlines an `@import`; every entry is
                // emitted verbatim (`@import "x";` / `@import url(x);`), matching
                // dart-sass loading a `.css` stylesheet.
                let imp: root.ast.Stmt_Import => {
                    for (let arg in imp.args) {
                        let tp: root.std.Tuple2<string, root.scanner.Pos> = match (arg) {
                            let c: root.ast.ImportArg_Css => root.std.Tuple2 {
                                _0: self.serialize_css_import(c.url, c.modifiers),
                                _1: c.pos,
                            },
                            let sa: root.ast.ImportArg_Sass => root.std.Tuple2 {
                                _0: root.value.serialize_quoted(sa.path),
                                _1: sa.pos,
                            },
                            _ => root.std.unreachable(),
                        };
                        let text = tp._0;
                        let pos = tp._1;
                        // Source-map: the rule maps to its URL token.
                        let lines = self.map_only_lines(pos);
                        sink.value.push_at_rule(root.eval.OutNode_Raw {
                            _0: `@import${self.at_rule_gap()}${text};`,
                            _1: lines,
                        });
                    }
                },
                let m: root.ast.Stmt_Media => {
                    let queries = self.resolve_media_queries(m.query);
                    let prelude = root.eval.serialize_media_queries(queries, self.compressed());
                    let out_body = self.css_at_body(m.body, false);
                    if (out_body.length() != 0) {
                        let lines = self.stamp(m.lines);
                        sink.value.push_at_rule(root.eval.OutNode_AtRule {
                            name: "media",
                            prelude: prelude,
                            body: out_body,
                            has_block: true,
                            kind: root.eval.AtRuleKind.Conditional,
                            lines: lines,
                        });
                    }
                },
                let sup: root.ast.Stmt_Supports => {
                    let prelude = self.serialize_supports_condition(sup.condition);
                    let out_body = self.css_at_body(sup.body, false);
                    if (out_body.length() != 0) {
                        sink.value.push_at_rule(root.eval.OutNode_AtRule {
                            name: "supports",
                            prelude: prelude,
                            body: out_body,
                            has_block: true,
                            kind: root.eval.AtRuleKind.Conditional,
                            lines: self.stamp(sup.lines),
                        });
                    }
                },
                let at: root.ast.Stmt_AtRule => {
                    // dart-sass never copies a loaded file's top-level
                    // `@charset`: the output's own is re-derived from its
                    // content. One nested in an at-rule or a style rule is
                    // kept verbatim, as dart keeps it.
                    if (at.body == null && root.std.eq_ignore_ascii_case(at.name, "charset")) {
                        continue;
                    }
                    let prelude_s = root.std.trim(self.eval_template(at.prelude));
                    let lines = self.stamp(at.lines);
                    let body = at.body;
                    if (body == null) {
                        sink.value.push_at_rule(root.eval.OutNode_AtRule {
                            name: at.name,
                            prelude: prelude_s,
                            body: [],
                            has_block: false,
                            kind: root.eval.AtRuleKind.Generic,
                            lines: lines,
                        });
                    } else {
                        let b = body;
                        let out_body = self.css_at_body(b, false);
                        sink.value.push_at_rule(root.eval.OutNode_AtRule {
                            name: at.name,
                            prelude: prelude_s,
                            body: out_body,
                            has_block: true,
                            kind: root.eval.AtRuleKind.Generic,
                            lines: lines,
                        });
                    }
                },
                let kf: root.ast.Stmt_Keyframes => {
                    let prelude_s = root.std.trim(self.eval_template(kf.prelude));
                    let out_body = self.css_at_body(kf.body, true);
                    let lines = self.stamp(kf.lines);
                    sink.value.push_at_rule(root.eval.OutNode_AtRule {
                        name: kf.name,
                        prelude: prelude_s,
                        body: out_body,
                        has_block: true,
                        kind: root.eval.AtRuleKind.Generic,
                        lines: lines,
                    });
                },
                // A plain-CSS custom `@function --x` is emitted verbatim, same
                // as in an SCSS sheet.
                let cc: root.ast.Stmt_CssCustomAtRule => {
                    self.eval_css_custom_at_rule(cc.name, cc.prelude, cc.body, sink);
                },
                _ => {},
            }
        }
    }

    /// Build the body of a top-level plain-CSS at-rule: style rules (with their
    /// own first-level bubbling), bare declarations, comments, and nested
    /// at-rules.
    function css_at_body(self, stmts: root.ast.Stmt[], frames: bool) -> root.eval.OutNode[] {
        if (frames) {
            check_keyframes_body(stmts);
        }
        let out: root.eval.OutNode[] = [];
        for (let stmt in stmts) {
            match (stmt) {
                let rs: root.ast.Stmt_Rule => {
                    let r = rs._0;
                    let sl: root.std.Tuple2<string[], bool[]> = if (frames) {
                        root.std.Tuple2 { _0: self.css_frame_selectors(r.selector), _1: [] }
                    } else {
                        self.css_selectors(r.selector, false)
                    };
                    let selectors = sl._0;
                    let linebreaks = sl._1;
                    // Inside `@keyframes` this rule is a FRAME, and nothing in
                    // it bubbles: dart keeps a nested at-rule where it is
                    // (`@keyframes k {from {@foo {a: b}}}`), while hoisting it
                    // would move it out of the frame and wrap the frame
                    // selector around its body. A frame body is therefore read
                    // the way any deeper level is, with no hoisting.
                    let ib: root.std.Tuple2<root.eval.OutItem[], root.eval.OutNode[]> = if (frames) {
                        root.std.Tuple2 { _0: self.css_body(r.body), _1: [] }
                    } else {
                        self.css_rule_children(r.body, selectors)
                    };
                    let items = ib._0;
                    let bubbled = ib._1;
                    if (items.length() != 0) {
                        out.push(root.eval.OutNode_Rule {
                            selectors: root.eval.RuleSelectors_Raw { _0: selectors },
                            linebreaks: linebreaks,
                            items: items,
                            lines: self.stamp(root.ast.SrcLines {
                                file: 0,
                                start: r.brace_line,
                                end: r.end_line,
                                col: 0,
                                start_col: root.std.saturating_sub_u(r.selector_pos.col, 1),
                                map_file: 0,
                                // Source-map: the selector's own line.
                                map_line: r.selector_pos.line,
                            }),
                            extend_base: root.std.INT_MAX(),
                        });
                    }
                    root.std.extend(out, bubbled);
                },
                let ds: root.ast.Stmt_Decl => {
                    let d = ds._0;
                    let prop = root.eval.trim_shared(self.eval_template_shared(d.property));
                    let value = self.eval_expr(d.value).to_css(self.compressed());
                    // Plain CSS has no variables, so the value node is always
                    // the value's own text (dart's `_expressionNode` fallback).
                    let value_span = self.span_at(d.value_pos);
                    out.push(root.eval.OutNode_AtDecl {
                        prop: prop,
                        value: value,
                        important: d.important,
                        custom: false,
                        lines: self.stamp(root.ast.SrcLines {
                            file: 0,
                            start: d.pos.line,
                            end: d.end_line,
                            col: 0,
                            start_col: root.std.saturating_sub_u(d.pos.col, 1),
                            map_file: 0,
                            map_line: 0,
                        }),
                        value_span: value_span,
                    });
                },
                let cds: root.ast.Stmt_CustomDecl => {
                    let d = cds._0;
                    let prop = root.eval.trim_shared(self.eval_template_shared(d.property));
                    let value = self.eval_template(d.value);
                    let value_span = self.span_at(d.value_pos);
                    out.push(root.eval.OutNode_AtDecl {
                        prop: prop,
                        value: value,
                        important: false,
                        custom: true,
                        lines: self.stamp(root.ast.SrcLines {
                            file: 0,
                            start: d.pos.line,
                            end: d.end_line,
                            col: 0,
                            start_col: root.std.saturating_sub_u(d.pos.col, 1),
                            map_file: 0,
                            map_line: 0,
                        }),
                        value_span: value_span,
                    });
                },
                let cs: root.ast.Stmt_Comment => {
                    let text = self.eval_template(cs._0);
                    let lines = self.stamp(cs._1);
                    out.push(root.eval.OutNode_Comment { _0: text, _1: lines });
                },
                let m: root.ast.Stmt_Media => {
                    let queries = self.resolve_media_queries(m.query);
                    let prelude = root.eval.serialize_media_queries(queries, self.compressed());
                    let inner = self.css_at_body(m.body, false);
                    if (inner.length() != 0) {
                        let lines = self.stamp(m.lines);
                        out.push(root.eval.OutNode_AtRule {
                            name: "media",
                            prelude: prelude,
                            body: inner,
                            has_block: true,
                            kind: root.eval.AtRuleKind.Conditional,
                            lines: lines,
                        });
                    }
                },
                let sup: root.ast.Stmt_Supports => {
                    let prelude = self.serialize_supports_condition(sup.condition);
                    let inner = self.css_at_body(sup.body, false);
                    if (inner.length() != 0) {
                        out.push(root.eval.OutNode_AtRule {
                            name: "supports",
                            prelude: prelude,
                            body: inner,
                            has_block: true,
                            kind: root.eval.AtRuleKind.Conditional,
                            lines: self.stamp(sup.lines),
                        });
                    }
                },
                let at: root.ast.Stmt_AtRule => {
                    let prelude_s = root.std.trim(self.eval_template(at.prelude));
                    let lines = self.stamp(at.lines);
                    let body = at.body;
                    if (body == null) {
                        out.push(root.eval.OutNode_AtRule {
                            name: at.name,
                            prelude: prelude_s,
                            body: [],
                            has_block: false,
                            kind: root.eval.AtRuleKind.Generic,
                            lines: lines,
                        });
                    } else {
                        let b = body;
                        let inner = self.css_at_body(b, false);
                        out.push(root.eval.OutNode_AtRule {
                            name: at.name,
                            prelude: prelude_s,
                            body: inner,
                            has_block: true,
                            kind: root.eval.AtRuleKind.Generic,
                            lines: lines,
                        });
                    }
                },
                let imp: root.ast.Stmt_Import => {
                    for (let arg in imp.args) {
                        let tp: root.std.Tuple2<string, root.scanner.Pos> = match (arg) {
                            let c: root.ast.ImportArg_Css => root.std.Tuple2 {
                                _0: self.serialize_css_import(c.url, c.modifiers),
                                _1: c.pos,
                            },
                            let sa: root.ast.ImportArg_Sass => root.std.Tuple2 {
                                _0: root.value.serialize_quoted(sa.path),
                                _1: sa.pos,
                            },
                            _ => root.std.unreachable(),
                        };
                        let text = tp._0;
                        let pos = tp._1;
                        let lines = self.map_only_lines(pos);
                        out.push(root.eval.OutNode_Raw {
                            _0: `@import${self.at_rule_gap()}${text};`,
                            _1: lines,
                        });
                    }
                },
                // `@keyframes` and a plain-CSS custom `@function` have
                // statements of their own, so they need arms of their own here:
                // falling through to `_` dropped them, and with them everything
                // they held (`@media screen {@keyframes k {from {a: b}}}` came
                // out empty, which then took the `@media` with it).
                let kf: root.ast.Stmt_Keyframes => {
                    let prelude_s = root.std.trim(self.eval_template(kf.prelude));
                    let out_body = self.css_at_body(kf.body, true);
                    let lines = self.stamp(kf.lines);
                    out.push(root.eval.OutNode_AtRule {
                        name: kf.name,
                        prelude: prelude_s,
                        body: out_body,
                        has_block: true,
                        kind: root.eval.AtRuleKind.Generic,
                        lines: lines,
                    });
                },
                let cc: root.ast.Stmt_CssCustomAtRule => {
                    let sink: root.std.Cell<root.eval.Sink> = root.std.Cell {
                        value: root.eval.Sink_AtRoot {
                            body: out,
                            group_ends: false,
                        },
                    };
                    self.eval_css_custom_at_rule(cc.name, cc.prelude, cc.body, sink);
                },
                _ => {},
            }
        }
        out
    }

    /// Build the children of a *top-level* plain-CSS style rule: declarations
    /// and nested rules stay in the block; a block at-rule (`@media` etc.)
    /// bubbles out wrapping a copy of the parent rule (dart-sass's standard
    /// at-rule bubbling — `a {@media b {c: d}}` → `@media b { a { c: d } }`).
    /// Deeper levels never bubble (see [`Evaluator::css_body`]).
    function css_rule_children(self, stmts: root.ast.Stmt[], parent_selectors: string[]) -> root.std.Tuple2<root.eval.OutItem[], root.eval.OutNode[]> {
        let items: root.eval.OutItem[] = [];
        let bubbled: root.eval.OutNode[] = [];
        let bubble = (name: string, kind: root.eval.AtRuleKind, prelude: string, inner: root.eval.OutItem[], bubbled: root.eval.OutNode[]) -> void {
            // Nothing to wrap means no copy of the parent rule, but the at-rule
            // itself still survives unless it is one of the two that go away
            // when their block is empty: `.a {@foo {}}` is `@foo {}`, while
            // `.a {@media b {}}` is nothing (see `at_rule_drops_when_empty`).
            let body: root.eval.OutNode[] = if (inner.length() == 0) {
                if (root.emit.at_rule_drops_when_empty(kind)) {
                    return;
                };
                []
            } else {
                [root.eval.OutNode_plain_rule(
                    root.std.clone_vec(parent_selectors),
                    inner,
                    root.ast.SrcLines.default(),
                )]
            };
            bubbled.push(root.eval.OutNode_AtRule {
                name: name,
                prelude: prelude,
                body: body,
                has_block: true,
                kind: kind,
                lines: root.ast.SrcLines.default(),
            });
        };
        for (let stmt in stmts) {
            match (stmt) {
                let m: root.ast.Stmt_Media => {
                    let queries = self.resolve_media_queries(m.query);
                    let prelude = root.eval.serialize_media_queries(queries, self.compressed());
                    let inner = self.css_body(m.body);
                    bubble("media", root.eval.AtRuleKind.Conditional, prelude, inner, bubbled);
                },
                let sup: root.ast.Stmt_Supports => {
                    let prelude = self.serialize_supports_condition(sup.condition);
                    let inner = self.css_body(sup.body);
                    bubble("supports", root.eval.AtRuleKind.Conditional, prelude, inner, bubbled);
                },
                // PORT: `Stmt::AtRule { body: Some(b), .. }` → a guard on `body`.
                let at: root.ast.Stmt_AtRule if at.body != null => {
                    let b = root.std.unwrap(at.body);
                    let prelude_s = root.std.trim(self.eval_template(at.prelude));
                    let inner = self.css_body(b);
                    bubble(at.name, root.eval.AtRuleKind.Generic, prelude_s, inner, bubbled);
                },
                // `@keyframes` hoists out like any other block at-rule, but
                // takes no copy of the parent selectors with it: its block holds
                // keyframe selectors, not declarations. Dropping it here lost
                // the whole rule.
                let kf: root.ast.Stmt_Keyframes => {
                    let prelude_s = root.std.trim(self.eval_template(kf.prelude));
                    let out_body = self.css_at_body(kf.body, true);
                    let lines = self.stamp(kf.lines);
                    bubbled.push(root.eval.OutNode_AtRule {
                        name: kf.name,
                        prelude: prelude_s,
                        body: out_body,
                        has_block: true,
                        kind: root.eval.AtRuleKind.Generic,
                        lines: lines,
                    });
                },
                // A custom `@function` bubbles like the at-rules above, parent
                // copy included: `.a {@function --f(--a) {result: 1}}` is
                // `@function --f(--a) {.a {result: 1 }}`. Its body holds
                // declarations rather than statements, so it is built here from
                // the same `(property, value)` pairs the at-root path uses.
                let cc: root.ast.Stmt_CssCustomAtRule => {
                    let prelude_s = self.eval_template(cc.prelude);
                    let inner = self.css_custom_decl_items(cc.body);
                    bubble(cc.name, root.eval.AtRuleKind.Generic, prelude_s, inner, bubbled);
                },
                let other => {
                    self.css_body_stmt(other, items);
                },
            }
        }
        root.std.Tuple2 { _0: items, _1: bubbled }
    }

    /// Build a plain-CSS custom at-rule's body as nested output items: each
    /// declaration is a custom property, which emits its value verbatim right
    /// after the colon, exactly as [`Self::eval_css_custom_at_rule`] writes it.
    function css_custom_decl_items(self, body: root.ast.CssCustomItem[]) -> root.eval.OutItem[] {
        self
            .css_custom_at_rule_decls(body)
            .map((pv: root.std.Tuple2<string, string>) -> root.eval.OutItem {
                root.eval.OutItem_Decl {
                    prop: pv._0,
                    value: pv._1,
                    important: false,
                    custom: true,
                    lines: root.ast.SrcLines.default(),
                    value_span: root.eval.VarSpan.default(),
                }
            })
    }

    /// Resolve a plain-CSS selector to its comma-separated parts, keeping `&`
    /// and combinators verbatim (no parent resolution), and rejecting the
    /// Sass-only selector forms that plain CSS forbids. The parts come back
    /// re-serialized the way dart's parser emits them (identifier attribute
    /// values lose their quotes, whitespace collapses), along with the
    /// source's per-complex line-break flags (`a,\nb` keeps its lines).
    function css_selectors(self, sel: root.ast.TplPiece[], top_level: bool) -> root.std.Tuple2<string[], bool[]> {
        let s = self.eval_template(sel);
        let parts: string[] = root.eval
            .split_commas(s)
            .deref()
            .map((p: string) -> string { root.std.trim(p) })
            .filter((p: string) -> bool { p != "" });
        for (let p in parts) {
            root.eval.validate_plain_css_selector(p, top_level);
        }
        let normalized: string[] = parts.map((p: string) -> string { root.eval.normalize_selector(p) });
        let linebreaks: bool[] = if (s.includes("\n")) {
            root.eval.comma_linebreaks(s, false)
        } else {
            []
        };
        root.std.Tuple2 { _0: normalized, _1: linebreaks }
    }

    /// Convert a `@keyframes` frame's selector list. A frame selector is a list
    /// of keyframe STOPS (`from`, `50%`), not of CSS selectors, and dart
    /// re-serializes the stops joined with `", "`: the author's line breaks do
    /// not survive it, none of the selector normalization applies (`+5%` is a
    /// stop, not a sibling combinator), and `from`/`to` and a percentage's
    /// exponent marker come back lowercased.
    function css_frame_selectors(self, sel: root.ast.TplPiece[]) -> string[] {
        let s = self.eval_template(sel);
        let stops: string[] = [];
        for (let part in root.eval.split_commas(s).deref()) {
            let part = root.std.trim(part);
            if (part == "") {
                continue;
            }
            // The stop grammar is `from` | `to` | `<number>%`, stricter than
            // this: dart rejects `foo`, `&` and `50 %` in a frame, where the
            // checks below only catch the Sass-only selector forms. The
            // remaining strictness gap is recorded in the plan.
            root.eval.validate_plain_css_selector(part, false);
            stops.push(root.eval.normalize_keyframe_selector(part));
        }
        stops
    }

    /// Build the body of a `@keyframes` below the bubbling level: as
    /// [`Evaluator::css_body`], except that a rule at this level is a FRAME —
    /// its selector is a stop list, and its own body nests natively.
    function css_frames_body(self, stmts: root.ast.Stmt[]) -> root.eval.OutItem[] {
        check_keyframes_body(stmts);
        let items: root.eval.OutItem[] = [];
        for (let stmt in stmts) {
            match (stmt) {
                let rs: root.ast.Stmt_Rule => {
                    let r = rs._0;
                    let selectors = self.css_frame_selectors(r.selector);
                    let inner = self.css_body(r.body);
                    // An (recursively) empty frame is invisible, like any rule.
                    if (inner.length() != 0) {
                        let lines = self.map_only_lines(r.selector_pos);
                        items.push(root.eval.OutItem_NestedRule {
                            selectors: selectors,
                            linebreaks: [],
                            items: inner,
                            lines: lines,
                        });
                    }
                },
                let other => {
                    self.css_body_stmt(other, items);
                },
            }
        }
        items
    }

    /// Build a plain-CSS rule body below the first nesting level: declarations
    /// and nested style rules with nesting preserved (`OutItem::NestedRule`),
    /// and block at-rules kept in place (`OutItem::NestedAtRule`) — dart-sass
    /// `_hasCssNesting` skips bubbling once nesting is already native.
    function css_body(self, stmts: root.ast.Stmt[]) -> root.eval.OutItem[] {
        let items: root.eval.OutItem[] = [];
        for (let stmt in stmts) {
            self.css_body_stmt(stmt, items);
        }
        items
    }

    /// Process one plain-CSS statement into rule-body items (the shared body of
    /// [`Evaluator::css_body`] and the non-bubbling arm of
    /// [`Evaluator::css_rule_children`]).
    function css_body_stmt(self, stmt: root.ast.Stmt, items: root.eval.OutItem[]) -> void {
        match (stmt) {
            let ds: root.ast.Stmt_Decl => {
                let d = ds._0;
                let prop = root.eval.trim_shared(self.eval_template_shared(d.property));
                let value = self.eval_expr(d.value).to_css(self.compressed());
                // Plain CSS has no variables, so the value node is always the
                // value's own text (dart's `_expressionNode` fallback).
                let value_span = self.span_at(d.value_pos);
                items.push(root.eval.OutItem_Decl {
                    prop: prop,
                    value: value,
                    important: d.important,
                    custom: false,
                    lines: self.stamp(root.ast.SrcLines {
                        file: 0,
                        start: d.pos.line,
                        end: d.end_line,
                        col: 0,
                        start_col: root.std.saturating_sub_u(d.pos.col, 1),
                        map_file: 0,
                        map_line: 0,
                    }),
                    value_span: value_span,
                });
            },
            let cds: root.ast.Stmt_CustomDecl => {
                let d = cds._0;
                let prop = root.eval.trim_shared(self.eval_template_shared(d.property));
                let value = self.eval_template(d.value);
                let value_span = self.span_at(d.value_pos);
                items.push(root.eval.OutItem_Decl {
                    prop: prop,
                    value: value,
                    important: false,
                    custom: true,
                    lines: self.stamp(root.ast.SrcLines {
                        file: 0,
                        start: d.pos.line,
                        end: d.end_line,
                        col: 0,
                        start_col: root.std.saturating_sub_u(d.pos.col, 1),
                        map_file: 0,
                        map_line: 0,
                    }),
                    value_span: value_span,
                });
            },
            let rs: root.ast.Stmt_Rule => {
                let r = rs._0;
                let sl = self.css_selectors(r.selector, false);
                let selectors = sl._0;
                let linebreaks = sl._1;
                let inner = self.css_body(r.body);
                // An (recursively) empty nested rule is invisible (dart-sass
                // skips childless rules when serializing).
                if (inner.length() != 0) {
                    let lines = self.map_only_lines(r.selector_pos);
                    items.push(root.eval.OutItem_NestedRule {
                        selectors: selectors,
                        linebreaks: linebreaks,
                        items: inner,
                        lines: lines,
                    });
                }
            },
            let cs: root.ast.Stmt_Comment => {
                let text = self.eval_template(cs._0);
                let lines = self.stamp(cs._1);
                items.push(root.eval.OutItem_Comment { _0: text, _1: lines });
            },
            // A nested `@import` inside a plain-CSS rule is preserved
            // verbatim, like a top-level one (see `exec_css`).
            let imp: root.ast.Stmt_Import => {
                for (let arg in imp.args) {
                    let pp: root.std.Tuple2<string, root.scanner.Pos> = match (arg) {
                        let c: root.ast.ImportArg_Css => root.std.Tuple2 {
                            _0: self.serialize_css_import(c.url, c.modifiers),
                            _1: c.pos,
                        },
                        let sa: root.ast.ImportArg_Sass => root.std.Tuple2 {
                            _0: root.value.serialize_quoted(sa.path),
                            _1: sa.pos,
                        },
                        _ => root.std.unreachable(),
                    };
                    let prelude = pp._0;
                    let pos = pp._1;
                    let lines = self.map_only_lines(pos);
                    items.push(root.eval.OutItem_ChildlessAtRule {
                        // A real CSS `@import`, whatever the parser made of its
                        // url — compressed output spells it with no gap.
                        css_import: true,
                        name: "import",
                        prelude: prelude,
                        lines: lines,
                    });
                }
            },
            let m: root.ast.Stmt_Media => {
                let queries = self.resolve_media_queries(m.query);
                let prelude = root.eval.serialize_media_queries(queries, self.compressed());
                let inner = self.css_body(m.body);
                if (inner.length() != 0) {
                    let lines = self.stamp(m.lines);
                    items.push(root.eval.OutItem_NestedAtRule {
                        name: "media",
                        prelude: prelude,
                        items: inner,
                        kind: root.eval.AtRuleKind.Conditional,
                        lines: lines,
                    });
                }
            },
            let sup: root.ast.Stmt_Supports => {
                let prelude = self.serialize_supports_condition(sup.condition);
                let inner = self.css_body(sup.body);
                if (inner.length() != 0) {
                    let lines = self.stamp(sup.lines);
                    items.push(root.eval.OutItem_NestedAtRule {
                        name: "supports",
                        prelude: prelude,
                        items: inner,
                        kind: root.eval.AtRuleKind.Conditional,
                        lines: lines,
                    });
                }
            },
            let at: root.ast.Stmt_AtRule => {
                let prelude_s = root.std.trim(self.eval_template(at.prelude));
                let body = at.body;
                if (body == null) {
                    let lines = self.stamp(at.lines);
                    items.push(root.eval.OutItem_ChildlessAtRule {
                        css_import: false,
                        name: at.name,
                        prelude: prelude_s,
                        lines: lines,
                    });
                } else {
                    let b = body;
                    let inner = self.css_body(b);
                    // An empty block below the bubbling level stays where it
                    // is, on the same terms as above: this is a generic
                    // at-rule, and only a conditional group rule goes away.
                    let lines = self.stamp(at.lines);
                    items.push(root.eval.OutItem_NestedAtRule {
                        name: at.name,
                        prelude: prelude_s,
                        items: inner,
                        kind: root.eval.AtRuleKind.Generic,
                        lines: lines,
                    });
                }
            },
            // Below the bubbling level it stays put, like any other at-rule.
            let kf: root.ast.Stmt_Keyframes => {
                let prelude_s = root.std.trim(self.eval_template(kf.prelude));
                let inner = self.css_frames_body(kf.body);
                let lines = self.stamp(kf.lines);
                items.push(root.eval.OutItem_NestedAtRule {
                    name: kf.name,
                    prelude: prelude_s,
                    items: inner,
                    kind: root.eval.AtRuleKind.Generic,
                    lines: lines,
                });
            },
            // Below the bubbling level it stays put, with no copy of the
            // parent selectors: `.a {.b {@function --f(--a) {result: 1}}}` is
            // `.a {.b {@function --f(--a) {result: 1 }}}`.
            let cc: root.ast.Stmt_CssCustomAtRule => {
                let prelude_s = self.eval_template(cc.prelude);
                let inner = self.css_custom_decl_items(cc.body);
                items.push(root.eval.OutItem_NestedAtRule {
                    name: cc.name,
                    prelude: prelude_s,
                    items: inner,
                    kind: root.eval.AtRuleKind.Generic,
                    lines: root.ast.SrcLines.default(),
                });
            },
            _ => {},
        }
    }

}

/// A style rule inside a keyframe block is invalid, and dart rejects it in plain
/// CSS exactly as it does in SCSS: `@keyframes k {from {.x {a: b}}}` is an
/// error, not output. A frame may hold declarations, comments and at-rules --
/// nothing that needs a selector of its own. Both evaluators check here, so the
/// message and the span they blame cannot drift apart.
function check_keyframes_body(body: root.ast.Stmt[]) -> void {
    for (let stmt in body) {
        if let frame_s: root.ast.Stmt_Rule = stmt {
            let frame = frame_s._0;
            for (let inner_s in frame.body) {
                if let inner_r: root.ast.Stmt_Rule = inner_s {
                    let inner = inner_r._0;
                    throw root.error.Error.at(
                        "Style rules may not be used within keyframe blocks.",
                        inner.selector_pos,
                    );
                }
            }
        }
    }
}
