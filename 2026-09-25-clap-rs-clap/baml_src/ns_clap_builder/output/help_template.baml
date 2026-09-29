// Port of clap_builder/src/output/help_template.rs

/// `(usize, String)` sort key for `BTreeMap` ordering
class SortKey {
    ord: int,
    key: string,
}

/// `BTreeMap<(usize, String), &Arg>` entry
class OrdArg {
    key: SortKey,
    arg: Arg,
}

/// `BTreeMap<(usize, StyledStr), &Command>` entry
class OrdCmd {
    key: SortKey,
    styled: StyledStr,
    cmd: Command,
}

function sort_key_cmp(a: SortKey, b: SortKey) -> baml.ops.Ordering {
    if (a.ord < b.ord) {
        baml.ops.Ordering.Less
    } else if (a.ord > b.ord) {
        baml.ops.Ordering.Greater
    } else {
        a.key.cmp(b.key)
    }
}

/// `BTreeMap::insert` + iteration order: replace equal keys, keep sorted
function btree_insert_arg(entries: OrdArg[], key: SortKey, arg: Arg) -> void {
    let existing = entries.find_index((e) -> { e.key == key });
    if let i: int = existing {
        entries[i] = OrdArg { key: key, arg: arg };
    } else {
        entries.push(OrdArg { key: key, arg: arg });
    }
}

function btree_insert_cmd(entries: OrdCmd[], key: SortKey, styled: StyledStr, cmd: Command) -> void {
    let existing = entries.find_index((e) -> { e.key == key });
    if let i: int = existing {
        entries[i] = OrdCmd { key: key, styled: styled, cmd: cmd };
    } else {
        entries.push(OrdCmd { key: key, styled: styled, cmd: cmd });
    }
}

/// `help_template.rs`'s `AutoHelp`: default help layout
class AutoHelp {
    _template: HelpTemplate,

    /// Create a new `HelpTemplate` instance.
    function new(writer: StyledStr, cmd: Command, usage: Usage, use_long: bool) -> AutoHelp {
        AutoHelp { _template: HelpTemplate.new(writer, cmd, usage, use_long) }
    }

    function write_help(self) -> void {
        let t = self._template;
        let pos = t._cmd.get_positionals().some((arg) -> { should_show_arg(t._use_long, arg) });
        let non_pos = t._cmd.get_non_positionals().some((arg) -> { should_show_arg(t._use_long, arg) });
        let subcmds = t._cmd.has_visible_subcommands();

        let template = if (non_pos || pos || subcmds) {
            DEFAULT_TEMPLATE()
        } else {
            DEFAULT_NO_ARGS_TEMPLATE()
        };
        t.write_templated_help(template);
    }
}

function DEFAULT_TEMPLATE() -> string {
    "{before-help}{about-with-newline}\n{usage-heading} {usage}\n\n{all-args}{after-help}"
}

function DEFAULT_NO_ARGS_TEMPLATE() -> string {
    "{before-help}{about-with-newline}\n{usage-heading} {usage}{after-help}"
}

/// See `fn short` for the 4
function SHORT_SIZE() -> int { 4 }

/// `help_template.rs`'s `HelpTemplate`: help message formatter
class HelpTemplate {
    _writer: StyledStr,
    _cmd: Command,
    _styles: Styles,
    _usage: Usage,
    _next_line_help: bool,
    _term_w: int,
    _use_long: bool,

    /// Create a new `HelpTemplate` instance.
    function new(writer: StyledStr, cmd: Command, usage: Usage, use_long: bool) -> HelpTemplate {
        let term_w = help_term_w(cmd);
        let next_line_help = cmd.is_next_line_help_set();

        HelpTemplate {
            _writer: writer,
            _cmd: cmd,
            _styles: cmd.get_styles(),
            _usage: usage,
            _next_line_help: next_line_help,
            _term_w: term_w,
            _use_long: use_long,
        }
    }

