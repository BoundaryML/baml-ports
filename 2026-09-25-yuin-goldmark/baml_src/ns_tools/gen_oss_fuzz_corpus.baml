// Port of goldmark _tools/gen-oss-fuzz-corpus.go.
//
// Writes every spec example into a zip file (one entry per example) as an
// OSS-Fuzz seed corpus. BAML has no `archive/zip`, so a minimal ZIP writer is
// implemented here. Entries use the "stored" method (Go's zip.Writer.Create
// deflates); the archive has the same entries and contents.

class OssTestCase {
    example: int,
    markdown: string,
}

function oss_fuzz_corpus_sub_command(args: string[]) -> int {
    if (args.length() < 1) {
        baml.io.eprintln("Expected command line: _tools oss-fuzz-corpus <corpus_output>.zip");
        return 1;
    }
    let corpus_out = args[0];
    if (!corpus_out.ends_with(".zip")) {
        baml.io.eprintln("Expected command line: _tools oss-fuzz-corpus <corpus_output>.zip");
        return 1;
    }

    let json_corpus = "_test/spec.json";
    let bs = baml.fs.read(json_corpus) catch_all (e) {
        _ => {
            baml.io.eprintln("Could not open file: " + json_corpus);
            return 1;
        }
    };
    let test_cases = baml.json.from_string<OssTestCase[]>(bs) catch_all (e) {
        _ => {
            baml.sys.panic("cannot decode " + json_corpus);
            let none: OssTestCase[] = [];
            none
        }
    };

    let zw = new_zip_writer();
    for (let c in test_cases) {
        let file_in_zip = "example-" + c.example.to_string();
        zw.create(file_in_zip, c.markdown.to_utf8());
    }
    baml.fs.write_bytes(corpus_out, zw.close()) catch_all (e) {
        _ => {
            baml.io.eprintln("Failed to close zip writer");
            return 1;
        }
    };
    0
}

// ---------------------------------------------------------------------------
// Minimal ZIP writer (stored entries only).
// ---------------------------------------------------------------------------

function put_u16(b: uint8array, v: int) -> void {
    b.push(v & 0xff);
    b.push((v >> 8) & 0xff);
}

function put_u32(b: uint8array, v: int) -> void {
    b.push(v & 0xff);
    b.push((v >> 8) & 0xff);
    b.push((v >> 16) & 0xff);
    b.push((v >> 24) & 0xff);
}

/// CRC-32 (IEEE) lookup table.
function crc32_table() -> int[] {
    let table: int[] = [];
    let n = 0;
    while (n < 256) {
        let c = n;
        let k = 0;
        while (k < 8) {
            if ((c & 1) != 0) {
                c = 0xEDB88320 ^ (c >> 1);
            } else {
                c = c >> 1;
            }
            k += 1;
        }
        table.push(c);
        n += 1;
    }
    table
}

function crc32(table: int[], data: uint8array) -> int {
    let c = 0xFFFFFFFF;
    let i = 0;
    let n = data.length();
    while (i < n) {
        c = table[(c ^ data[i]) & 0xff] ^ (c >> 8);
        i += 1;
    }
    c ^ 0xFFFFFFFF
}

class ZipEntry {
    name: uint8array,
    crc: int,
    size: int,
    offset: int,
}

class ZipWriter {
    out: uint8array,
    entries: ZipEntry[],
    table: int[],

    /// Adds a stored entry (Go: `zip.Writer.Create` + `Write`).
    function create(self, name: string, data: uint8array) -> void {
        let nb = name.to_utf8();
        let crc = crc32(self.table, data);
        let e = ZipEntry { name: nb, crc: crc, size: data.length(), offset: self.out.length() };
        let h = root.util.new_bytes();
        put_u32(h, 0x04034b50);
        put_u16(h, 20); // version needed
        put_u16(h, 0x800); // flags: UTF-8 names
        put_u16(h, 0); // method: store
        put_u16(h, 0); // mod time
        put_u16(h, 0x21); // mod date (1980-01-01)
        put_u32(h, crc);
        put_u32(h, data.length());
        put_u32(h, data.length());
        put_u16(h, nb.length());
        put_u16(h, 0); // extra
        root.util.append_bytes(h, nb);
        root.util.append_bytes(self.out, h);
        root.util.append_bytes(self.out, data);
        self.entries.push(e);
    }

    /// Writes the central directory and returns the archive bytes.
    function close(self) -> uint8array {
        let cd_start = self.out.length();
        for (let e in self.entries) {
            let h = root.util.new_bytes();
            put_u32(h, 0x02014b50);
            put_u16(h, 20); // version made by
            put_u16(h, 20); // version needed
            put_u16(h, 0x800);
            put_u16(h, 0);
            put_u16(h, 0);
            put_u16(h, 0x21);
            put_u32(h, e.crc);
            put_u32(h, e.size);
            put_u32(h, e.size);
            put_u16(h, e.name.length());
            put_u16(h, 0); // extra
            put_u16(h, 0); // comment
            put_u16(h, 0); // disk number start
            put_u16(h, 0); // internal attrs
            put_u32(h, 0); // external attrs
            put_u32(h, e.offset);
            root.util.append_bytes(h, e.name);
            root.util.append_bytes(self.out, h);
        }
        let cd_size = self.out.length() - cd_start;
        let eocd = root.util.new_bytes();
        put_u32(eocd, 0x06054b50);
        put_u16(eocd, 0);
        put_u16(eocd, 0);
        put_u16(eocd, self.entries.length());
        put_u16(eocd, self.entries.length());
        put_u32(eocd, cd_size);
        put_u32(eocd, cd_start);
        put_u16(eocd, 0);
        root.util.append_bytes(self.out, eocd);
        self.out
    }
}

function new_zip_writer() -> ZipWriter {
    ZipWriter { out: root.util.new_bytes(), entries: [], table: crc32_table() }
}
