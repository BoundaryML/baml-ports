// Ported from sasso `src/main.rs` `#[cfg(test)] mod default_jobs_tests`
// (namespace `root.default_jobs_tests`).
//
// PORT: `use super::{jobs_from, physical_cores}` — reached as `root.*`.
// `(a..b).map(f).collect::<String>()` → `root.std.range(a, b).map(f)` joined
// with `root.std.concat`.

test "eight_threads_on_four_cores_read_as_four" {
    let text = root.std.concat(
        root.std.range(0, 8).map((i: int) -> string {
            `processor\t: ${i}\nphysical id\t: 0\ncore id\t: ${i / 2}\n\n`
        }),
    );
    assert.equal(root.physical_cores(text), 4)
}

test "two_sockets_of_four_read_as_eight_not_four" {
    let text = "";
    for (let package in baml.iter.Range.new(0, 2)) {
        for (let core in baml.iter.Range.new(0, 4)) {
            text = text + `physical id\t: ${package}\ncore id\t: ${core}\n\n`;
        }
    }
    assert.equal(root.physical_cores(text), 8)
}

test "a_cgroup_cap_below_the_core_count_wins" {
    // 8 physical cores on the host, but this process may use two of them.
    let host = root.std.concat(
        root.std.range(0, 16).map((i: int) -> string {
            `physical id\t: 0\ncore id\t: ${i / 2}\n\n`
        }),
    );
    assert.equal(root.jobs_from(2, host), 2);
    assert.equal(root.jobs_from(16, host), 8);
    assert.equal(root.jobs_from(4, null), 4)
}

test "the_socket_resets_at_each_processor_record" {
    // Two sockets' worth of `core id: 0` are two cores, however incomplete
    // the file is about saying so.
    let partial = "processor\t: 0\nphysical id\t: 0\ncore id\t: 0\n\nprocessor\t: 1\ncore id\t: 0\n";
    assert.equal(root.physical_cores(partial), 2);
    // But a file that names no socket at all is one socket, not a
    // giving-up: that is what a single-socket VM reports.
    let unnamed = "processor\t: 0\ncore id\t: 0\n\nprocessor\t: 1\ncore id\t: 0\n";
    assert.equal(root.physical_cores(unnamed), 1)
}

test "the_fields_may_come_in_either_order" {
    // Nothing promises `physical id` is printed first. Two sockets of two
    // cores, written the other way round, are still four cores.
    let text = "";
    for (let package in baml.iter.Range.new(0, 2)) {
        for (let core in baml.iter.Range.new(0, 2)) {
            text = text + `processor\t: 0\ncore id\t: ${core}\nphysical id\t: ${package}\n\n`;
        }
    }
    assert.equal(root.physical_cores(text), 4)
}

test "no_topology_reported_is_no_answer" {
    assert.equal(root.physical_cores("processor\t: 0\nmodel name\t: Whatever\n"), null);
    assert.equal(root.physical_cores(""), null)
}
