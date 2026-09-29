// Port of parse.go.
//
// Go's parser stores decoded TOML values as `any`. The concrete Go types it
// ever puts there are string, int64, float64, bool, time.Time, []any,
// map[string]any and []map[string]any (arrays of tables). BAML has no `any`
// that can be matched structurally without knowing the members, so `Any` is a
// closed recursive union of exactly those shapes. BAML arrays/maps carry
// their element type at runtime, so a `map<string, Any>[]` (array of tables)
// is still distinguishable from an `Any[]` (inline array) by `match`, exactly
// like Go's type switch distinguishes []map[string]any from []any.
//
// Go int64 does not fit BAML's `int` (63-bit), so TOML integers are `bigint`
// values restricted to the int64 range.
type Any = string | bigint | float | bool | root.go.Time | Any[] | map<string, Any> | map<string, Any>[];

class KeyInfo {
    pos: Position,
    toml_type: TomlType?,
}

// (any, tomlType) return pair of (*parser).value and friends.
class TypedValue {
    val: Any,
    typ: TomlType,
}

class Parser {
    lx: Lexer,
    max_depth: int,
    arr_depth: int,
    context: Key, // Full key for the current hash in scope.
    current_key: string, // Base key name for everything except hashes.
    pos: Position, // Current position in the TOML file.

    ordered: Key[], // List of keys in the order that they appear in the TOML data.
    key_info: map<string, KeyInfo>, // Map keyname → info about the TOML key.
    mapping: map<string, Any>, // Map keyname → key value.
    implicits: map<string, bool>, // Record implicit keys (e.g. "key.group.names").

    function panic_err(self, it: Item, err: TomlError) -> never {
        throw ParseError {
            message: err.error(),
            usage: "",
            err: err,
            position: it.pos.with_col(self.lx.input),
            line: it.pos.len,
            last_key: self.current(),
            input: [],
        }
    }

    function panic_itemf(self, it: Item, msg: string) -> never {
        throw ParseError {
            message: msg,
            usage: "",
            err: null,
            position: it.pos.with_col(self.lx.input),
            line: it.pos.len,
            last_key: self.current(),
            input: [],
        }
    }

    function panicf(self, msg: string) -> never {
        throw ParseError {
            message: msg,
            usage: "",
            err: null,
            position: self.pos.with_col(self.lx.input),
            line: self.pos.line,
            last_key: self.current(),
            input: [],
        }
    }

    function next(self) -> Item {
        let it = self.lx.next_item();
        if (it.typ == ItemType.Error) {
            let e = it.err;
            if (e != null) {
                throw ParseError {
                    message: e.error(),
                    usage: "",
                    err: e,
                    position: it.pos.with_col(self.lx.input),
                    line: it.pos.line,
                    last_key: self.current(),
                    input: [],
                }
            }
            self.panic_itemf(it, it.val);
        }
        it
    }

    function next_pos(self) -> Item {
        let it = self.next();
        self.pos = it.pos;
        it
    }

    function expect(self, typ: ItemType) -> Item {
        let it = self.next();
        self.assert_equal(typ, it.typ);
        it
    }

    function assert_equal(self, expected: ItemType, got: ItemType) -> void {
        if (expected != got) {
            bug(`Expected '${item_type_string(expected)}' but got '${item_type_string(got)}'.`);
        }
    }

