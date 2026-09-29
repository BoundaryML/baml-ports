// Port of goldmark testutil/testutil_test.go.
//
// Go: `var _ TestingT = (*testing.T)(nil)` — fails to compile if the
// TestingT interface is changed in a way that doesn't conform to testing.T.
// BAML has no `testing.T`; the analogous check is that the port's recording
// implementation still conforms to TestingT.
function recording_t_conforms_to_testing_t() -> TestingT {
    new_recording_t()
}
