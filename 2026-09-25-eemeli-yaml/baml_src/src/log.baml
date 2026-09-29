// Port of src/log.ts

/// `LogLevelId = 'silent' | 'error' | 'warn' | 'debug'`
type LogLevelId = string

function debug(logLevel: string, message: string) -> null {
  if (logLevel == "debug") {
    baml.io.println(message);
  }
  null
}

/// JS `process.emitWarning(warning)` / `console.warn(warning)`.
/// Written to stderr.
function warn(logLevel: string, warning: string) -> null {
  if (logLevel == "debug" || logLevel == "warn") {
    baml.io.eprintln("Warning: " + warning);
  }
  null
}