    /// Write help to stream for the parser in the format defined by the template.
    ///
    /// For details about the template language see [`Command::help_template`].
    function write_templated_help(self, template: string) -> void {
        let parts = template.split("{");
        if let first: string = parts.at(0) {
            self._writer.push_str(first);
        }
        for (let part in parts.slice(1, parts.length())) {
            if let idx: int = part.index_of("}") {
                let tag = part.slice(0, idx);
                let rest = part.slice(idx + 1, part.length());
                match (tag) {
                    "name" => {
                        self.write_display_name();
                    },
                    "bin" => {
                        if (!features().unstable_v5) {
                            self.write_bin_name();
                        } else {
                            self._writer.push_str(`{${tag}}`);
                        }
                    },
                    "version" => {
                        self.write_version();
                    },
                    "author" => {
                        self.write_author(false, false);
                    },
                    "author-with-newline" => {
                        self.write_author(false, true);
                    },
                    "author-section" => {
                        self.write_author(true, true);
                    },
                    "about" => {
                        self.write_about(false, false);
                    },
                    "about-with-newline" => {
                        self.write_about(false, true);
                    },
                    "about-section" => {
                        self.write_about(true, true);
                    },
                    "usage-heading" => {
                        self._writer.push_str(`${self._styles.get_usage().render()}Usage:${self._styles.get_usage().render_reset()}`);
                    },
                    "usage" => {
                        self._writer.push_styled(self._usage.create_usage_no_title([]) ?? StyledStr.new());
                    },
                    "all-args" => {
                        self.write_all_args();
                    },
                    "options" => {
                        // Include even those with a heading as we don't have a good way of
                        // handling help_heading in the template.
                        self.write_args(self._cmd.get_non_positionals(), "options", "option");
                    },
                    "positionals" => {
                        self.write_args(self._cmd.get_positionals(), "positionals", "positional");
                    },
                    "subcommands" => {
                        self.write_subcommands(self._cmd);
                    },
                    "tab" => {
                        self._writer.push_str(TAB());
                    },
                    "after-help" => {
                        self.write_after_help();
                    },
                    "before-help" => {
                        self.write_before_help();
                    },
                    _ => {
                        self._writer.push_str(`{${tag}}`);
                    },
                }
                self._writer.push_str(rest);
            }
        }
    }

    // ===== Basic template methods =====

    /// Writes binary name of a Parser Object to the wrapped stream.
    function write_display_name(self) -> void {
        let display_name = wrap(
            (self._cmd.get_display_name() ?? self._cmd.get_name()).replace_all("{n}", "\n"),
            self._term_w,
        );
        self._writer.push_string(display_name);
    }

    /// Writes binary name of a Parser Object to the wrapped stream.
    function write_bin_name(self) -> void {
        let bin_name = if let bn: string = self._cmd.get_bin_name() {
            if (bn.includes(" ")) {
                // In case we're dealing with subcommands i.e. git mv is translated to git-mv
                bn.replace_all(" ", "-")
            } else {
                wrap(self._cmd.get_name().replace_all("{n}", "\n"), self._term_w)
            }
        } else {
            wrap(self._cmd.get_name().replace_all("{n}", "\n"), self._term_w)
        };
        self._writer.push_string(bin_name);
    }

    function write_version(self) -> void {
        let version = self._cmd.get_version() ?? self._cmd.get_long_version();
        if let output: string = version {
            self._writer.push_string(wrap(output, self._term_w));
        }
    }

    function write_author(self, before_new_line: bool, after_new_line: bool) -> void {
        if let author: string = self._cmd.get_author() {
            if (before_new_line) {
                self._writer.push_str("\n");
            }
            self._writer.push_string(wrap(author, self._term_w));
            if (after_new_line) {
                self._writer.push_str("\n");
            }
        }
    }

    function write_about(self, before_new_line: bool, after_new_line: bool) -> void {
        let about = if (self._use_long) {
            self._cmd.get_long_about() ?? self._cmd.get_about()
        } else {
            self._cmd.get_about()
        };
        if let o: StyledStr = about {
            if (before_new_line) {
                self._writer.push_str("\n");
            }
            let output = o.clone();
            output.replace_newline_var();
            output.wrap(self._term_w);
            self._writer.push_styled(output);
            if (after_new_line) {
                self._writer.push_str("\n");
            }
        }
    }

