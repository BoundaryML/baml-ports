// Port of syn-2.0.117/src/error.rs

/// Error returned when a Syn parser cannot parse the input tokens.
class Error {
    message: string,
    span: root.proc_macro2.Span,

    /// Usually the `ParseStream::error` method will be used instead, which
    /// automatically uses the correct span from the current position of the
    /// parse stream.
    function new(span: root.proc_macro2.Span, message: string) -> Error {
        Error { message: message, span: span }
    }

    implements baml.ToString {
        function to_string(self) -> string throws never { self.message }
    }
}
