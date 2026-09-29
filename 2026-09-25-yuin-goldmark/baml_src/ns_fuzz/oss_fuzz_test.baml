// Port of goldmark fuzz/oss_fuzz_test.go.

/// FuzzOss: no seed corpus in the repository (OSS-Fuzz supplies its own), so
/// under plain `go test` it runs nothing; here it runs the mutation fuzzer
/// from an empty seed.
test "FuzzOss" {
    assert.equal(fuzz_mutations([], 200, 2), 200);
}
