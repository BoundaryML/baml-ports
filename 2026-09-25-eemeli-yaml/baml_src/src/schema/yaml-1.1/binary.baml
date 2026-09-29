// Port of src/schema/yaml-1.1/binary.ts

function binary_tag() -> Tag {
  Tag {
    _id: 18,
    identify: (value: unknown) -> bool {
      match (value) {
        uint8array => true,
        _ => false,
      }
    },
    default: false,
    tag: "tag:yaml.org,2002:binary",
    /// Returns a Uint8Array.
    resolve: (src_: string, onError: TagOnError, opts: Options) -> unknown {
      // `Buffer.from(src, 'base64')` is lenient about whitespace/newlines
      let clean = src_.replace_all(re("[\\s]"), "");
      baml.Uint8Array.from_base64(clean) catch (e) {
        _ => {
          onError("Invalid base64 in !!binary value");
          src_
        },
      }
    },
    stringify: (item: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      let value = item.value;
      if (!js_truthy(value)) {
        return "";
      }
      let str = match (value) {
        let buf: uint8array => buf.to_base64(),
        _ => "",
      };
      let type = item.type ?? Scalar.BLOCK_LITERAL();
      if (type != Scalar.QUOTE_DOUBLE()) {
        let a = ctx.options.lineWidth - ctx.indent.length();
        let b = ctx.options.minContentWidth;
        let lineWidth = if (a > b) { a } else { b };
        let n = (str.length() + lineWidth - 1) / lineWidth;
        let lines: string[] = [];
        let i = 0;
        let o = 0;
        while (i < n) {
          lines.push(str.slice(o, o + lineWidth));
          i += 1;
          o += lineWidth;
        }
        str = lines.join(if (type == Scalar.BLOCK_LITERAL()) { "\n" } else { " " });
      }

      stringifyString(
        StringifyScalar { comment: item.comment, type: type, value: str },
        ctx,
        onComment,
        onChompKeep,
      )
    },
  }
}
