// Port of internal/tz.go.
//
// Timezones used for local datetime, date, and time TOML types.
//
// The exact way times and dates without a timezone should be interpreted is not
// well-defined in the TOML specification and left to the implementation. These
// defaults to current local timezone offset of the computer, but this can be
// changed by changing these variables before decoding.
//
// Go keeps these in package-level variables (internal.LocalDatetime etc.).
// BAML has no package-level variables, so each is a function returning an
// equal Location value; identity is compared with root.go.same_location.
// The local offset is that of root.go.local() (see ns_go/time.baml).

function local_offset() -> int {
    root.go.local().offset
}

function local_datetime() -> root.go.Location {
    root.go.fixed_zone("datetime-local", local_offset())
}

function local_date() -> root.go.Location {
    root.go.fixed_zone("date-local", local_offset())
}

function local_time() -> root.go.Location {
    root.go.fixed_zone("time-local", local_offset())
}