    function write_before_help(self) -> void {
        let before_help = if (self._use_long) {
            self._cmd.get_before_long_help() ?? self._cmd.get_before_help()
        } else {
            self._cmd.get_before_help()
        };
        if let o: StyledStr = before_help {
            let output = o.clone();
            output.replace_newline_var();
            output.wrap(self._term_w);
            self._writer.push_styled(output);
            self._writer.push_str("\n\n");
        }
    }

    function write_after_help(self) -> void {
        let after_help = if (self._use_long) {
            self._cmd.get_after_long_help() ?? self._cmd.get_after_help()
        } else {
            self._cmd.get_after_help()
        };
        if let o: StyledStr = after_help {
            self._writer.push_str("\n\n");
            let output = o.clone();
            output.replace_newline_var();
            output.wrap(self._term_w);
            self._writer.push_styled(output);
        }
    }

    // ===== Arguments =====

    /// Writes help for all arguments (options, flags, args, subcommands)
    /// including titles of a Parser Object to the wrapped stream.
    function write_all_args(self) -> void {
        let header = self._styles.get_header();

        let pos = self._cmd.get_positionals()
            .filter((a) -> { a.get_help_heading() == null })
            .filter((arg) -> { should_show_arg(self._use_long, arg) });
        let non_pos = self._cmd.get_non_positionals()
            .filter((a) -> { a.get_help_heading() == null })
            .filter((arg) -> { should_show_arg(self._use_long, arg) });
        let subcmds = self._cmd.has_visible_subcommands();

        let custom_headings: FlatSet<string> = FlatSet.new();
        for (let arg in self._cmd.get_arguments()) {
            if let h: string = arg.get_help_heading() { custom_headings.insert(h); }
        }

        let flatten = self._cmd.is_flatten_help_set();

        let first = FirstFlag { value: true };

        if (subcmds && !flatten) {
            if (!first.value) {
                self._writer.push_str("\n\n");
            }
            first.value = false;
            let help_heading = self._cmd.get_subcommand_help_heading() ?? "Commands";
            self._writer.push_styled_str(header, `${help_heading}:`);
            self._writer.push_str("\n");

            self.write_subcommands(self._cmd);
        }

        if (pos.length() > 0) {
            if (!first.value) {
                self._writer.push_str("\n\n");
            }
            first.value = false;
            // Write positional args if any
            let help_heading = "Arguments";
            self._writer.push_styled_str(header, `${help_heading}:`);
            self._writer.push_str("\n");
            self.write_args(pos, "Arguments", "positional");
        }

        if (non_pos.length() > 0) {
            if (!first.value) {
                self._writer.push_str("\n\n");
            }
            first.value = false;
            let help_heading = "Options";
            self._writer.push_styled_str(header, `${help_heading}:`);
            self._writer.push_str("\n");
            self.write_args(non_pos, "Options", "option");
        }
        if (!custom_headings.is_empty()) {
            for (let heading in custom_headings.iter()) {
                let args = self._cmd.get_arguments()
                    .filter((a) -> {
                        if let help_heading: string = a.get_help_heading() {
                            return help_heading == heading;
                        }
                        false
                    })
                    .filter((arg) -> { should_show_arg(self._use_long, arg) });

                if (args.length() > 0) {
                    if (!first.value) {
                        self._writer.push_str("\n\n");
                    }
                    first.value = false;
                    self._writer.push_styled_str(header, `${heading}:`);
                    self._writer.push_str("\n");
                    self.write_args(args, heading, "option");
                }
            }
        }
        if (subcmds && flatten) {
            let cmd = self._cmd.clone();
            cmd.build();
            self.write_flat_subcommands(cmd, first);
        }
    }