    function top_level(self, item: Item) -> void {
        match (item.typ) {
            ItemType.CommentStart => { // # ..
                let _ = self.expect(ItemType.Text);
            },
            ItemType.TableStart => { // [ .. ]
                let name = self.next_pos();

                let key = new_key([]);
                while (name.typ != ItemType.TableEnd && name.typ != ItemType.EOF) {
                    key.parts.push(self.key_string(name));
                    name = self.next();
                }
                self.assert_equal(ItemType.TableEnd, name.typ);

                self.add_context(key, false);
                self.set_type("", toml_hash(), item.pos);
                self.ordered.push(key);
            },
            ItemType.ArrayTableStart => { // [[ .. ]]
                let name = self.next_pos();

                let key = new_key([]);
                while (name.typ != ItemType.ArrayTableEnd && name.typ != ItemType.EOF) {
                    key.parts.push(self.key_string(name));
                    name = self.next();
                }
                self.assert_equal(ItemType.ArrayTableEnd, name.typ);

                self.add_context(key, true);
                self.set_type("", toml_array_hash(), item.pos);
                self.ordered.push(key);
            },
            ItemType.KeyStart => { // key = ..
                let outer_context = self.context;
                /// Read all the key parts (e.g. 'a' and 'b' in 'a.b')
                let k = self.next_pos();
                let key = new_key([]);
                while (k.typ != ItemType.KeyEnd && k.typ != ItemType.EOF) {
                    key.parts.push(self.key_string(k));
                    k = self.next();
                }
                self.assert_equal(ItemType.KeyEnd, k.typ);

                /// The current key is the last part.
                self.current_key = key.last();

                /// All the other parts (if any) are the context; need to set each part
                /// as implicit.
                let context = key.parent();
                let i = 0;
                while (i < context.parts.length()) {
                    self.add_implicit_context(self.context.add(context.parts[i]));
                    i += 1;
                }
                self.ordered.push(self.context.add(self.current_key));

                /// Set value.
                let v_item = self.next();
                let tv = self.value(v_item, false);
                self.set_value(self.current_key, tv.val);
                self.set_type(self.current_key, tv.typ, v_item.pos);

                /// Remove the context we added (preserving any context from [tbl] lines).
                self.context = outer_context;
                self.current_key = "";
            },
            _ => bug(`Unexpected type at top level: ${item_type_string(item.typ)}`),
        }
    }

    // Gets a string for a key (or part of a key in a table name).
    function key_string(self, it: Item) -> string {
        match (it.typ) {
            ItemType.Text => it.val,
            ItemType.String | ItemType.StringEsc | ItemType.MultilineString | ItemType.RawString | ItemType.RawMultilineString => {
                let tv = self.value(it, false);
                match (tv.val) {
                    let s: string => s,
                    _ => bug("key_string: string item did not produce a string"),
                }
            },
            _ => bug(`Unexpected key type: ${item_type_string(it.typ)}`),
        }
    }

    // value translates an expected value from the lexer into a Go value wrapped
    // as an empty interface.
    function value(self, it: Item, parent_is_array: bool) -> TypedValue {
        match (it.typ) {
            ItemType.String => TypedValue { val: it.val, typ: type_of_primitive(it) },
            ItemType.StringEsc => TypedValue { val: self.replace_escapes(it, it.val), typ: type_of_primitive(it) },
            ItemType.MultilineString => TypedValue {
                val: self.replace_escapes(it, self.strip_escaped_newlines(strip_first_newline(it.val))),
                typ: type_of_primitive(it),
            },
            ItemType.RawString => TypedValue { val: it.val, typ: type_of_primitive(it) },
            ItemType.RawMultilineString => TypedValue { val: strip_first_newline(it.val), typ: type_of_primitive(it) },
            ItemType.Integer => self.value_integer(it),
            ItemType.Float => self.value_float(it),
            ItemType.Bool => {
                match (it.val) {
                    "true" => TypedValue { val: true, typ: type_of_primitive(it) },
                    "false" => TypedValue { val: false, typ: type_of_primitive(it) },
                    _ => bug(`Expected boolean value, but got '${it.val}'.`),
                }
            },
            ItemType.Datetime => self.value_datetime(it),
            ItemType.Array => self.value_array(it),
            ItemType.InlineTableStart => self.value_inline_table(it, parent_is_array),
            _ => bug(`Unexpected value type: ${item_type_string(it.typ)}`),
        }
    }

    function value_integer(self, it: Item) -> TypedValue {
        if (!num_underscores_ok(it.val)) {
            self.panic_itemf(it, `Invalid integer ${root.go.quote(it.val)}: underscores must be surrounded by digits`);
        }
        if (num_has_leading_zero(it.val)) {
            self.panic_itemf(it, `Invalid integer ${root.go.quote(it.val)}: cannot have leading zeroes`);
        }

        let r = root.go.parse_int(it.val, 0, 64);
        let num = r.value;
        if (r.err != "") {
            // Distinguish integer values. Normally, it'd be a bug if the lexer
            // provides an invalid integer, but it's possible that the number is
            // out of range of valid values (which the lexer cannot determine).
            // So mark the former as a bug but the latter as a legitimate user
            // error.
            if (r.err == "range") {
                self.panic_err(it, ErrParseRange { i: it.val, size: "int64" });
            } else {
                bug(`Expected integer value, but got '${it.val}'.`);
            }
        }
        TypedValue { val: num, typ: type_of_primitive(it) }
    }

