function r02(idx: int?) -> int {
    if (idx == null) {
        baml.sys.panic("missing");
    }
    idx + 1
}