    /// Sorts arguments by length and display order and write their help to the wrapped stream.
    function write_args(self, args: Arg[], _category: string, sort_key: "positional" | "option") -> void {
        // The shortest an arg can legally be is 2 (i.e. '-x')
        let longest = 2;
        let ord_v: OrdArg[] = [];

        // Determine the longest
        for (let arg in args.filter((arg) -> {
            // If it's NextLineHelp we don't care to compute how long it is because it may be
            // NextLineHelp on purpose simply *because* it's so long and would throw off all other
            // args alignment
            should_show_arg(self._use_long, arg)
        })) {
            let width = display_width(arg.to_string());
            let actual_width = if (arg.get_long() != null) {
                width + SHORT_SIZE()
            } else {
                width
            };
            if (actual_width > longest) { longest = actual_width; }

            let key = if (sort_key == "positional") { positional_sort_key(arg) } else { option_sort_key(arg) };
            btree_insert_arg(ord_v, key, arg);
        }
        ord_v.sort_by((a, b) -> { sort_key_cmp(a.key, b.key) });

        let next_line_help = self.will_args_wrap(args, longest);

        for (let i in baml.iter.Range.new(0, ord_v.length())) {
            if (i != 0) {
                self._writer.push_str("\n");
                if (next_line_help && self._use_long) {
                    self._writer.push_str("\n");
                }
            }
            self.write_arg(ord_v[i].arg, next_line_help, longest);
        }
    }

    /// Writes help for an argument to the wrapped stream.
    function write_arg(self, arg: Arg, next_line_help: bool, longest: int) -> void {
        let spec_vals = self.spec_vals(arg);

        self._writer.push_str(TAB());
        self.short(arg);
        self.long(arg);
        self._writer.push_styled(arg.stylize_arg_suffix(self._styles, null));
        self.align_to_about(arg, next_line_help, longest);

        let about = if (self._use_long) {
            arg.get_long_help() ?? arg.get_help() ?? StyledStr.new()
        } else {
            arg.get_help() ?? arg.get_long_help() ?? StyledStr.new()
        };

        self.help(arg, about, spec_vals, next_line_help, longest);
    }

    /// Writes argument's short command to the wrapped stream.
    function short(self, arg: Arg) -> void {
        let literal = self._styles.get_literal();

        if let s: string = arg.get_short() {
            self._writer.push_styled_str(literal, `-${s}`);
        } else if (arg.get_long() != null) {
            self._writer.push_str("    ");
        }
    }

    /// Writes argument's long command to the wrapped stream.
    function long(self, arg: Arg) -> void {
        let literal = self._styles.get_literal();

        if let long: string = arg.get_long() {
            if (arg.get_short() != null) {
                self._writer.push_str(", ");
            }
            self._writer.push_styled_str(literal, `--${long}`);
        }
    }

    /// Write alignment padding between arg's switches/values and its about message.
    function align_to_about(self, arg: Arg, next_line_help: bool, longest: int) -> void {
        let padding = if (self._use_long || next_line_help) {
            // long help prints messages on the next line so it doesn't need to align text
            0
        } else if (!arg.is_positional()) {
            let self_len = display_width(arg.to_string()) + SHORT_SIZE();
            // Since we're writing spaces from the tab point we first need to know if we
            // had a long and short, or just short
            let p = if (arg.get_long() != null) {
                // Only account 4 after the val
                TAB_WIDTH()
            } else {
                // Only account for ', --' + 4 after the val
                TAB_WIDTH() + 4
            };
            longest + p - self_len
        } else {
            let self_len = display_width(arg.to_string());
            let p = TAB_WIDTH();
            longest + p - self_len
        };

        self.write_padding(padding);
    }

