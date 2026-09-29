// Port of clap_builder/src/mkeymap.rs

class Key {
    key: KeyType,
    index: int,
}

/// `enum KeyType { Short(char), Long(OsStr), Position(usize) }`
type KeyType = KeyShort | KeyLong | KeyPosition

class KeyShort { c: string }
class KeyLong { s: OsStr }
class KeyPosition { n: int }

function key_is_position(k: KeyType) -> bool { k is KeyPosition }

/// `impl PartialEq<char>`, `PartialEq<&str>`, `PartialEq<usize>` for `KeyType`
function key_matches_short(k: KeyType, c: string) -> bool {
    match (k) {
        let s: KeyShort => s.c == c,
        _ => false,
    }
}

function key_matches_long(k: KeyType, l: string) -> bool {
    match (k) {
        let x: KeyLong => x.s == l,
        _ => false,
    }
}

function key_matches_position(k: KeyType, n: int) -> bool {
    match (k) {
        let p: KeyPosition => p.n == n,
        _ => false,
    }
}

class MKeyMap {
    /// All of the arguments.
    _args: Arg[],
    // Cache part:
    /// Will be set after `_build()`.
    _keys: Key[],

    function new() -> MKeyMap { MKeyMap { _args: [], _keys: [] } }

    function contains_short(self, c: string) -> bool {
        self._keys.some((x) -> { key_matches_short(x.key, c) })
    }

    function contains_long(self, l: string) -> bool {
        self._keys.some((x) -> { key_matches_long(x.key, l) })
    }

    function contains_position(self, n: int) -> bool {
        self._keys.some((x) -> { key_matches_position(x.key, n) })
    }

    /// Push an argument in the map.
    function push(self, new_arg: Arg) -> void {
        self._args.push(new_arg);
    }

    /// Find the arg have corresponding key in this map, we can search the key
    /// with u64(for positional argument), char(for short flag), &str and `OsString`
    /// (for long flag)
    function get_short(self, c: string) -> Arg? {
        let k = self._keys.find((k) -> { key_matches_short(k.key, c) });
        if let key: Key = k { self._args[key.index] } else { null }
    }

    function get_long(self, l: string) -> Arg? {
        let k = self._keys.find((k) -> { key_matches_long(k.key, l) });
        if let key: Key = k { self._args[key.index] } else { null }
    }

    function get_position(self, n: int) -> Arg? {
        let k = self._keys.find((k) -> { key_matches_position(k.key, n) });
        if let key: Key = k { self._args[key.index] } else { null }
    }

    /// Return iterators of all keys.
    function keys(self) -> KeyType[] {
        self._keys.map((x) -> { x.key })
    }

    /// Return iterators of all args.
    function args(self) -> Arg[] { self._args }

    /// Mutate every argument.
    function mut_args(self, f: (Arg) -> Arg throws never) -> void {
        self._args = self._args.map(f);
    }

    /// We need a lazy build here since some we may change args after creating
    /// the map, you can checkout who uses `args_mut`.
    function _build(self) -> void {
        // There will be at least as many keys as args, so that is a good starting point
        for (let i in baml.iter.Range.new(0, self._args.length())) {
            append_keys(self._keys, self._args[i], i);
        }
    }

    /// Remove an arg in the graph by Id, usually used by `mut_arg`. Return
    /// `Some(arg)` if removed.
    function remove_by_name(self, name: string) -> Arg? {
        let pos = self._args.find_index((arg) -> { arg._id == name });
        if let i: int = pos { self._args.remove_at(i) } else { null }
    }

    function clone(self) -> MKeyMap {
        MKeyMap { _args: self._args.map((a) -> { a.clone() }), _keys: self._keys.slice(0, self._keys.length()) }
    }
}

/// Generate key types for an specific Arg.
function append_keys(keys: Key[], arg: Arg, index: int) -> void {
    if let pos_index: int = arg._index {
        keys.push(Key { key: KeyPosition { n: pos_index }, index: index });
    } else {
        if let short: string = arg._short {
            keys.push(Key { key: KeyShort { c: short }, index: index });
        }
        if let long: string = arg._long {
            keys.push(Key { key: KeyLong { s: long }, index: index });
        }
        for (let a in arg._short_aliases) {
            keys.push(Key { key: KeyShort { c: a.name }, index: index });
        }
        for (let a in arg._aliases) {
            keys.push(Key { key: KeyLong { s: a.name }, index: index });
        }
    }
}