    function value_float(self, it: Item) -> TypedValue {
        let parts = root.go.fields_func(it.val, (r: string) -> bool {
            r == "." || r == "e" || r == "E"
        });
        for (let part in parts) {
            if (!num_underscores_ok(part)) {
                self.panic_itemf(it, `Invalid float ${root.go.quote(it.val)}: underscores must be surrounded by digits`);
            }
        }
        if (parts.length() > 0 && num_has_leading_zero(parts[0])) {
            self.panic_itemf(it, `Invalid float ${root.go.quote(it.val)}: cannot have leading zeroes`);
        }
        if (!num_periods_ok(it.val)) {
            // As a special case, numbers like '123.' or '1.e2',
            // which are valid as far as Go/strconv are concerned,
            // must be rejected because TOML says that a fractional
            // part consists of '.' followed by 1+ digits.
            self.panic_itemf(it, `Invalid float ${root.go.quote(it.val)}: '.' must be followed by one or more digits`);
        }
        let val = it.val.replace_all("_", "");
        let signbit = false;
        if (val == "+nan" || val == "-nan") {
            signbit = val == "-nan";
            val = "nan";
        }
        let r = root.go.parse_float(val);
        let num = r.value;
        if (r.err != "") {
            if (r.err == "range") {
                self.panic_err(it, ErrParseRange { i: it.val, size: "float64" });
            } else {
                self.panic_itemf(it, `Invalid float value: ${root.go.quote(it.val)}`);
            }
        }
        if (signbit) {
            num = root.go.copysign(num, -1.0);
        }
        TypedValue { val: num, typ: type_of_primitive(it) }
    }

    function value_datetime(self, it: Item) -> TypedValue {
        let val = datetime_repl(it.val);
        let found: root.go.Time? = null;
        for (let dt in dt_types()) {
            let t = root.go.parse_in_location(dt.fmt, val, dt.zone);
            if (t != null) {
                if (missing_leading_zero(val, dt.fmt)) {
                    self.panic_err(it, ErrParseDate { v: val });
                }
                found = t;
                break;
            }
        }
        match (found) {
            null => self.panic_err(it, ErrParseDate { v: val }),
            let t: root.go.Time => TypedValue { val: t, typ: type_of_primitive(it) },
        }
    }

    function value_array(self, it0: Item) -> TypedValue {
        if (self.max_depth > 0 && self.arr_depth >= self.max_depth) {
            self.panicf(`exceeds maximum array depth of ${self.max_depth}`);
        }
        self.arr_depth += 1;
        // Go: defer func() { p.arrDepth-- }(). A panic unwinds the whole parse, so
        // the decrement only matters on the normal path.

        self.set_type(self.current_key, toml_array(), it0.pos);

        // Initialize to a non-nil slice to make it consistent with how S = []
        // decodes into a non-nil slice inside something like struct { S
        // []string }. See #338
        let array: Any[] = [];
        let it = self.next();
        while (it.typ != ItemType.ArrayEnd) {
            if (it.typ == ItemType.CommentStart) {
                let _ = self.expect(ItemType.Text);
                it = self.next();
                continue;
            }

            let tv = self.value(it, true);
            array.push(tv.val);

            // XXX: type isn't used here, we need it to record the accurate type
            // information.
            //
            // Not entirely sure how to best store this; could use "key[0]",
            // "key[1]" notation, or maybe store it on the Array type?
            it = self.next();
        }
        self.arr_depth -= 1;
        TypedValue { val: array, typ: toml_array() }
    }