    /// Writes argument's help to the wrapped stream.
    function help(self, arg: Arg?, about: StyledStr, spec_vals: string, next_line_help: bool, longest: int) -> void {
        let literal = self._styles.get_literal();

        // Is help on next line, if so then indent
        if (next_line_help) {
            self._writer.push_str("\n");
            self._writer.push_str(TAB());
            self._writer.push_str(NEXT_LINE_INDENT());
        }

        let spaces = if (next_line_help) {
            TAB().length() + NEXT_LINE_INDENT().length()
        } else {
            longest + TAB_WIDTH() * 2
        };
        let trailing_indent = self.get_spaces(spaces); // Don't indent any further than the first line is indented

        let help = about.clone();
        let help_is_empty = help.is_empty();
        help.replace_newline_var();
        let next_line_specs = self._use_long && arg != null;
        if (!spec_vals.is_empty() && !next_line_specs) {
            if (!help_is_empty) {
                let sep = " ";
                help.push_str(sep);
            }
            help.push_str(spec_vals);
            help_is_empty = help.is_empty();
        }
        let avail_chars = if (self._term_w > spaces) { self._term_w - spaces } else { 0 };
        help.wrap(avail_chars);
        help.indent("", trailing_indent);
        self._writer.push_styled(help);

        let has_possible_values = false;
        if let a: Arg = arg {
            if (!a.is_hide_possible_values_set() && self.use_long_pv(a)) {
                let DASH_SPACE = 2;
                let possible_vals = a.get_possible_values();
                if (possible_vals.length() > 0) {
                    has_possible_values = true;
                    let longest_pv = possible_vals
                        .filter((f) -> { !f.is_hide_set() })
                        .map((f) -> { display_width(f.get_name()) })
                        .reduce((acc, w) -> { if (w > acc) { w } else { acc } }, 0);
                    let pv_spaces = spaces + TAB_WIDTH() - DASH_SPACE;
                    let pv_trailing_indent = self.get_spaces(pv_spaces + DASH_SPACE);

                    if (!help_is_empty) {
                        self._writer.push_str(`\n\n${" ".repeat(pv_spaces)}`);
                    }
                    self._writer.push_str("Possible values:");
                    for (let pv in possible_vals.filter((pv) -> { !pv.is_hide_set() })) {
                        let name = pv.get_name();

                        let descr = StyledStr.new();
                        descr.push_styled_str(literal, name);
                        if let h: StyledStr = pv.get_help() {
                            // To align help messages
                            let padding = longest_pv - display_width(name);
                            descr.push_str(`: ${" ".repeat(padding)}`);
                            descr.push_styled(h);
                        }

                        let pv_avail_chars = if (self._term_w > pv_trailing_indent.length()) {
                            self._term_w - pv_trailing_indent.length()
                        } else {
                            USIZE_MAX()
                        };
                        descr.replace_newline_var();
                        descr.wrap(pv_avail_chars);
                        descr.indent("", pv_trailing_indent);

                        self._writer.push_str(`\n${" ".repeat(pv_spaces)}- `);
                        self._writer.push_styled(descr);
                    }
                }
            }
        }

        if (!spec_vals.is_empty() && next_line_specs) {
            let h = StyledStr.new();
            if (!help_is_empty || has_possible_values) {
                let sep = "\n\n";
                h.push_str(sep);
            }
            h.push_str(spec_vals);
            h.wrap(avail_chars);
            h.indent("", trailing_indent);
            self._writer.push_styled(h);
        }
    }

    /// Will use next line help on writing args.
    function will_args_wrap(self, args: Arg[], longest: int) -> bool {
        args.filter((arg) -> { should_show_arg(self._use_long, arg) })
            .some((arg) -> {
                let spec_vals = self.spec_vals(arg);
                self.arg_next_line_help(arg, spec_vals, longest)
            })
    }

    function arg_next_line_help(self, arg: Arg, spec_vals: string, longest: int) -> bool {
        if (self._next_line_help || arg.is_next_line_help_set() || self._use_long) {
            // setting_next_line
            true
        } else {
            // force_next_line
            let h = arg.get_help() ?? arg.get_long_help() ?? StyledStr.new();
            let h_w = h.display_width() + display_width(spec_vals);
            let taken = longest + TAB_WIDTH() * 2;
            self._term_w >= taken
                && ((taken * 1.0) / self._term_w) > 0.40
                && h_w > (self._term_w - taken)
        }
    }

