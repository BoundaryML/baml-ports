// Port of jiff/src/signed_duration.rs (subset)

/// A signed duration of time represented as a 96-bit integer of nanoseconds.
class SignedDuration {
    secs: int,
    nanos: int,

    function new(secs: int, nanos: int) -> SignedDuration { SignedDuration { secs: secs, nanos: nanos } }

    function from_secs(secs: int) -> SignedDuration { SignedDuration { secs: secs, nanos: 0 } }

    function from_nanos(total: int) -> SignedDuration {
        SignedDuration { secs: total / 1000000000, nanos: total % 1000000000 }
    }

    function as_nanos(self) -> int { self.secs * 1000000000 + self.nanos }

    function is_zero(self) -> bool { self.secs == 0 && self.nanos == 0 }

    /// `impl FromStr for SignedDuration` (the "friendly" format)
    function parse(s: string) -> SignedDuration throws Error {
        parse_friendly(s)
    }

    /// `impl Display for SignedDuration` (compact "friendly" format, e.g. `1h 30m 10s`)
    implements baml.ToString {
        function to_string(self) -> string throws never {
            format_friendly(self)
        }
    }
}

/// An error that can occur in this crate.
class Error {
    message: string,

    implements baml.ToString {
        function to_string(self) -> string throws never { self.message }
    }
}
