// Port of syn-2.0.117/src/path.rs

/// A path at which a named item is exported (e.g. `std::collections::HashMap`).
class Path {
    leading_colon: bool,
    segments: PathSegment[],

    /// Determines whether this is a path of length 1 equal to the given ident.
    function is_ident(self, ident: string) -> bool {
        !self.leading_colon && self.segments.length() == 1 && self.segments[0].ident == ident && self.segments[0].arguments.length() == 0
    }

    /// If this path consists of a single ident, returns the ident.
    function get_ident(self) -> string? {
        if (!self.leading_colon && self.segments.length() == 1 && self.segments[0].arguments.length() == 0) {
            self.segments[0].ident
        } else {
            null
        }
    }

    /// `a::b::c` (generic arguments dropped)
    function joined(self) -> string {
        self.segments.map((s) -> { s.ident }).join("::")
    }

    /// The last segment's identifier
    function last(self) -> string {
        if let s: PathSegment = self.segments.at(-1) { s.ident } else { "" }
    }
}

/// A segment of a path together with any path arguments on that segment.
class PathSegment {
    ident: string,
    /// Angle bracketed generic arguments, as raw source (e.g. `["String", "i32"]`)
    arguments: string[],
}