    function spec_vals(self, a: Arg) -> string {
        let ctx = self._styles.get_context();
        let ctx_val = self._styles.get_context_value();
        let val_sep = `${ctx.render()}, ${ctx.render_reset()}`; // context values styled separator

        let spec_vals: string[] = [];
        if (features().env) {
            if let arg_env: ArgEnv = a._env {
                if (!a.is_hide_env_set()) {
                    let env_val = if (!a.is_hide_env_values_set()) {
                        `=${arg_env.value ?? ""}`
                    } else {
                        ""
                    };
                    let env_info = `${ctx.render()}[env: ${ctx.render_reset()}${ctx_val.render()}${arg_env.name}${env_val}${ctx_val.render_reset()}${ctx.render()}]${ctx.render_reset()}`;
                    spec_vals.push(env_info);
                }
            }
        }
        if (a.is_takes_value_set() && !a.is_hide_default_value_set() && a._default_vals.length() > 0) {
            let dvs = a._default_vals
                .map((dv) -> { Escape.new(dv).to_cow() })
                .join(" ");

            spec_vals.push(`${ctx.render()}[default: ${ctx.render_reset()}${ctx_val.render()}${dvs}${ctx_val.render_reset()}${ctx.render()}]${ctx.render_reset()}`);
        }

        let als: string[] = [];
        let short_als = a._short_aliases
            .filter((x) -> { x.visible }) // visible
            .map((x) -> { `${ctx_val.render()}-${x.name}${ctx_val.render_reset()}` }); // name
        for (let s in short_als) { als.push(s); }

        let long_als = a._aliases
            .filter((x) -> { x.visible }) // visible
            .map((x) -> { `${ctx_val.render()}--${x.name}${ctx_val.render_reset()}` }); // name
        for (let l in long_als) { als.push(l); }

        if (als.length() > 0) {
            let joined = als.join(val_sep);
            spec_vals.push(`${ctx.render()}[aliases: ${ctx.render_reset()}${joined}${ctx.render()}]${ctx.render_reset()}`);
        }

        if (!a.is_hide_possible_values_set() && !self.use_long_pv(a)) {
            let possible_vals = a.get_possible_values();
            if (possible_vals.length() > 0) {
                let pvs = possible_vals
                    .filter_map((pv) -> { pv.get_visible_quoted_name() })
                    .map((pv) -> { `${ctx_val.render()}${pv}${ctx_val.render_reset()}` })
                    .join(val_sep);

                spec_vals.push(`${ctx.render()}[possible values: ${ctx.render_reset()}${pvs}${ctx.render()}]${ctx.render_reset()}`);
            }
        }
        let connector = if (self._use_long) { "\n" } else { " " };
        spec_vals.join(connector)
    }

    function get_spaces(self, n: int) -> string {
        " ".repeat(n)
    }

    function write_padding(self, amount: int) -> void {
        self._writer.push_str(" ".repeat(amount));
    }

    function use_long_pv(self, arg: Arg) -> bool {
        self._use_long && arg.get_possible_values().some((pv) -> { pv.should_show_help() })
    }

    // ===== Subcommands =====

    function write_flat_subcommands(self, cmd: Command, first: FirstFlag) -> void {
        let header = self._styles.get_header();

        let ord_v: OrdCmd[] = [];
        for (let subcommand in cmd.get_subcommands().filter((subcommand) -> { should_show_subcommand(subcommand) })) {
            btree_insert_cmd(
                ord_v,
                SortKey { ord: subcommand.get_display_order(), key: subcommand.get_name() },
                StyledStr.new(),
                subcommand,
            );
        }
        ord_v.sort_by((a, b) -> { sort_key_cmp(a.key, b.key) });
        for (let entry in ord_v) {
            let subcommand = entry.cmd;
            if (!first.value) {
                self._writer.push_str("\n\n");
            }
            first.value = false;

            let heading = subcommand.get_usage_name_fallback();
            let about = subcommand.get_about() ?? subcommand.get_long_about() ?? StyledStr.new();

            self._writer.push_styled_str(header, `${heading}:`);
            if (!about.is_empty()) {
                self._writer.push_str(`\n${about}`);
            }

            let args = subcommand.get_arguments()
                .filter((arg) -> { should_show_arg(self._use_long, arg) && !arg.is_global_set() });
            if (args.length() > 0) {
                self._writer.push_str("\n");
            }

            let sub_help = HelpTemplate {
                _writer: self._writer,
                _cmd: subcommand,
                _styles: self._styles,
                _usage: self._usage,
                _next_line_help: self._next_line_help,
                _term_w: self._term_w,
                _use_long: self._use_long,
            };
            sub_help.write_args(args, heading, "option");
            if (subcommand.is_flatten_help_set()) {
                sub_help.write_flat_subcommands(subcommand, first);
            }
        }
    }

