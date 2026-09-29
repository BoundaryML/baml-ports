// Port of src/schema/core/schema.ts

function core_schema() -> Tag[] {
  [
    map_tag(),
    seq_tag(),
    string_tag(),
    null_tag(),
    core_bool_tag(),
    core_int_oct_tag(),
    core_int_tag(),
    core_int_hex_tag(),
    core_float_nan_tag(),
    core_float_exp_tag(),
    core_float_tag(),
  ]
}
