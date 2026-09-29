class G { text: string }
function r03(m: map<string, G?>) -> string? {
    m.get("k")?.text
}