    /// Writes help for subcommands of a Parser Object to the wrapped stream.
    function write_subcommands(self, cmd: Command) -> void {
        let literal = self._styles.get_literal();

        // The shortest an arg can legally be is 2 (i.e. '-x')
        let longest = 2;
        let ord_v: OrdCmd[] = [];
        for (let subcommand in cmd.get_subcommands().filter((subcommand) -> { should_show_subcommand(subcommand) })) {
            let styled = StyledStr.new();
            let name = subcommand.get_name();
            styled.push_styled_str(literal, name);
            if let short: string = subcommand.get_short_flag() {
                styled.push_str(", ");
                styled.push_styled_str(literal, `-${short}`);
            }
            if let long: string = subcommand.get_long_flag() {
                styled.push_str(", ");
                styled.push_styled_str(literal, `--${long}`);
            }
            let w = styled.display_width();
            if (w > longest) { longest = w; }
            btree_insert_cmd(
                ord_v,
                SortKey { ord: subcommand.get_display_order(), key: styled.as_styled_str() },
                styled,
                subcommand,
            );
        }
        ord_v.sort_by((a, b) -> { sort_key_cmp(a.key, b.key) });

        let next_line_help = self.will_subcommands_wrap(cmd.get_subcommands(), longest);

        for (let i in baml.iter.Range.new(0, ord_v.length())) {
            if (0 < i) {
                self._writer.push_str("\n");
            }
            self.write_subcommand(ord_v[i].styled, ord_v[i].cmd, next_line_help, longest);
        }
    }

    /// Will use next line help on writing subcommands.
    function will_subcommands_wrap(self, subcommands: Command[], longest: int) -> bool {
        subcommands
            .filter((subcommand) -> { should_show_subcommand(subcommand) })
            .some((subcommand) -> {
                let spec_vals = self.sc_spec_vals(subcommand);
                self.subcommand_next_line_help(subcommand, spec_vals, longest)
            })
    }

    function write_subcommand(self, sc_str: StyledStr, cmd: Command, next_line_help: bool, longest: int) -> void {
        let spec_vals = self.sc_spec_vals(cmd);

        let about = cmd.get_about() ?? cmd.get_long_about() ?? StyledStr.new();

        self.subcmd(sc_str, next_line_help, longest);
        self.help(null, about, spec_vals, next_line_help, longest);
    }

    function sc_spec_vals(self, a: Command) -> string {
        let ctx = self._styles.get_context();
        let ctx_val = self._styles.get_context_value();
        let val_sep = `${ctx.render()}, ${ctx.render_reset()}`; // context values styled separator
        let spec_vals: string[] = [];

        let short_als = a.get_visible_short_flag_aliases()
            .map((s) -> { `${ctx_val.render()}-${s}${ctx_val.render_reset()}` });
        let long_als = a.get_visible_long_flag_aliases()
            .map((s) -> { `${ctx_val.render()}--${s}${ctx_val.render_reset()}` });
        let als = a.get_visible_aliases()
            .map((s) -> { `${ctx_val.render()}${s}${ctx_val.render_reset()}` });
        let all_als = short_als.concat(long_als).concat(als).join(val_sep);
        if (!all_als.is_empty()) {
            spec_vals.push(`${ctx.render()}[aliases: ${ctx.render_reset()}${all_als}${ctx.render()}]${ctx.render_reset()}`);
        }

        spec_vals.join(" ")
    }