    function value_inline_table(self, it0: Item, parent_is_array: bool) -> TypedValue {
        let top_hash: map<string, Any> = {};
        let outer_context = self.context;
        let outer_key = self.current_key;

        self.context = self.context.add(self.current_key);
        let prev_context = self.context;
        self.current_key = "";

        self.add_implicit(self.context);
        self.add_context(self.context, parent_is_array);

        /// Loop over all table key/value pairs.
        let it = self.next();
        while (it.typ != ItemType.InlineTableEnd) {
            if (it.typ == ItemType.CommentStart) {
                let _ = self.expect(ItemType.Text);
                it = self.next();
                continue;
            }

            /// Read all key parts.
            let k = self.next_pos();
            let key = new_key([]);
            while (k.typ != ItemType.KeyEnd && k.typ != ItemType.EOF) {
                key.parts.push(self.key_string(k));
                k = self.next();
            }
            self.assert_equal(ItemType.KeyEnd, k.typ);

            /// The current key is the last part.
            self.current_key = key.last();

            /// All the other parts (if any) are the context; need to set each part
            /// as implicit.
            let context = key.parent();
            let i = 0;
            while (i < context.parts.length()) {
                self.add_implicit_context(self.context.add(context.parts[i]));
                i += 1;
            }
            self.ordered.push(self.context.add(self.current_key));

            /// Set the value.
            let tv = self.value(self.next(), false);
            self.set_value(self.current_key, tv.val);
            self.set_type(self.current_key, tv.typ, it.pos);

            let hash = top_hash;
            for (let c in context.parts) {
                let h = hash.get(c);
                if (h == null) {
                    let fresh: map<string, Any> = {};
                    hash.set(c, fresh);
                    h = fresh;
                }
                match (h) {
                    let m: map<string, Any> => {
                        hash = m;
                    },
                    _ => self.panicf(`${root.go.quote(self.context.to_string())} is not a table`),
                }
            }
            hash.set(self.current_key, tv.val);

            /// Restore context.
            self.context = prev_context;
            it = self.next();
        }
        self.context = outer_context;
        self.current_key = outer_key;
        TypedValue { val: top_hash, typ: toml_hash() }
    }

    // Set the current context of the parser, where the context is either a hash or
    // an array of hashes, depending on the value of the `array` parameter.
    //
    // Establishing the context also makes sure that the key isn't a duplicate, and
    // will create implicit hashes automatically.
    function add_context(self, key: Key, array: bool) -> void {
        if (self.max_depth > 0 && key.parts.length() >= self.max_depth) {
            // Don't use panicf() helper because we don't want to set LastKey here –
            // it's going to be a very long string and not very useful.
            throw ParseError {
                message: `exceeds maximum table depth of ${self.max_depth}`,
                usage: "",
                err: null,
                position: self.pos.with_col(self.lx.input),
                line: self.pos.line,
                last_key: "",
                input: [],
            }
        }

        /// Always start at the top level and drill down for our context.
        let hash_context = self.mapping;
        let key_context = new_key([]);

        /// We only need implicit hashes for the parents.
        for (let k in key.parent().parts) {
            let ok = hash_context.has(k);
            key_context = key_context.add(k);

            // No key? Make an implicit hash and move on.
            if (!ok) {
                self.add_implicit(key_context);
                let fresh: map<string, Any> = {};
                hash_context.set(k, fresh);
            }

            // If the hash context is actually an array of tables, then set
            // the hash context to the last element in that array.
            //
            // Otherwise, it better be a table, since this MUST be a key group (by
            // virtue of it not being the last element in a key).
            match (hash_context.get(k)) {
                let t: map<string, Any>[] => {
                    hash_context = t[t.length() - 1];
                },
                let t: map<string, Any> => {
                    hash_context = t;
                },
                _ => self.panicf(`Key '${key_context.to_string()}' was already created as a hash.`),
            }
        }

        self.context = key_context;
        if (array) {
            // If this is the first element for this array, then allocate a new
            // list of tables for it.
            let k = key.last();
            if (!hash_context.has(k)) {
                let fresh: map<string, Any>[] = [];
                hash_context.set(k, fresh);
            }

            // Add a new table. But make sure the key hasn't already been used
            // for something else.
            match (hash_context.get(k)) {
                let hash: map<string, Any>[] => {
                    let fresh: map<string, Any> = {};
                    hash.push(fresh);
                },
                _ => self.panicf(`Key '${key.to_string()}' was already created and cannot be used as an array.`),
            }
        } else {
            let fresh: map<string, Any> = {};
            self.set_value(key.last(), fresh);
        }
        self.context = self.context.add(key.last());
    }

