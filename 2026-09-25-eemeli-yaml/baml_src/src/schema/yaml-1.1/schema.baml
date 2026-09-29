// Port of src/schema/yaml-1.1/schema.ts

function yaml11_schema() -> Tag[] {
  [
    map_tag(),
    seq_tag(),
    string_tag(),
    null_tag(),
    yaml11_true_tag(),
    yaml11_false_tag(),
    yaml11_int_bin_tag(),
    yaml11_int_oct_tag(),
    yaml11_int_tag(),
    yaml11_int_hex_tag(),
    yaml11_float_nan_tag(),
    yaml11_float_exp_tag(),
    yaml11_float_tag(),
    binary_tag(),
    merge_tag(),
    omap_tag(),
    pairs_tag(),
    set_tag(),
    int_time_tag(),
    float_time_tag(),
    timestamp_tag(),
  ]
}