    function subcommand_next_line_help(self, cmd: Command, spec_vals: string, longest: int) -> bool {
        // Ignore `self.use_long` since subcommands are only shown as short help
        if (self._next_line_help) {
            // setting_next_line
            true
        } else {
            // force_next_line
            let h = cmd.get_about() ?? cmd.get_long_about() ?? StyledStr.new();
            let h_w = h.display_width() + display_width(spec_vals);
            let taken = longest + TAB_WIDTH() * 2;
            self._term_w >= taken
                && ((taken * 1.0) / self._term_w) > 0.40
                && h_w > (self._term_w - taken)
        }
    }

    /// Writes subcommand to the wrapped stream.
    function subcmd(self, sc_str: StyledStr, next_line_help: bool, longest: int) -> void {
        self._writer.push_str(TAB());
        self._writer.push_styled(sc_str);
        if (!next_line_help) {
            let width = sc_str.display_width();
            let padding = longest + TAB_WIDTH() - width;
            self.write_padding(padding);
        }
    }
}

/// `&mut bool` out-parameter for `first`
class FirstFlag {
    value: bool,
}

function help_term_w(cmd: Command) -> int {
    if (!features().unstable_v5) {
        match (cmd.get_term_width()) {
            0 => USIZE_MAX(),
            let w: int => w,
            null => {
                let current_width = dimensions().width ?? 100;
                let max_width = match (cmd.get_max_term_width()) {
                    null | 0 => USIZE_MAX(),
                    let mw: int => mw,
                };
                if (current_width < max_width) { current_width } else { max_width }
            },
        }
    } else {
        let term_w = match (cmd.get_term_width()) {
            0 => USIZE_MAX(),
            let w: int => w,
            null => dimensions().width ?? USIZE_MAX(),
        };

        let max_term_w = match (cmd.get_max_term_width()) {
            0 => USIZE_MAX(),
            let mw: int => mw,
            null => 100,
        };

        if (term_w < max_term_w) { term_w } else { max_term_w }
    }
}

function NEXT_LINE_INDENT() -> string { "        " }

function positional_sort_key(arg: Arg) -> SortKey {
    SortKey { ord: arg.get_index() ?? 0, key: "" }
}

function option_sort_key(arg: Arg) -> SortKey {
    // Formatting key like this to ensure that:
    // 1. Argument has long flags are printed just after short flags.
    // 2. For two args both have short flags like `-c` and `-C`, the
    //    `-C` arg is printed just after the `-c` arg
    // 3. For args without short or long flag, print them at last(sorted
    //    by arg name).
    // Example order: -a, -b, -B, -s, --select-file, --select-folder, -x

    let key = if let x: string = arg.get_short() {
        let lower = if (x.is_ascii()) { x.to_lower_case() } else { x };
        lower + if (x.is_ascii_lowercase()) { "0" } else { "1" }
    } else if let x: string = arg.get_long() {
        x
    } else {
        "{" + arg.get_id()
    };
    SortKey { ord: arg.get_display_order(), key: key }
}

/// `(Option<usize>, Option<usize>)`
class Dimensions {
    width: int?,
    height: int?,
}

function dimensions() -> Dimensions {
    if (!features().wrap_help) {
        return Dimensions { width: null, height: null };
    }

    if let size: root.terminal_size.TerminalSize = root.terminal_size.terminal_size() {
        Dimensions { width: size.width.value, height: size.height.value }
    } else {
        Dimensions { width: parse_env("COLUMNS"), height: parse_env("LINES") }
    }
}

function parse_env(var: string) -> int? {
    let v = baml.env.get(var) catch_all (e) { _ => null };
    if let s: string = v {
        baml.Int.parse(s) catch_all (e) { _ => null }
    } else {
        null
    }
}

function should_show_arg(use_long: bool, arg: Arg) -> bool {
    if (arg.is_hide_set()) {
        return false;
    }
    (!arg.is_hide_long_help_set() && use_long)
        || (!arg.is_hide_short_help_set() && !use_long)
        || arg.is_next_line_help_set()
}

function should_show_subcommand(subcommand: Command) -> bool {
    !subcommand.is_hide_set()
}
