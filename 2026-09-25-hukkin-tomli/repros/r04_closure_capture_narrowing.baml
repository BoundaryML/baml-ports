function r04(f: ((string) -> int)?) -> (string) -> int {
    if (f == null) {
        return (s: string) -> int { 0 };
    }
    (s: string) -> int { f(s) }
}
