// Port of src/schema/tags.ts

function schemas_get(name: string) -> Tag[]? {
  match (name) {
    "core" => core_schema(),
    "failsafe" => [map_tag(), seq_tag(), string_tag()],
    "json" => json_schema(),
    "yaml11" => yaml11_schema(),
    "yaml-1.1" => yaml11_schema(),
    _ => null,
  }
}

function schemas_keys() -> string[] {
  ["core", "failsafe", "json", "yaml11", "yaml-1.1"]
}

/// `TagId = keyof typeof tagsByName`
function tagsByName(name: string) -> Tag? {
  match (name) {
    "binary" => binary_tag(),
    "bool" => core_bool_tag(),
    "float" => core_float_tag(),
    "floatExp" => core_float_exp_tag(),
    "floatNaN" => core_float_nan_tag(),
    "floatTime" => float_time_tag(),
    "int" => core_int_tag(),
    "intHex" => core_int_hex_tag(),
    "intOct" => core_int_oct_tag(),
    "intTime" => int_time_tag(),
    "map" => map_tag(),
    "merge" => merge_tag(),
    "null" => null_tag(),
    "omap" => omap_tag(),
    "pairs" => pairs_tag(),
    "seq" => seq_tag(),
    "set" => set_tag(),
    "timestamp" => timestamp_tag(),
    _ => null,
  }
}

function tagsByName_keys() -> string[] {
  ["binary", "bool", "float", "floatExp", "floatNaN", "floatTime", "int", "intHex", "intOct", "intTime", "map", "merge", "null", "omap", "pairs", "seq", "set", "timestamp"]
}

function coreKnownTags() -> map<string, Tag> {
  {
    "tag:yaml.org,2002:binary": binary_tag(),
    "tag:yaml.org,2002:merge": merge_tag(),
    "tag:yaml.org,2002:omap": omap_tag(),
    "tag:yaml.org,2002:pairs": pairs_tag(),
    "tag:yaml.org,2002:set": set_tag(),
    "tag:yaml.org,2002:timestamp": timestamp_tag(),
  }
}

function tags_include(tags: Tag[], tag: Tag) -> bool {
  tags.some((t: Tag) -> bool { t._id == tag._id })
}

function getTags(
  customTags: (TagRef[] | ((TagRef[]) -> TagRef[] throws unknown))?,
  schemaName: string,
  addMergeTag: bool?,
) -> Tag[] throws unknown {
  let schemaTags = schemas_get(schemaName);
  let merge = merge_tag();
  if (schemaTags != null && customTags == null) {
    if ((addMergeTag ?? false) && !tags_include(schemaTags, merge)) {
      let out = schemaTags.slice(0, schemaTags.length());
      out.push(merge);
      return out;
    }
    return schemaTags;
  }

  let tags: TagRef[] = [];
  if (schemaTags != null) {
    for (let t in schemaTags) {
      tags.push(t);
    }
  } else {
    match (customTags) {
      TagRef[] => {},
      _ => {
        let keys = schemas_keys()
          .filter((key: string) -> bool { key != "yaml11" })
          .map((key: string) -> string { json_quote(key) })
          .join(", ");
        throw js_error("Unknown schema \"" + schemaName + "\"; use one of " + keys + " or define customTags array");
      },
    }
  }

  match (customTags) {
    let arr: TagRef[] => {
      for (let tag in arr) {
        tags.push(tag);
      }
    },
    let f: (TagRef[]) -> TagRef[] throws unknown => {
      tags = f(tags.slice(0, tags.length()));
    },
    null => {},
  }
  if (addMergeTag ?? false) {
    tags.push(merge);
  }

  let res: Tag[] = [];
  for (let tag in tags) {
    let tagObj = match (tag) {
      let s: string => tagsByName(s),
      let t: Tag => t,
    };
    if (tagObj == null) {
      let tagName = match (tag) {
        let s: string => json_quote(s),
        _ => "{}",
      };
      let keys = tagsByName_keys().map((key: string) -> string { json_quote(key) }).join(", ");
      throw js_error("Unknown custom tag " + tagName + "; use one of " + keys);
    }
    if (!tags_include(res, tagObj)) {
      res.push(tagObj);
    }
  }
  res
}