    // setValue sets the given key to the given value in the current context.
    // It will make sure that the key hasn't already been defined, account for
    // implicit key groups.
    function set_value(self, key: string, value: Any) -> void {
        let hash = self.mapping;
        let key_context = new_key([]);
        for (let k in self.context.parts) {
            key_context = key_context.add(k);
            let tmp_hash = hash.get(k);
            if (!hash.has(k)) {
                bug(`Context for key '${key_context.to_string()}' has not been established.`);
            }
            match (tmp_hash) {
                // The context is a table of hashes. Pick the most recent table
                // defined as the current hash.
                let t: map<string, Any>[] => {
                    hash = t[t.length() - 1];
                },
                let t: map<string, Any> => {
                    hash = t;
                },
                _ => self.panicf(`Key '${key_context.to_string()}' has already been defined.`),
            }
        }
        key_context = key_context.add(key);

        if (hash.has(key)) {
            // Normally redefining keys isn't allowed, but the key could have been
            // defined implicitly and it's allowed to be redefined concretely. (See
            // the `valid/implicit-and-explicit-after.toml` in toml-test)
            //
            // But we have to make sure to stop marking it as an implicit. (So that
            // another redefinition provokes an error.)
            //
            // Note that since it has already been defined (as a hash), we don't
            // want to overwrite it. So our business is done.
            if (self.is_array(key_context)) {
                if (!self.is_implicit(key_context)) {
                    if (hash.has(key)) {
                        self.panicf(`Key '${key_context.to_string()}' has already been defined.`);
                    }
                }
                self.remove_implicit(key_context);
                hash.set(key, value);
                return;
            }
            if (self.is_implicit(key_context)) {
                self.remove_implicit(key_context);
                return;
            }
            // Otherwise, we have a concrete key trying to override a previous key,
            // which is *always* wrong.
            self.panicf(`Key '${key_context.to_string()}' has already been defined.`);
        }

        hash.set(key, value);
    }

    // setType sets the type of a particular value at a given key. It should be
    // called immediately AFTER setValue.
    //
    // Note that if `key` is empty, then the type given will be applied to the
    // current context (which is either a table or an array of tables).
    function set_type(self, key: string, typ: TomlType, pos: Position) -> void {
        let key_context = new_key(self.context.parts.slice(0, self.context.parts.length()));
        if (key.length() > 0) { // allow type setting for hashes
            key_context = key_context.add(key);
        }
        // Special case to make empty keys ("" = 1) work.
        // Without it it will set "" rather than `""`.
        // TODO: why is this needed? And why is this only needed here?
        if (key_context.parts.length() == 0) {
            key_context = new_key([""]);
        }
        self.key_info.set(key_context.to_string(), KeyInfo { toml_type: typ, pos: pos });
    }

    // Implicit keys need to be created when tables are implied in "a.b.c.d = 1" and
    // "[a.b.c]" (the "a", "b", and "c" hashes are never created explicitly).
    function add_implicit(self, key: Key) -> void {
        self.implicits.set(key.to_string(), true);
    }

    function remove_implicit(self, key: Key) -> void {
        let _ = self.implicits.delete(key.to_string());
    }

    function is_implicit(self, key: Key) -> bool {
        self.implicits.has(key.to_string())
    }

    function is_array(self, key: Key) -> bool {
        let ki = self.key_info.get(key.to_string());
        if (ki == null) {
            return false;
        }
        type_equal(ki.toml_type, toml_array())
    }

    function add_implicit_context(self, key: Key) -> void {
        self.add_implicit(key);
        self.add_context(key, false);
    }

    // current returns the full key name of the current context.
    function current(self) -> string {
        if (self.current_key.length() == 0) {
            return self.context.to_string();
        }
        if (self.context.parts.length() == 0) {
            return self.current_key;
        }
        `${self.context.to_string()}.${self.current_key}`
    }

    // stripEscapedNewlines removes whitespace after line-ending backslashes in
    // multiline strings.
    //
    // A line-ending backslash is an unescaped \ followed only by whitespace until
    // the next newline. After a line-ending backslash, all whitespace is removed
    // until the next non-whitespace character.
    //
    // Works on bytes, like Go, since all indices are byte offsets.
    function strip_escaped_newlines(self, s0: string) -> string {
        let s = root.go.bytes_of(s0);
        let b: int[] = [];
        let i = 0;
        while (true) {
            let ix = root.go.index_byte(s, i, 92); // `\`
            if (ix < 0) {
                b = b.concat(s);
                return root.go.string_of(b);
            }
            i = ix;

            if (s.length() > i + 1 && s[i + 1] == 92) {
                // Escaped backslash.
                i += 2;
                continue;
            }
            // Scan until the next non-whitespace.
            let j = i + 1;
            while (j < s.length()) {
                let c = s[j];
                if (c == 32 || c == 9 || c == 13 || c == 10) {
                    j += 1;
                    continue;
                }
                break;
            }
            if (j == i + 1) {
                // Not a whitespace escape.
                i += 1;
                continue;
            }
            if (root.go.index_byte(s.slice(i, j), 0, 10) < 0) {
                // This is not a line-ending backslash. (It's a bad escape sequence,
                // but we can let replaceEscapes catch it.)
                i += 1;
                continue;
            }
            b = b.concat(s.slice(0, i));
            s = s.slice(j, s.length());
            i = 0;
        }
        bug("unreachable")
    }

