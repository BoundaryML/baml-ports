// Port of clap_builder/src/util/any_value.rs
//
// Rust type-erases parsed values behind `Arc<dyn Any>` and remembers the
// `TypeId`. BAML's `unknown` plays the role of `dyn Any`; downcasting is a
// type-pattern match (`match (v) { let t: T => t }`) and the type identity is
// the runtime `reflect.Type`.

class AnyValue {
    _inner: unknown,
    _id: AnyValueId,

    function new(inner: unknown) -> AnyValue {
        AnyValue { _inner: inner, _id: AnyValueId.of_value(inner) }
    }

    function with_id(inner: unknown, id: AnyValueId) -> AnyValue {
        AnyValue { _inner: inner, _id: id }
    }

    function inner(self) -> unknown { self._inner }

    function type_id(self) -> AnyValueId { self._id }

    /// `AnyValue { inner: i32 }`
    function debug(self) -> string { `AnyValue { inner: ${self._id.debug()} }` }
}

/// `downcast_ref::<T>()`
function downcast_ref<T>(v: AnyValue) -> T? {
    match (v._inner) {
        let t: T => t,
        _ => null,
    }
}

class AnyValueId {
    type_name: string,

    function of<A>() -> AnyValueId {
        AnyValueId { type_name: type_name(reflect.Type.of<A>()) }
    }

    function of_value(value: unknown) -> AnyValueId {
        AnyValueId { type_name: type_name(reflect.Type.of_value(value)) }
    }

    function debug(self) -> string { self.type_name }
}

function type_name(t: reflect.Type) -> string {
    t.to_string()
}

test "any_value_debug_impl" {
    assert.equal(AnyValue.new(5).debug(), "AnyValue { inner: int }");
    assert.equal(downcast_ref<int>(AnyValue.new(5)), 5);
    assert.equal(downcast_ref<string>(AnyValue.new(5)), null);
    assert.equal(AnyValueId.of<int>(), AnyValueId.of_value(1))
}
