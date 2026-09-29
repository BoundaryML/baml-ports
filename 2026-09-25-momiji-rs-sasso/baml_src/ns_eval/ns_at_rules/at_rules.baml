// Ported from sasso `src/eval/at_rules.rs` (namespace `root.eval.at_rules`).

interface EvaluatorAtRules {
    /// Evaluate a generic at-rule. The prelude template is resolved to a
    /// string; the body (when present) is executed so that nested rules carry
    /// the enclosing selectors INSIDE the at-rule, and the whole node hoists to
    /// the document root (bubbling).
    function eval_at_rule(
        self,
        name: string,
        prelude: root.ast.TplPiece[],
        body: root.ast.Stmt[]?,
        lines: root.ast.SrcLines,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Evaluate a plain CSS custom `@function`/`@mixin`: resolve the prelude
    /// and each body declaration (verbatim values keep their literal text;
    /// interpolated-property declarations evaluate as SassScript), then emit the
    /// whole construct verbatim as a generic at-rule.
    function eval_css_custom_at_rule(
        self,
        name: string,
        prelude: root.ast.TplPiece[],
        body: root.ast.CssCustomItem[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Resolve a plain CSS custom `@function`/`@mixin` body into
    /// `(property, everything after the colon)` pairs: a verbatim value keeps
    /// its literal text, including the whitespace the source put after the
    /// colon, while an interpolated-property declaration evaluates as
    /// SassScript and takes dart's OPTIONAL space — which is the whole
    /// difference between the two kinds of value here, since compressed output
    /// writes none of it (`#{result}: 1 + 1` compresses to `result:2` where
    /// `result: 1 + 1` keeps the space it was written with).
    ///
    /// Both the at-root path above and the plain-CSS evaluator's nested paths
    /// (`OutItem::Decl` with `custom: true`, which also emits its value
    /// verbatim after the colon) build their nodes from these pairs, so the
    /// bytes cannot drift between them.
    function css_custom_at_rule_decls(
        self,
        body: root.ast.CssCustomItem[],
    ) -> root.std.Tuple2<string, string>[] throws unknown;

    /// Run an at-rule body, producing its output node list. When the at-rule
    /// is nested under a style rule, bare declarations are wrapped in the
    /// enclosing selectors; at the document root they emit directly.
    function eval_at_body(
        self,
        stmts: root.ast.Stmt[],
        parents: string[],
    ) -> root.eval.OutNode[] throws unknown;

    /// Evaluate `@media`: resolve the query list (SassScript inside feature
    /// values is evaluated), merge with any enclosing `@media`, run the body
    /// carrying enclosing selectors inside, then emit the at-rule (which bubbles
    /// to the document root). An empty body produces no output.
    function eval_media(
        self,
        query: root.ast.MediaQueryList,
        body: root.ast.Stmt[],
        lines: root.ast.SrcLines,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Resolve a parsed media query list to its final string components,
    /// evaluating SassScript inside feature values.
    function resolve_media_queries(
        self,
        list: root.ast.MediaQueryList,
    ) -> root.eval.ResolvedQuery[] throws unknown;

    function resolve_media_query(
        self,
        q: root.ast.MediaQuery,
    ) -> root.eval.ResolvedQuery throws unknown;

    function resolve_conditions(self, conds: root.ast.MediaInParens[]) -> string[] throws unknown;

    function serialize_media_in_parens(self, c: root.ast.MediaInParens) -> string throws unknown;

    function serialize_media_feature(self, f: root.ast.MediaFeature) -> string throws unknown;

    /// Evaluate `@supports <condition> { body }`: serialize the structured
    /// condition canonically, run the body (bubbling like any at-rule), and emit
    /// the node — skipping emission entirely when the body produces nothing
    /// (dart-sass drops an empty/invisible `@supports`).
    function eval_supports(
        self,
        condition: root.ast.SupportsCondition,
        body: root.ast.Stmt[],
        lines: root.ast.SrcLines,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Serialize a `@supports` condition to its canonical CSS string
    /// (dart-sass `_visitSupportsCondition`).
    function serialize_supports_condition(
        self,
        condition: root.ast.SupportsCondition,
    ) -> string throws unknown;

    /// Serialize a plain-CSS `@import` argument: the URL template followed by
    /// its canonical modifiers. Raw identifier/function runs join with single
    /// spaces; a `supports(<query>)` re-serializes its parsed condition (a
    /// declaration's own parens double as the call parens); the terminal media
    /// query list joins with `, ` when it continued a bare-identifier query.
    function serialize_css_import(
        self,
        url: root.ast.TplPiece[],
        modifiers: root.ast.ImportModifier[],
    ) -> string throws unknown;

    /// dart-sass `_writeOptionalSpace`: a single space in every style but
    /// compressed, where it is exactly the byte a minifier exists to drop.
    function optional_space(self) -> string throws unknown;

    /// The space between an at-rule's name and its prelude, which compressed
    /// output does not write for a CSS `@import`.
    function at_rule_gap(self) -> string throws unknown;

    /// dart-sass `_writeImportUrl`: compressed output unwraps a `url(…)` to
    /// save the four bytes of the wrapper, quoting the contents unless they
    /// already carry a quote. Any other url — a quoted string already — is
    /// written exactly as it was spelled, in either style.
    function import_url_css(self, url: string) -> string throws unknown;

    /// dart-sass `_parenthesize`: wrap a sub-condition in parentheses when it is
    /// a negation, or an operation whose operator differs from the surrounding
    /// one (or there is no surrounding operator).
    function parenthesize_supports(
        self,
        condition: root.ast.SupportsCondition,
        operator: root.ast.Conjunction?,
    ) -> string throws unknown;

    /// Evaluate `@keyframes`. The frame selectors are keyframe selectors, not
    /// CSS selectors: no `&`/parent resolution. We run the body with the parent
    /// context reset to root (empty parents), so frame blocks emit verbatim.
    /// The whole node bubbles to the document root like any other at-rule.
    function eval_keyframes(
        self,
        name: string,
        prelude: root.ast.TplPiece[],
        body: root.ast.Stmt[],
        lines: root.ast.SrcLines,
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Evaluate `@at-root`: hoist the body's output to the document root. The
    /// parent-selector context is KEPT — dart resolves `&` against the
    /// enclosing rule but disables the implicit parent join
    /// (`implicitParent: !_atRootExcludingStyleRule`), so `@at-root & {…}`
    /// re-emits the parent at the root while `@at-root .x {…}` stays `.x`.
    /// The optional query is accepted but not yet honoured (the common
    /// no-query case is supported).
    function eval_at_root(
        self,
        query: root.ast.TplPiece[]?,
        body: root.ast.Stmt[],
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;
}

implements EvaluatorAtRules for root.eval.Evaluator {
    /// Evaluate a generic at-rule. The prelude template is resolved to a
    /// string; the body (when present) is executed so that nested rules carry
    /// the enclosing selectors INSIDE the at-rule, and the whole node hoists to
    /// the document root (bubbling).
    function eval_at_rule(self, name: string, prelude: root.ast.TplPiece[], body: root.ast.Stmt[]?, lines: root.ast.SrcLines, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        let prelude = self.eval_template(prelude);
        if (body == null) {
            // dart-sass strips a top-level (or bubbled-out) `@charset` entirely,
            // but keeps one that appears inside a style rule's block.
            if (name == "charset" && !sink.value.is_rule()) {
                return;
            }
            sink.value.push_childless_at_rule(name, prelude, lines);
            return;
        }
        let stmts = body;
        // `@font-face` (exactly, case-sensitively, unprefixed) holds plain
        // declarations: dart-sass does NOT carry the enclosing style-rule
        // selector into its body — `a { @font-face { d: e } }` emits a bare
        // `@font-face { d: e }`. Every other at-rule (including `@page`,
        // `@-moz-font-face`, and unknown directives) wraps its body in the
        // enclosing selector — UNLESS we're directly inside `@at-root`,
        // where there is no style rule to wrap with (dart's _styleRule is
        // null even though `&` still resolves).
        let body_parents: string[] = if (name == "font-face" || self.at_root_excluding_style_rule) {
            []
        } else {
            parents
        };
        // dart `_inUnknownAtRule`: every at-rule without a dedicated visitor
        // (this generic path) sets the flag for its body, legalizing bare
        // declarations in nested contexts that would otherwise reject them
        // (a `@media` directly inside `@utility`).
        let saved_unknown = self.in_unknown_at_rule;
        self.in_unknown_at_rule = true;
        // PORT: a `Result` held across cleanup (`let r = …; cleanup; r?`) is caught
        // into a `root.error.Error?` local and re-thrown after the cleanup.
        let out_body_err: root.error.Error? = null;
        let out_body: root.eval.OutNode[] = self.eval_at_body(stmts, body_parents) catch (e) {
            let err: root.error.Error => {
                out_body_err = err;
                []
            }
        };
        self.in_unknown_at_rule = saved_unknown;
        if (out_body_err != null) {
            throw out_body_err;
        }
        sink.value.push_at_rule(root.eval.OutNode_AtRule {
            name: name,
            prelude: prelude,
            body: out_body,
            has_block: true,
            // The generic path: every at-rule without a visitor of its own
            // comes through here, and so does every INTERPOLATED name, which is
            // why a `@#{"media"}` node is generic however its name reads.
            kind: root.eval.AtRuleKind.Generic,
            lines: lines,
        });
    }

    /// Evaluate a plain CSS custom `@function`/`@mixin`: resolve the prelude
    /// and each body declaration (verbatim values keep their literal text;
    /// interpolated-property declarations evaluate as SassScript), then emit the
    /// whole construct verbatim as a generic at-rule.
    function eval_css_custom_at_rule(self, name: string, prelude: root.ast.TplPiece[], body: root.ast.CssCustomItem[], sink: root.std.Cell<root.eval.Sink>) -> void {
        let prelude = self.eval_template(prelude);
        let out_body: root.eval.OutNode[] = self
            .css_custom_at_rule_decls(body)
            .map((pv: root.std.Tuple2<string, string>) -> root.eval.OutNode {
                root.eval.OutNode_Raw { _0: `${pv._0}:${pv._1};`, _1: root.ast.SrcLines.default() }
            });
        sink.value.push_at_rule(root.eval.OutNode_AtRule {
            name: name,
            prelude: prelude,
            body: out_body,
            has_block: true,
            kind: root.eval.AtRuleKind.Generic,
            lines: root.ast.SrcLines.default(),
        });
    }

    /// Resolve a plain CSS custom `@function`/`@mixin` body into
    /// `(property, everything after the colon)` pairs: a verbatim value keeps
    /// its literal text, including the whitespace the source put after the
    /// colon, while an interpolated-property declaration evaluates as
    /// SassScript and takes dart's OPTIONAL space — which is the whole
    /// difference between the two kinds of value here, since compressed output
    /// writes none of it (`#{result}: 1 + 1` compresses to `result:2` where
    /// `result: 1 + 1` keeps the space it was written with).
    ///
    /// Both the at-root path above and the plain-CSS evaluator's nested paths
    /// (`OutItem::Decl` with `custom: true`, which also emits its value
    /// verbatim after the colon) build their nodes from these pairs, so the
    /// bytes cannot drift between them.
    function css_custom_at_rule_decls(self, body: root.ast.CssCustomItem[]) -> root.std.Tuple2<string, string>[] {
        let decls: root.std.Tuple2<string, string>[] = [];
        for (let item in body) {
            let prop = self.eval_template(item.property);
            match (item.value) {
                let raw_v: root.ast.CssCustomValue_Raw => {
                    let raw = self.eval_template(raw_v._0);
                    decls.push(root.std.Tuple2 { _0: prop, _1: raw });
                },
                let script: root.ast.CssCustomValue_Script => {
                    let gap = self.optional_space();
                    let value = self.eval_expr(script._0).to_css(self.compressed());
                    decls.push(root.std.Tuple2 { _0: prop, _1: `${gap}${value}` });
                },
                // A nested property set on an interpolated property: each
                // child emits as `property-suffix: value`.
                let set: root.ast.CssCustomValue_Set => {
                    let gap = self.optional_space();
                    for (let child in set._0) {
                        let suffix = child._0;
                        let expr = child._1;
                        let sfx = self.eval_template(suffix);
                        let value = self.eval_expr(expr).to_css(self.compressed());
                        decls.push(root.std.Tuple2 { _0: `${prop}-${sfx}`, _1: `${gap}${value}` });
                    }
                },
                _ => root.std.unreachable(),
            }
        }
        decls
    }

    /// Run an at-rule body, producing its output node list. When the at-rule
    /// is nested under a style rule, bare declarations are wrapped in the
    /// enclosing selectors; at the document root they emit directly.
    function eval_at_body(self, stmts: root.ast.Stmt[], parents: string[]) -> root.eval.OutNode[] {
        self.push_scope(false);
        // The at-rule body's trailing-invisible tracking is its own; the
        // exec arm that called us reports the at-rule itself to the parent.
        let saved_last_invisible = self.last_child_invisible;
        self.last_child_invisible = false;
        let body: root.eval.OutNode[] = [];
        // PORT: the `Result` of the branch below is caught into `result` and
        // re-thrown after the cleanup.
        let result: root.error.Error? = null;
        if (parents.length() == 0) {
            let child: root.std.Cell<root.eval.Sink> = root.std.Cell {
                value: root.eval.Sink_AtRoot {
                    body: body,
                    group_ends: false,
                },
            };
            self.exec(stmts, [], child) catch (e) {
                let err: root.error.Error => {
                    result = err;
                }
            };
        } else {
            let items: root.eval.OutItem[] = [];
            let nested: root.eval.OutNode[] = [];
            let flushed: int? = null;
            let at_depth = self.at_rule_ctx.length();
            // The wrap re-emits the enclosing selectors, and dart preserves
            // their source line structure inside the hoisted at-rule copy too
            // (`h1,\n.alpha { @include has-media; }`) — carry the enclosing
            // rule's linebreaks when they line up with `parents`.
            let wrap_linebreaks: bool[] = if (self.current_linebreaks.length() == parents.length()) {
                root.std.clone_vec(self.current_linebreaks)
            } else {
                []
            };
            // The wrap re-emits the enclosing selectors, and on the common shape
            // those still ARE the enclosing rule's shared list — so the wrap can
            // hand a refcount to every block it flushes instead of copying the
            // list again. `Borrowed` is for the shapes where the rule replaced
            // `current_selector` with a different list (`@at-root`, a plain-CSS
            // shell) and the slice is all this body has.
            // PORT: `std::ptr::eq(sel.as_slice(), parents)` → `[sel].includes(parents)`
            // (`Array.includes` compares array elements by identity).
            let wrap_shared: string[]? = null;
            let cur_sel = self.current_selector;
            if (cur_sel != null) {
                if ([cur_sel].includes(parents)) {
                    wrap_shared = cur_sel;
                }
            }
            {
                let selectors: root.eval.SinkSelectors = if (wrap_shared != null) {
                    root.eval.SinkSelectors_Shared { _0: wrap_shared }
                } else {
                    root.eval.SinkSelectors_Borrowed { _0: parents }
                };
                // PORT: the sink borrowed `items`, `nested` and `flushed` as `&mut`;
                // here it holds them, and `nested` is read back from it below.
                let child_rule = root.eval.Sink_Rule {
                    selectors: selectors,
                    linebreaks: wrap_linebreaks,
                    // The wrap re-uses the enclosing selectors, so it has no
                    // source rule of its own: `file`/`start`/`end` stay 0 to keep
                    // the trailing-comment rule disabled. For SOURCE MAPS only it
                    // carries the enclosing rule's selector position in the
                    // map-override fields, so the bubbled parent selector maps
                    // back to the ORIGINAL rule's span (dart parity). No CSS effect.
                    lines: root.ast.SrcLines {
                        ...root.ast.SrcLines.default(),
                        map_file: self.cur_rule_lines.file,
                        map_line: self.cur_rule_lines.mapped_line(),
                        start_col: self.cur_rule_lines.start_col,
                    },
                    items: items,
                    nested: nested,
                    at_depth: at_depth,
                    flushed: flushed,
                    // Inherit the enclosing rule's addSelector timing: the
                    // wrapped copy exists from the moment the rule ran, so
                    // pre-registered extensions apply one-shot to it too
                    // (govuk's contextual rules inside their @media copies).
                    extend_base: self.cur_rule_extend_base,
                };
                let child: root.std.Cell<root.eval.Sink> = root.std.Cell { value: child_rule };
                self.exec(stmts, parents, child) catch (e) {
                    let err: root.error.Error => {
                        result = err;
                    }
                };
                if (result == null) {
                    let _ = child.value.flush_rule_block();
                }
                nested = child_rule.nested;
            }
            if (result == null) {
                root.std.extend(body, nested);
            }
        }
        self.pop_scope();
        self.last_child_invisible = saved_last_invisible;
        if (result != null) {
            throw result;
        }
        body
    }

    /// Evaluate `@media`: resolve the query list (SassScript inside feature
    /// values is evaluated), merge with any enclosing `@media`, run the body
    /// carrying enclosing selectors inside, then emit the at-rule (which bubbles
    /// to the document root). An empty body produces no output.
    function eval_media(self, query: root.ast.MediaQueryList, body: root.ast.Stmt[], lines: root.ast.SrcLines, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // Without an enclosing style rule, a bare declaration directly inside a
        // media block is invalid (dart-sass: "expected \"{\".") — only rules and
        // at-rules may appear there. With a style rule, declarations belong to
        // its selector and are allowed — and inside an UNKNOWN at-rule dart's
        // parser context (`_inUnknownAtRule`) legalizes them too
        // (`@utility x { @media (…) { max-width: …; } }`, Tailwind v4).
        if (parents.length() == 0 && !self.in_unknown_at_rule) {
            for (let stmt in body) {
                if (stmt is root.ast.Stmt_Decl) {
                    throw root.error.Error.unpositioned("expected \"{\".");
                }
            }
        }

        let queries = self.resolve_media_queries(query);

        // Inside a keyframe block an at-rule nests verbatim: the frame is not
        // a style rule in dart-sass, so there is no bubbling/wrapping.
        if (self.in_keyframes && sink.value.is_rule()) {
            let prelude = root.eval.serialize_media_queries(queries, self.compressed());
            let out_body = self.eval_at_body(body, []);
            sink.value.push_item(root.eval.OutItem_NestedAtRule {
                name: "media",
                prelude: prelude,
                items: root.eval.at_body_to_items(out_body),
                kind: root.eval.AtRuleKind.Conditional,
                lines: lines,
            });
            return;
        }

        // Merge with the enclosing media context (dart-sass `_mergeMediaQueries`).
        let merged: root.eval.ResolvedQuery[]? = null;
        if (self.media_queries.length() != 0) {
            let other = root.eval.merge_media_query_lists(self.media_queries, queries);
            if (other != null) {
                // Mutually exclusive everywhere — emit nothing.
                if (other.length() == 0) {
                    return;
                }
            }
            merged = other;
        }

        // Children see the merged queries when mergeable, else just our own.
        let child_queries: root.eval.ResolvedQuery[] = if (merged != null) {
            root.std.clone_vec(merged)
        } else {
            root.std.clone_vec(queries)
        };
        // The emitted node carries the merged queries (when mergeable) and
        // bubbles past the enclosing media; otherwise it stays nested.
        let bubble_out = merged != null;
        let node_queries = if (bubble_out) {
            child_queries
        } else {
            queries
        };
        let prelude = root.eval.serialize_media_queries(node_queries, self.compressed());

        let enclosing = self.media_queries.length() != 0;
        let saved = self.media_queries;
        self.media_queries = child_queries;
        let saved_hoist = self.media_hoist;
        self.media_hoist = [];
        let own_depth = self.at_rule_ctx.length();
        self.at_rule_ctx.push(root.eval.AtCtx_Media {
            prelude: prelude,
        });
        // PORT: the body's `Result` is caught and re-thrown after the cleanup.
        let out_body_err: root.error.Error? = null;
        let out_body: root.eval.OutNode[] = self.eval_at_body(body, parents) catch (e) {
            let err: root.error.Error => {
                out_body_err = err;
                []
            }
        };
        let _ = self.at_rule_ctx.pop();
        self.media_queries = saved;
        let hoisted = self.media_hoist;
        self.media_hoist = saved_hoist;
        if (out_body_err != null) {
            throw out_body_err;
        }

        // Split the body at the hoist markers nested mergeable media rules
        // left behind: each marker interleaves the bubbled rule at its source
        // position, slicing this rule's own children into segments around it
        // (dart-sass#453 keeps source order).
        let result: root.eval.OutNode[] = [];
        let segment: root.eval.OutNode[] = [];
        // PORT: `hoisted.drain(..)` iterator → an index cursor into `hoisted`.
        let hoist_idx = 0;
        let flush = (segment: root.eval.OutNode[], result: root.eval.OutNode[], prelude: string) -> void {
            if (segment.length() != 0) {
                result.push(root.eval.OutNode_AtRule {
                    name: "media",
                    prelude: prelude,
                    body: root.std.take_all(segment),
                    has_block: true,
                    kind: root.eval.AtRuleKind.Conditional,
                    lines: lines,
                });
            }
        };
        for (let n in out_body) {
            let at_root_target: int? = match (n) {
                let h: root.eval.OutNode_AtRootHoist => h.target,
                _ => null,
            };
            if (n is root.eval.OutNode_MediaHoist) {
                flush(segment, result, prelude);
                if (hoist_idx < hoisted.length()) {
                    let batch = hoisted[hoist_idx];
                    hoist_idx += 1;
                    root.std.extend(result, batch);
                }
            } else if (at_root_target != null) {
                let t = at_root_target;
                if (t == own_depth + 1) {
                    // The batch grafts INTO this rule's own body (dart adds
                    // it to the existing node at its current end): it joins
                    // the current segment in place, splitting nothing.
                    let b = self.at_root_hoist.shift();
                    if (b != null) {
                        // debug_assert_eq!(b.target, t);
                        root.std.extend(segment, b.nodes);
                    }
                } else if (own_depth == 0) {
                    // A root-bound batch: split around it, placing it just
                    // after this rule's current segment at the root.
                    flush(segment, result, prelude);
                    let b = self.at_root_hoist.shift();
                    if (b != null) {
                        // debug_assert_eq!(b.target, t);
                        root.std.extend(result, b.nodes);
                        let marker: root.eval.OutNode = if (b.group_end) {
                            root.eval.OutNode_GroupEnd {}
                        } else {
                            root.eval.OutNode_AtRootPackTight {}
                        };
                        result.push(marker);
                    }
                } else {
                    // Bound further out: split and pass the marker outward.
                    flush(segment, result, prelude);
                    result.push(n);
                }
            } else {
                segment.push(n);
            }
        }
        // PORT: `drop(hoist_iter)` drained the rest of `hoisted` (a local) — nothing to do.
        flush(segment, result, prelude);
        if (result.length() == 0) {
            return;
        }

        // A mergeable rule nested in another media bubbles the whole batch
        // out through the enclosing rule (leaving a marker at this source
        // position); otherwise emit in place.
        if (bubble_out && enclosing) {
            sink.value.push_at_rule(root.eval.OutNode_MediaHoist {});
            self.media_hoist.push(result);
        } else {
            for (let n in result) {
                sink.value.push_at_rule(n);
            }
        }
    }

    /// Resolve a parsed media query list to its final string components,
    /// evaluating SassScript inside feature values.
    function resolve_media_queries(self, list: root.ast.MediaQueryList) -> root.eval.ResolvedQuery[] {
        let out: root.eval.ResolvedQuery[] = [];
        for (let q in list.queries) {
            out.push(self.resolve_media_query(q));
        }
        // dart-sass re-parses the RESOLVED prelude text (CssMediaQuery
        // .parseList), so interpolation may span query boundaries
        // (`scr#{"een, pri"}nt` splits into two queries). Only a prelude that
        // actually contained interpolation needs the round-trip.
        if (list.queries.some((q: root.ast.MediaQuery) -> bool { root.eval.media_query_has_interp(q) })) {
            let text = root.eval.serialize_media_queries(out, self.compressed());
            return root.eval.css_media_parse_list(text);
        }
        out
    }

    function resolve_media_query(self, q: root.ast.MediaQuery) -> root.eval.ResolvedQuery {
        match (q) {
            let t: root.ast.MediaQuery_Type => {
                let mtype = self.eval_template(t.mtype);
                let modifier_t = t.modifier;
                let modifier: string? = if (modifier_t != null) {
                    self.eval_template(modifier_t)
                } else {
                    null
                };
                let conditions = self.resolve_conditions(t.conditions);
                root.eval.ResolvedQuery {
                    modifier: modifier,
                    mtype: mtype,
                    conditions: conditions,
                    conjunction_and: true,
                }
            },
            let c: root.ast.MediaQuery_Condition => root.eval.ResolvedQuery {
                modifier: null,
                mtype: null,
                conditions: self.resolve_conditions(c.conditions),
                conjunction_and: c.conjunction == root.ast.Conjunction.And,
            },
            _ => root.std.unreachable(),
        }
    }

    function resolve_conditions(self, conds: root.ast.MediaInParens[]) -> string[] {
        let out: string[] = [];
        for (let c in conds) {
            out.push(self.serialize_media_in_parens(c));
        }
        out
    }

    function serialize_media_in_parens(self, c: root.ast.MediaInParens) -> string {
        match (c) {
            let f: root.ast.MediaInParens_Feature => {
                let inner = self.serialize_media_feature(f._0);
                `(${inner})`
            },
            let n: root.ast.MediaInParens_Not => `not ${self.serialize_media_in_parens(n._0)}`,
            let g: root.ast.MediaInParens_Group => {
                let parts = self.resolve_conditions(g.conditions);
                let sep = if (g.conjunction == root.ast.Conjunction.And) {
                    " and "
                } else {
                    " or "
                };
                `(${parts.join(sep)})`
            },
            let i: root.ast.MediaInParens_Interp => {
                let v = self.eval_expr(i._0);
                root.eval.interp_checked(v)
            },
            _ => root.std.unreachable(),
        }
    }

    function serialize_media_feature(self, f: root.ast.MediaFeature) -> string {
        match (f) {
            let d: root.ast.MediaFeature_Decl => {
                // Media-feature names and values serialize in interpolation
                // context: a quoted string unquotes (`("min-width:#{$w}")`
                // emits `(min-width:20px)`), numbers are unchanged.
                let n = root.eval.interp_checked(self.eval_expr(d.name));
                let value = d.value;
                if (value != null) {
                    let val = root.eval.interp_checked(self.eval_expr(value));
                    `${n}: ${val}`
                } else {
                    n
                }
            },
            let r: root.ast.MediaFeature_Range => {
                let a = self.eval_expr(r.first).to_css(self.compressed());
                let b = self.eval_expr(r.second).to_css(self.compressed());
                let s = `${a} ${r.op1} ${b}`;
                let rest = r.rest;
                if (rest != null) {
                    let op2 = rest._0;
                    let third = rest._1;
                    let c = self.eval_expr(third).to_css(self.compressed());
                    s = s + ` ${op2} ${c}`;
                }
                s
            },
            _ => root.std.unreachable(),
        }
    }

    /// Evaluate `@supports <condition> { body }`: serialize the structured
    /// condition canonically, run the body (bubbling like any at-rule), and emit
    /// the node — skipping emission entirely when the body produces nothing
    /// (dart-sass drops an empty/invisible `@supports`).
    function eval_supports(self, condition: root.ast.SupportsCondition, body: root.ast.Stmt[], lines: root.ast.SrcLines, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        let prelude = self.serialize_supports_condition(condition);
        let own_depth = self.at_rule_ctx.length();
        self.at_rule_ctx.push(root.eval.AtCtx_Supports {
            prelude: prelude,
        });
        // PORT: the body's `Result` is caught and re-thrown after the cleanup.
        let out_body_err: root.error.Error? = null;
        let out_body: root.eval.OutNode[] = self.eval_at_body(body, parents) catch (e) {
            let err: root.error.Error => {
                out_body_err = err;
                []
            }
        };
        let _ = self.at_rule_ctx.pop();
        if (out_body_err != null) {
            throw out_body_err;
        }
        if (out_body.length() == 0) {
            return;
        }
        // Split around any escaping @at-root batches (markers), wrapping each
        // segment in its own @supports copy like dart's tree rebuild.
        let result: root.eval.OutNode[] = [];
        let segment: root.eval.OutNode[] = [];
        let flush = (segment: root.eval.OutNode[], result: root.eval.OutNode[]) -> void {
            if (segment.length() != 0) {
                result.push(root.eval.OutNode_AtRule {
                    name: "supports",
                    prelude: prelude,
                    body: root.std.take_all(segment),
                    has_block: true,
                    kind: root.eval.AtRuleKind.Conditional,
                    lines: lines,
                });
            }
        };
        for (let n in out_body) {
            let at_root_target: int? = match (n) {
                let h: root.eval.OutNode_AtRootHoist => h.target,
                _ => null,
            };
            if (at_root_target != null) {
                let t = at_root_target;
                if (t == own_depth + 1) {
                    // Grafts INTO this rule's own body: joins the current
                    // segment in place (dart appends to the existing node).
                    let b = self.at_root_hoist.shift();
                    if (b != null) {
                        root.std.extend(segment, b.nodes);
                    }
                } else if (own_depth == 0) {
                    flush(segment, result);
                    let b = self.at_root_hoist.shift();
                    if (b != null) {
                        root.std.extend(result, b.nodes);
                        let marker: root.eval.OutNode = if (b.group_end) {
                            root.eval.OutNode_GroupEnd {}
                        } else {
                            root.eval.OutNode_AtRootPackTight {}
                        };
                        result.push(marker);
                    }
                } else {
                    flush(segment, result);
                    result.push(n);
                }
            } else {
                segment.push(n);
            }
        }
        flush(segment, result);
        for (let n in result) {
            sink.value.push_at_rule(n);
        }
    }

    /// Serialize a `@supports` condition to its canonical CSS string
    /// (dart-sass `_visitSupportsCondition`).
    function serialize_supports_condition(self, condition: root.ast.SupportsCondition) -> string {
        match (condition) {
            let o: root.ast.SupportsCondition_Operation => {
                let l = self.parenthesize_supports(o.left, o.op);
                let r = self.parenthesize_supports(o.right, o.op);
                let word = if (o.op == root.ast.Conjunction.And) {
                    "and"
                } else {
                    "or"
                };
                `${l} ${word} ${r}`
            },
            let neg: root.ast.SupportsCondition_Negation => `not ${self.parenthesize_supports(neg._0, null)}`,
            let interp: root.ast.SupportsCondition_Interpolation => root.eval.interp_checked(self.eval_expr(interp._0)),
            let d: root.ast.SupportsCondition_Declaration => {
                // dart-sass evaluates BOTH the name and the value with
                // `_inSupportsDeclaration` set, so a calc in the name
                // (`(calc(0): a)`) is also kept unsimplified.
                let saved = self.in_supports_declaration;
                self.in_supports_declaration = true;
                let result_fn = () -> root.std.Tuple2<string, string> {
                    let n = self.eval_expr(d.name).to_css(self.compressed());
                    let v = match (d.value) {
                        let e: root.ast.SupportsValue_Expr => self.eval_expr(e._0).to_css(self.compressed()),
                        // A custom-property value is an unquoted string: resolve
                        // its interpolation, then apply unquoted-string
                        // serialization (`\n` -> space, post-newline spaces
                        // dropped), matching dart-sass `_visitUnquotedString`.
                        let tpl: root.ast.SupportsValue_Raw => root.eval.unquoted_string_css(self.eval_template(tpl._0)),
                        _ => root.std.unreachable(),
                    };
                    root.std.Tuple2 { _0: n, _1: v }
                };
                // PORT: the closure's `Result` → restore the flag in the catch
                // arm before re-throwing, and after the call on success.
                let result = result_fn() catch (e) {
                    let err: root.error.Error => {
                        self.in_supports_declaration = saved;
                        throw err;
                    }
                };
                self.in_supports_declaration = saved;
                let n = result._0;
                let v = result._1;
                let sep = if (d.custom) {
                    ""
                } else {
                    " "
                };
                `(${n}:${sep}${v})`
            },
            let func: root.ast.SupportsCondition_Function => {
                let n = self.eval_template(func.name);
                let args = self.eval_template(func.arguments);
                `${n}(${args})`
            },
            let any: root.ast.SupportsCondition_Anything => {
                let inner = self.eval_template(any._0);
                `(${inner})`
            },
            _ => root.std.unreachable(),
        }
    }

    /// Serialize a plain-CSS `@import` argument: the URL template followed by
    /// its canonical modifiers. Raw identifier/function runs join with single
    /// spaces; a `supports(<query>)` re-serializes its parsed condition (a
    /// declaration's own parens double as the call parens); the terminal media
    /// query list joins with `, ` when it continued a bare-identifier query.
    function serialize_css_import(self, url: root.ast.TplPiece[], modifiers: root.ast.ImportModifier[]) -> string {
        let url_text = self.eval_template(url);
        let out = self.import_url_css(url_text);
        // Compressed output drops the ONE separator between the url and the
        // modifiers (dart's `_writeOptionalSpace`); the modifiers keep the
        // spaces they hold between themselves.
        let first = true;
        for (let m in modifiers) {
            let sep = if (first && self.compressed()) {
                ""
            } else {
                " "
            };
            first = false;
            match (m) {
                let raw: root.ast.ImportModifier_Raw => {
                    out = out + sep;
                    out = out + self.eval_template(raw._0);
                },
                let sup: root.ast.ImportModifier_Supports => {
                    out = out + sep;
                    // The condition is an *expression* part of the modifiers
                    // interpolation in dart-sass (a `SupportsExpression` whose
                    // value is an unquoted string), so its serialized text gets
                    // the unquoted-string newline collapse — unlike a Raw
                    // modifier, which is verbatim buffer text.
                    let inner = root.eval.unquoted_string_css(self.serialize_supports_condition(sup.condition));
                    if (sup.declaration) {
                        out = out + `supports${inner}`;
                    } else {
                        out = out + `supports(${inner})`;
                    }
                },
                let media: root.ast.ImportModifier_Media => {
                    let lead = if (media.comma_before) {
                        ", "
                    } else {
                        sep
                    };
                    out = out + lead;
                    let queries = self.resolve_media_queries(media.list);
                    // An import's modifiers are ONE STRING in dart-sass,
                    // spelled by the PARSER and written verbatim by
                    // `visitCssImport` — the media-rule serializer, and so the
                    // compressed media-query form, is never reached from here.
                    out = out + root.eval.serialize_import_media_queries(queries);
                },
                _ => root.std.unreachable(),
            }
        }
        out
    }

    /// dart-sass `_writeOptionalSpace`: a single space in every style but
    /// compressed, where it is exactly the byte a minifier exists to drop.
    function optional_space(self) -> string {
        if (self.compressed()) {
            ""
        } else {
            " "
        }
    }

    /// The space between an at-rule's name and its prelude, which compressed
    /// output does not write for a CSS `@import`.
    function at_rule_gap(self) -> string {
        if (self.compressed()) {
            ""
        } else {
            " "
        }
    }

    /// dart-sass `_writeImportUrl`: compressed output unwraps a `url(…)` to
    /// save the four bytes of the wrapper, quoting the contents unless they
    /// already carry a quote. Any other url — a quoted string already — is
    /// written exactly as it was spelled, in either style.
    function import_url_css(self, url: string) -> string {
        if (!self.compressed() || !url.starts_with("u")) {
            return url;
        }
        let stripped = root.std.strip_prefix(url, "url(");
        let inner: string? = if (stripped != null) {
            root.std.strip_suffix(stripped, ")")
        } else {
            null
        };
        if (inner == null) {
            return url;
        }
        if (inner.starts_with("\"") || inner.starts_with("'")) {
            inner
        } else {
            root.value.serialize_quoted_styled(inner, true)
        }
    }

    /// dart-sass `_parenthesize`: wrap a sub-condition in parentheses when it is
    /// a negation, or an operation whose operator differs from the surrounding
    /// one (or there is no surrounding operator).
    function parenthesize_supports(self, condition: root.ast.SupportsCondition, operator: root.ast.Conjunction?) -> string {
        let needs_parens = match (condition) {
            root.ast.SupportsCondition_Negation {} => true,
            let o: root.ast.SupportsCondition_Operation => {
                if (operator == null) {
                    true
                } else {
                    operator != o.op
                }
            },
            _ => false,
        };
        let inner = self.serialize_supports_condition(condition);
        if (needs_parens) {
            `(${inner})`
        } else {
            inner
        }
    }

    /// Evaluate `@keyframes`. The frame selectors are keyframe selectors, not
    /// CSS selectors: no `&`/parent resolution. We run the body with the parent
    /// context reset to root (empty parents), so frame blocks emit verbatim.
    /// The whole node bubbles to the document root like any other at-rule.
    function eval_keyframes(self, name: string, prelude: root.ast.TplPiece[], body: root.ast.Stmt[], lines: root.ast.SrcLines, sink: root.std.Cell<root.eval.Sink>) -> void {
        // A style rule nested inside a keyframe block is invalid; each frame
        // (a top-level rule in the body) may only hold declarations. The
        // plain-CSS evaluator checks the same thing on the same statements, so
        // the check itself lives in one place.
        root.eval.plain_css.check_keyframes_body(body);
        let prelude = self.eval_template(prelude);
        let saved_kf = self.in_keyframes;
        self.in_keyframes = true;
        let own_depth = self.at_rule_ctx.length();
        self.at_rule_ctx.push(root.eval.AtCtx_Keyframes {
            name: name,
            prelude: prelude,
        });
        // PORT: the body's `Result` is caught and re-thrown after the cleanup.
        let out_body_err: root.error.Error? = null;
        let out_body: root.eval.OutNode[] = self.eval_at_body(body, []) catch (e) {
            let err: root.error.Error => {
                out_body_err = err;
                []
            }
        };
        let _ = self.at_rule_ctx.pop();
        self.in_keyframes = saved_kf;
        if (out_body_err != null) {
            throw out_body_err;
        }
        // Pull any escaping @at-root batches out (the keyframes shell stays,
        // even empty: `@keyframes a {}` + the hoisted rules after it).
        let shell: root.eval.OutNode[] = [];
        let after: root.eval.OutNode[] = [];
        for (let n in out_body) {
            let at_root_target: int? = match (n) {
                let h: root.eval.OutNode_AtRootHoist => h.target,
                _ => null,
            };
            if (at_root_target != null) {
                let t = at_root_target;
                if (t == own_depth + 1) {
                    let b = self.at_root_hoist.shift();
                    if (b != null) {
                        root.std.extend(shell, b.nodes);
                    }
                } else if (own_depth == 0) {
                    let b = self.at_root_hoist.shift();
                    if (b != null) {
                        root.std.extend(after, b.nodes);
                        let marker: root.eval.OutNode = if (b.group_end) {
                            root.eval.OutNode_GroupEnd {}
                        } else {
                            root.eval.OutNode_AtRootPackTight {}
                        };
                        after.push(marker);
                    }
                } else {
                    after.push(n);
                }
            } else {
                shell.push(n);
            }
        }
        sink.value.push_at_rule(root.eval.OutNode_AtRule {
            name: name,
            prelude: prelude,
            body: shell,
            has_block: true,
            kind: root.eval.AtRuleKind.Generic,
            lines: lines,
        });
        for (let n in after) {
            sink.value.push_at_rule(n);
        }
    }

    /// Evaluate `@at-root`: hoist the body's output to the document root. The
    /// parent-selector context is KEPT — dart resolves `&` against the
    /// enclosing rule but disables the implicit parent join
    /// (`implicitParent: !_atRootExcludingStyleRule`), so `@at-root & {…}`
    /// re-emits the parent at the root while `@at-root .x {…}` stays `.x`.
    /// The optional query is accepted but not yet honoured (the common
    /// no-query case is supported).
    function eval_at_root(self, query: root.ast.TplPiece[]?, body: root.ast.Stmt[], parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        let query_text: string? = if (query != null) {
            self.eval_template(query)
        } else {
            null
        };
        let q = root.eval.AtRootQuery.parse(query_text);
        // Which enclosing at-rule layers the query keeps vs excludes (dart
        // `AtRootQuery.excludes`). The topmost excluded layer is the graft
        // target (dart `_trimIncluded`): kept layers ABOVE it stay in place
        // (the batch re-enters inside the innermost of them), kept layers
        // BELOW it are copied around the hoisted body.
        let excluded: bool[] = self
            .at_rule_ctx
            .map((c: root.eval.AtCtx) -> bool { q.excludes_name(c.query_name()) });
        let first_excluded: int? = excluded.find_index((e: bool) -> bool { e });
        let any_excluded_layer = first_excluded != null;
        // `(with: all)`-style queries that exclude nothing run in place.
        if (!any_excluded_layer && !q.excludes_style_rules()) {
            self.exec(body, parents, sink);
            return;
        }

        self.push_scope(false);
        let saved = self.at_root_excluding_style_rule;
        self.at_root_excluding_style_rule = q.excludes_style_rules();
        // An excluded media layer also stops feeding the body's own @media
        // merging; an excluded keyframes layer drops the keyframe context.
        let saved_media: root.eval.ResolvedQuery[]? = null;
        if (q.excludes_name("media")) {
            saved_media = self.media_queries;
            self.media_queries = [];
        }
        let saved_kf: bool? = null;
        if (q.excludes_name("keyframes")) {
            saved_kf = self.in_keyframes;
            self.in_keyframes = false;
        }
        let out: root.eval.OutNode[] = [];
        // PORT: the body's `Result` is caught and re-thrown after the cleanup.
        let res: root.error.Error? = null;
        {
            let child: root.std.Cell<root.eval.Sink> = root.std.Cell {
                value: root.eval.Sink_AtRoot {
                    body: out,
                    group_ends: true,
                },
            };
            self.exec(body, parents, child) catch (e) {
                let err: root.error.Error => {
                    res = err;
                }
            };
        }
        self.at_root_excluding_style_rule = saved;
        if (saved_media != null) {
            self.media_queries = saved_media;
        }
        if (saved_kf != null) {
            self.in_keyframes = saved_kf;
        }
        self.pop_scope();
        if (res != null) {
            throw res;
        }

        // A declaration inside `@at-root` that no style rule wraps lands at
        // the document root, which dart rejects ("Declarations may only be
        // used within style rules." — issue_1585's `@at-root { @content }`).
        if ((q.excludes_style_rules() || parents.length() == 0)
            && out.some((n: root.eval.OutNode) -> bool { n is root.eval.OutNode_AtDecl })) {
            throw root.error.Error.unpositioned("Declarations may only be used within style rules.");
        }

        // When the query KEEPS style rules, bare declarations re-wrap in the
        // enclosing selectors (dart's included CssStyleRule copy):
        // `a { @at-root (without: media) { b: c } }` emits `a { b: c }`.
        let out: root.eval.OutNode[] = if (!q.excludes_style_rules() && parents.length() != 0) {
            let wrapped: root.eval.OutNode[] = [];
            let decls: root.eval.OutItem[] = [];
            let flush = (decls: root.eval.OutItem[], wrapped: root.eval.OutNode[]) -> void {
                if (decls.length() != 0) {
                    wrapped.push(root.eval.OutNode_plain_rule(
                        root.std.clone_vec(parents),
                        root.std.take_all(decls),
                        root.ast.SrcLines.default(),
                    ));
                    // The re-wrapped copy is a completed style rule too.
                    wrapped.push(root.eval.OutNode_GroupEnd {});
                }
            };
            for (let n in out) {
                match (n) {
                    let d: root.eval.OutNode_AtDecl => {
                        decls.push(root.eval.OutItem_Decl {
                            prop: d.prop,
                            value: d.value,
                            important: d.important,
                            custom: d.custom,
                            lines: d.lines,
                            value_span: d.value_span,
                        });
                    },
                    let other => {
                        flush(decls, wrapped);
                        wrapped.push(other);
                    },
                }
            }
            flush(decls, wrapped);
            wrapped
        } else {
            out
        };

        // Hoisted root-level nodes separate with a blank line only after a
        // completed style rule (dart's isGroupEnd: `#inc {…}` → blank →
        // `@supports`, but `@supports {…}` → `@foo` packs tight). The
        // group-end sentinels were pushed by `Sink::AtRoot`'s emit — one per
        // rule completed at the body's own level; rules flattened out of a
        // WRAPPER rule (`@at-root .slim & { &__a{} &__b{} }`) share one batch
        // and pack tight, exactly like dart's `_styleRule == null` gate. An
        // interior sentinel becomes the one blank line; a trailing one stays
        // (the graft's next sibling separates against it).
        let spaced: root.eval.OutNode[] = root.eval.materialize_interior_group_ends(out);
        // A TRAILING sentinel has done its job (it only gated the interior
        // separators above): pop it so it can't ride into the escape path and
        // conjure an empty resume shell (`@media print {}`), or double the
        // top-level `push_group` default blank-after-rule.
        while (root.std.last(spaced) is root.eval.OutNode_GroupEnd) {
            let _ = spaced.pop();
        }
        if (spaced
            .every((n: root.eval.OutNode) -> bool {
                n is root.eval.OutNode_Blank || n is root.eval.OutNode_GroupEnd || n is root.eval.OutNode_AtRootPackTight
            })) {
            return;
        }
        if (first_excluded != null) {
            let te = first_excluded;
            // Escape the excluded at-rules: re-wrap the body in the kept
            // layers BELOW the graft target (innermost-last) and leave a
            // marker; each enclosing layer below the target splits around it
            // and passes it outward until the target layer consumes it.
            let batch = spaced;
            // PORT: `.iter().enumerate().rev()` → a descending index loop.
            let i = self.at_rule_ctx.length() - 1;
            while (i >= 0) {
                let layer = self.at_rule_ctx[i];
                if (i > te && !excluded[i]) {
                    batch = [layer.wrap(batch)];
                }
                i -= 1;
            }
            self.at_root_hoist.push(root.eval.AtRootBatch {
                target: te,
                group_end: parents.length() == 0,
                nodes: batch,
            });
            sink.value.push_at_rule(root.eval.OutNode_AtRootHoist { target: te });
        } else {
            // No layer escaped: the body stays inside the enclosing at-rules
            // (only the style-rule join was disabled), so emit in place.
            // When the hoisted chunk ends in a style rule AND an enclosing style
            // rule resumes after it, dart separates the resumed parent with one
            // blank line (isGroupEnd). Leave a group-end marker that
            // `emit_style_rule` materializes into that blank (a trailing marker —
            // nothing resumes — stays a no-op, so no spurious trailing blank).
            let ends_in_rule = root.std.last(spaced) is root.eval.OutNode_Rule;
            for (let node in spaced) {
                // Push inter-rule separators as GROUP-END markers, not literal
                // blanks, so the group machinery inserts EXACTLY one blank: at the
                // document root `push_group` turns the marker into one separator
                // (a literal blank would be double-counted into three), and inside
                // a resumed rule `emit_style_rule` materializes it into one.
                if (node is root.eval.OutNode_Blank) {
                    sink.value.push_at_rule(root.eval.OutNode_GroupEnd {});
                } else {
                    sink.value.push_at_rule(node);
                }
            }
            if (ends_in_rule && parents.length() != 0) {
                sink.value.push_at_rule(root.eval.OutNode_GroupEnd {});
            }
        }
    }

}
