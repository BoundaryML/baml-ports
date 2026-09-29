// Port of clap_builder/src/builder/ext.rs
//
// `Extensions` is a type-keyed map (`FlatMap<AnyValueId, AnyValue>`) used by
// `Command`/`Arg` to carry extension data (e.g. `Styles`) that can be set on a
// parent and looked up on subcommands.

class Extensions {
    _extensions: FlatMap<string, AnyValue>,

    function new() -> Extensions { Extensions { _extensions: FlatMap.new() } }

    function get<T>(self) -> T? {
        let id = AnyValueId.of<T>().type_name;
        let e = self._extensions.get(id);
        if let v: AnyValue = e { downcast_ref<T>(v) } else { null }
    }

    function set<T>(self, tagged: T) -> bool {
        let value = AnyValue.with_id(tagged, AnyValueId.of<T>());
        let id = value.type_id().type_name;
        self._extensions.insert(id, value) != null
    }

    function remove<T>(self) -> T? {
        let id = AnyValueId.of<T>().type_name;
        let e = self._extensions.remove(id);
        if let v: AnyValue = e { downcast_ref<T>(v) } else { null }
    }

    function update(self, other: Extensions) -> void {
        let keys = other._extensions.get_keys();
        let values = other._extensions.get_values();
        for (let i in baml.iter.Range.new(0, keys.length())) {
            self._extensions.insert(keys[i], values[i]);
        }
    }

    function clone(self) -> Extensions {
        let e = Extensions.new();
        e.update(self);
        e
    }
}