    function replace_escapes(self, it: Item, str0: string) -> string {
        let str = root.go.bytes_of(str0);
        let b: int[] = [];
        let skip = 0;
        let i = 0;
        // Go ranges over runes; every byte that is not a backslash is copied
        // verbatim, which is equivalent to writing the decoded rune back.
        while (i < str.length()) {
            let c = str[i];
            if (skip > 0) {
                skip -= 1;
                i += 1;
                continue;
            }
            if (c != 92) {
                b.push(c);
                i += 1;
                continue;
            }

            if (i + 1 >= str.length()) {
                bug("Escape sequence at end of string.");
            }
            let e = str[i + 1];
            if (e == 32 || e == 9) {
                self.panic_itemf(it, `invalid escape: '\\${root.go.rune_string(e)}'`);
            } else if (e == 98) { // b
                b.push(8);
                skip = 1;
            } else if (e == 116) { // t
                b.push(9);
                skip = 1;
            } else if (e == 110) { // n
                b.push(10);
                skip = 1;
            } else if (e == 102) { // f
                b.push(12);
                skip = 1;
            } else if (e == 114) { // r
                b.push(13);
                skip = 1;
            } else if (e == 101) { // e
                b.push(27);
                skip = 1;
            } else if (e == 34) { // "
                b.push(34);
                skip = 1;
            } else if (e == 92) { // \
                b.push(92);
                skip = 1;
            } else if (e == 120) { // x
                // The lexer guarantees the correct number of characters are present;
                // don't need to check here.
                let escaped = self.ascii_escape_to_unicode(it, root.go.string_slice(str, i + 2, i + 4));
                root.go.append_rune(b, escaped);
                skip = 3;
            } else if (e == 117) { // u
                let escaped = self.ascii_escape_to_unicode(it, root.go.string_slice(str, i + 2, i + 6));
                root.go.append_rune(b, escaped);
                skip = 5;
            } else if (e == 85) { // U
                let escaped = self.ascii_escape_to_unicode(it, root.go.string_slice(str, i + 2, i + 10));
                root.go.append_rune(b, escaped);
                skip = 9;
            } else {
                bug(`Expected valid escape code after \\, but got ${root.go.quote_rune(e)}.`);
            }
            i += 1;
        }
        root.go.string_of(b)
    }

    function ascii_escape_to_unicode(self, it: Item, s: string) -> int {
        let hex = root.go.parse_hex(s.to_lower_case());
        if (hex < 0) {
            bug(`Could not parse '${s}' as a hexadecimal number, but the lexer claims it's OK`);
        }
        if (!root.go.valid_rune(hex)) {
            self.panic_itemf(it, `Escaped character '\\u${s}' is not valid UTF-8.`);
        }
        hex
    }
}

// The result of parse(): Go returns (*parser, error).
function parse(data0: int[], max_depth: int) -> Parser {
    // Read over BOM; do this here as the lexer calls utf8.DecodeRuneInString()
    // which mangles stuff. UTF-16 BOM isn't strictly valid, but some tools add
    // it anyway.
    let data = data0;
    if (root.go.has_prefix(data, [255, 254]) || root.go.has_prefix(data, [254, 255])) { // UTF-16
        data = data.slice(2, data.length());
    } else if (root.go.has_prefix(data, [239, 187, 191])) { // UTF-8
        data = data.slice(3, data.length());
    }

    // Examine first few bytes for NULL bytes; this probably means it's a UTF-16
    // file (second byte in surrogate pair being NULL). Again, do this here to
    // avoid having to deal with UTF-8/16 stuff in the lexer.
    let i = root.go.index_byte(data.slice(0, root.go.min(data.length(), 6)), 0, 0);
    if (i > -1) {
        throw ParseError {
            message: "files cannot contain NULL bytes; probably using UTF-16; TOML files must be UTF-8",
            usage: "",
            err: null,
            position: Position { line: 1, col: 1, start: i, len: 1 },
            line: 1,
            last_key: "",
            input: data,
        }
    }

    let p = Parser {
        lx: lex(data),
        max_depth: max_depth,
        arr_depth: 0,
        context: new_key([]),
        current_key: "",
        pos: Position { line: 0, col: 0, start: 0, len: 0 },
        key_info: {},
        mapping: {},
        ordered: [],
        implicits: {},
    };
    // Go: defer/recover turns a panicked ParseError into the returned error,
    // attaching the input.
    parse_loop(p) catch (e) {
        let pe: ParseError => {
            pe.input = data;
            throw pe
        },
    };
    p
}

function parse_loop(p: Parser) -> void {
    while (true) {
        let item = p.next();
        if (item.typ == ItemType.EOF) {
            break;
        }
        p.top_level(item);
    }
}

class DtType {
    fmt: string,
    zone: root.go.Location,
}

function dt_types() -> DtType[] {
    [
        DtType { fmt: root.go.rfc3339_nano(), zone: root.go.local() },
        DtType { fmt: "2006-01-02T15:04:05.999999999", zone: local_datetime() },
        DtType { fmt: "2006-01-02", zone: local_date() },
        DtType { fmt: "15:04:05.999999999", zone: local_time() },
        DtType { fmt: "2006-01-02T15:04Z07:00", zone: root.go.local() },
        DtType { fmt: "2006-01-02T15:04", zone: local_datetime() },
        DtType { fmt: "15:04", zone: local_time() },
    ]
}

// var datetimeRepl = strings.NewReplacer("z", "Z", "t", "T", " ", "T")
function datetime_repl(s: string) -> string {
    s.replace_all("z", "Z").replace_all("t", "T").replace_all(" ", "T")
}

// Go's time.Parse() will accept numbers without a leading zero; there isn't any
// way to require it. https://github.com/golang/go/issues/29911
//
// Depend on the fact that the separators (- and :) should always be at the same
// location.
function missing_leading_zero(d0: string, l0: string) -> bool {
    let d = root.go.bytes_of(d0);
    let l = root.go.bytes_of(l0);
    let i = 0;
    while (i < l.length()) {
        let c = l[i];
        if (c == 46 || c == 90) { // '.' or 'Z'
            return false;
        }
        if ((c < 48 || c > 57) && (i >= d.length() || d[i] != c)) {
            return true;
        }
        i += 1;
    }
    false
}

// numHasLeadingZero checks if this number has leading zeroes, allowing for '0',
// +/- signs, and base prefixes.
function num_has_leading_zero(s0: string) -> bool {
    let s = root.go.bytes_of(s0);
    if (s.length() > 1 && s[0] == 48 && !(s[1] == 98 || s[1] == 111 || s[1] == 120)) { // Allow 0b, 0o, 0x
        return true;
    }
    if (s.length() > 2 && (s[0] == 45 || s[0] == 43) && s[1] == 48) {
        return true;
    }
    false
}

// numUnderscoresOK checks whether each underscore in s is surrounded by
// characters that are not underscores.
function num_underscores_ok(s: string) -> bool {
    match (s) {
        "nan" | "+nan" | "-nan" | "inf" | "-inf" | "+inf" => {
            return true;
        },
        _ => {},
    }
    let accept = false;
    for (let r in root.go.runes_of(s)) {
        if (r == 95) { // '_'
            if (!accept) {
                return false;
            }
        }

        // isHex is a superset of all the permissible characters surrounding an
        // underscore.
        accept = is_hex(r);
    }
    accept
}

// numPeriodsOK checks whether every period in s is followed by a digit.
function num_periods_ok(s: string) -> bool {
    let period = false;
    for (let r in root.go.runes_of(s)) {
        if (period && !is_digit(r)) {
            return false;
        }
        period = r == 46;
    }
    !period
}

function strip_first_newline(s: string) -> string {
    if (s.starts_with("\n")) {
        return s.slice(1, s.length());
    }
    if (s.starts_with("\r\n")) {
        return s.slice(2, s.length());
    }
    s
}
