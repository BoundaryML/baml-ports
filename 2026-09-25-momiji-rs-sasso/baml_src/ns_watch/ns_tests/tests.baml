// Ported from sasso `src/watch.rs` `mod tests` (namespace `root.watch.tests`).
//
// PORT: `use super::*;` → items of `root.watch` are written fully qualified.
// PORT: `PathBuf::from(p)` → the path string; `Stamp::MISSING` →
// `root.watch.Stamp.MISSING()`; a `SystemTime` is nanoseconds since the Unix
// epoch (a bigint), as in `root.watch.Stamp.modified`.
// PORT: `.unwrap()` on an io `Result` → the plain call: an uncaught
// `baml.errors.Io` fails the test just as the panic does.
// PORT: `std::env::temp_dir()` → `$TMPDIR`, else `/tmp` (its Unix
// definition); `std::process::id()` → `baml.sys.pid()`.

/// PORT: `SystemTime::UNIX_EPOCH + Duration::from_secs(n)`.
function epoch_plus_secs(n: int) -> bigint {
    root.std.bigint_of(n) * 1000000000n
}

/// PORT: `std::env::temp_dir()`.
function temp_dir() -> string {
    root.std.env_var("TMPDIR") ?? "/tmp"
}

function stamp_of(n: int) -> root.watch.Stamp {
    root.watch.Stamp { modified: epoch_plus_secs(n), len: n, digest: 0n, mode: 0o644 }
}

// The property a `--watch` test cannot assert: what a BURST costs. With
// the clock supplied, N changes inside one window is exactly two runs.
test "a_burst_inside_one_window_costs_two_runs" {
    let c = root.watch.Coalesce.new(baml.time.Duration.from_milliseconds(50));
    let runs: bool[] = [];
    // Eight changes, 5 ms apart, all inside the first window.
    for (let i in baml.iter.Range.new(0, 8)) {
        if let root.watch.Step_Run { provisional: let provisional } = c.on_change(i * 5) {
            runs.push(provisional);
            c.finished(provisional, true);
        }
    }
    // The window closes.
    if let root.watch.Step_Run { provisional: let provisional } = c.on_tick(60) {
        runs.push(provisional);
        c.finished(provisional, true);
    }
    // one provisional head, one catch-up
    assert.equal(runs, [true, false])
}

// The leading edge is the whole point: one save must not wait out a
// window that will stay empty.
test "a_lone_save_compiles_immediately" {
    let c = root.watch.Coalesce.new(baml.time.Duration.from_milliseconds(50));
    assert.equal(c.on_change(0), root.watch.Step_Run { provisional: true })
}

// A provisional run earns a catch-up even when it SUCCEEDS: what it read
// is not always what the save finally left there.
test "a_successful_provisional_run_still_gets_a_catch_up" {
    let c = root.watch.Coalesce.new(baml.time.Duration.from_milliseconds(50));
    c.on_change(0);
    c.finished(true, true);
    // not before the window closes
    assert.equal(c.on_tick(49), root.watch.Step_Wait {  });
    assert.equal(c.on_tick(50), root.watch.Step_Run { provisional: false })
}

// …and an authoritative failure does NOT, or a broken file reports its
// error forever.
test "an_authoritative_failure_does_not_ask_for_another" {
    let c = root.watch.Coalesce.new(baml.time.Duration.from_milliseconds(50));
    c.on_change(0);
    c.finished(true, true);
    let step = c.on_tick(50);
    assert.equal(step, root.watch.Step_Run { provisional: false });
    c.finished(false, false);
    assert.equal(c.on_tick(100), root.watch.Step_Wait {  });
    // and stays quiet
    assert.equal(c.on_tick(1000), root.watch.Step_Wait {  })
}

// A change during the cool-down is not lost — it is what the catch-up is
// for.
test "a_change_while_cooling_is_picked_up_by_the_catch_up" {
    let c = root.watch.Coalesce.new(baml.time.Duration.from_milliseconds(50));
    c.on_change(0);
    c.finished(true, true);
    // coalesced into the window
    assert.equal(c.on_change(10), root.watch.Step_Wait {  });
    assert.equal(c.on_tick(50), root.watch.Step_Run { provisional: false })
}

// A file that is missing and stays missing is not a change on every
// tick — otherwise a watch with one unresolved `@use` would recompile
// forever.
test "a_file_that_stays_missing_is_not_a_change" {
    let s = root.watch.Snapshot.default();
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: "/gone.scss", _1: root.watch.Stamp.MISSING() }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        root.watch.Stamp.MISSING()
    });
    assert.is_true(
        !s.changed((_p: string) -> root.watch.Stamp {
            root.watch.Stamp.MISSING()
        }),
    );
    // …and its appearance IS one.
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(1)
        }),
    );
    // reported once
    assert.is_true(
        !s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(1)
        }),
    )
}

// The same second, twice: a filesystem with a one-second timestamp can
// leave the mtime alone across two saves, and the length catches it.
test "a_same_second_save_of_a_different_length_is_a_change" {
    let s = root.watch.Snapshot.default();
    let coarse = (len: int) -> root.watch.Stamp {
        root.watch.Stamp { modified: epoch_plus_secs(1), len: len, digest: 0n, mode: 0o644 }
    };
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: "/a.scss", _1: coarse(10) }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        coarse(10)
    });
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            coarse(11)
        }),
    )
}

// Following a new set keeps what is known about the files that stay: a
// file that has just been READ has not just changed, and re-stamping the
// whole set on every compile would be a recompile on the next tick.
test "following_again_does_not_invent_a_change" {
    let s = root.watch.Snapshot.default();
    let at = (p: string) -> root.std.Tuple2<string, root.watch.Stamp> {
        root.std.Tuple2<string, root.watch.Stamp> { _0: p, _1: stamp_of(1) }
    };
    s.follow([at("/a.scss"), at("/b.scss")], [], [], (_p: string) -> root.watch.Stamp {
        stamp_of(1)
    });
    s.follow([at("/a.scss"), at("/c.scss")], [], [], (_p: string) -> root.watch.Stamp {
        stamp_of(1)
    });
    assert.equal(s.len(), 2);
    assert.is_true(
        !s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(1)
        }),
    )
}

// The interval is not a constant: measured, a 5000-file sweep is 9 ms,
// and repeating that every 50 ms is 18% of a core left running all
// afternoon.
test "the_interval_grows_with_what_a_sweep_costs" {
    // Ten files: 0.014 ms. The floor decides.
    assert.equal(
        root.watch.next_interval(baml.time.Duration.from_microseconds(14), 50),
        root.watch.MIN_INTERVAL(),
    );
    // 500 files: 0.665 ms, 50x is 33 ms — still the floor.
    assert.equal(
        root.watch.next_interval(baml.time.Duration.from_microseconds(665), 50),
        root.watch.MIN_INTERVAL(),
    );
    // 2000 files: 3.2 ms, 50x is 160 ms.
    assert.equal(
        root.watch.next_interval(baml.time.Duration.from_microseconds(3191), 50),
        baml.time.Duration.from_microseconds(159550),
    );
    // 5000 files: 9.1 ms, 50x is 457 ms.
    assert.equal(
        root.watch.next_interval(baml.time.Duration.from_microseconds(9138), 50),
        baml.time.Duration.from_microseconds(456900),
    );
    // And a pathological sweep is capped rather than unbounded.
    assert.equal(
        root.watch.next_interval(baml.time.Duration.from_milliseconds(100), 50),
        root.watch.MAX_INTERVAL(),
    )
}

// A save that lands WHILE the compile is running must survive being
// followed again. Re-stamping the file after the compile records the
// new bytes as the baseline for output built from the old ones, and
// nothing ever compiles them — measured at 1 in 4, writing into a
// 680 ms compile.
test "a_file_changed_during_the_compile_is_still_a_change" {
    let s = root.watch.Snapshot.default();
    let f = "/a.scss";
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: f, _1: stamp_of(1) }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        stamp_of(1)
    });
    // The compile runs; the file is saved again; the watcher follows the
    // same set afterwards and must NOT adopt the new stamp.
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: f, _1: stamp_of(2) }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        stamp_of(2)
    });
    // the mid-compile save was absorbed
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(2)
        }),
    )
}

// A file this compile met for the FIRST time — the whole set, on the
// first compile of a watch — takes the stamp from when it was read,
// not from after. Otherwise a save that lands during that compile
// becomes the baseline and the CSS built from the older bytes stands.
// Measured before this: 3 of 5 lost, saving 300 ms into a 680 ms first
// compile.
test "a_new_file_takes_the_stamp_from_when_it_was_read" {
    let s = root.watch.Snapshot.default();
    let f = "/new.scss";
    // Read at 1; saved again during the compile, so it is 2 by the time
    // the watcher follows it.
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: f, _1: stamp_of(1) }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        stamp_of(2)
    });
    // the save during the first compile was absorbed
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(2)
        }),
    )
}

// The case two fields cannot see: same second, same length. On a
// filesystem that keeps whole seconds that is two ordinary saves, and
// without the digest the watch would sit on stale CSS forever.
test "a_same_second_same_length_save_is_still_a_change" {
    let whole_second = (digest: bigint) -> root.watch.Stamp {
        root.watch.Stamp { modified: epoch_plus_secs(1), len: 10, digest: digest, mode: 0o644 }
    };
    let s = root.watch.Snapshot.default();
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: "/a.scss", _1: whole_second(111n) }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        whole_second(111n)
    });
    // the contents changed and nothing else did
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            whole_second(222n)
        }),
    );
    // reported once
    assert.is_true(
        !s.changed((_p: string) -> root.watch.Stamp {
            whole_second(222n)
        }),
    )
}

// …and a precise timestamp does not pay for it. `Stamp::of` reads the
// file only when the mtime has no sub-second part, so on a filesystem
// like this one the digest is always zero and no content is read.
test "a_precise_timestamp_costs_no_read" {
    let dir = root.std.path_join(temp_dir(), `sasso-stamp-${baml.sys.pid()}`);
    root.std.create_dir_all(dir);
    let p = root.std.path_join(dir, "a.scss");
    root.std.write_file(p, "$c: red;\n");
    let stamp = root.watch.Stamp.of(p);
    // PORT: `modified.and_then(|t| t.duration_since(UNIX_EPOCH).ok())
    // .is_some_and(|d| d.subsec_nanos() != 0)` as explicit `if`s.
    let modified = stamp.modified;
    let precise = if (modified == null) {
        false
    } else if (modified < 0n) {
        false
    } else {
        modified % 1000000000n != 0n
    };
    if (precise) {
        // a precise mtime should not have read the file
        assert.equal(stamp.digest, 0n);
    }
    // A file that does not exist is never read either.
    assert.equal(
        root.watch.Stamp.of(root.std.path_join(dir, "nope.scss")),
        root.watch.Stamp.MISSING(),
    );
    // PORT: `std::fs::remove_dir_all(&dir).ok()` → catch the io error.
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    };
}

// The same, through `Stamp::of` rather than hand-made stamps: a
// whole-second mtime is the signal that the clock is coarse, and the
// digest has to actually be taken there. Forced with `set_modified`,
// so this does not need a filesystem that keeps whole seconds.
test "a_whole_second_mtime_makes_stamp_of_read_the_contents" {
    let dir = root.std.path_join(temp_dir(), `sasso-digest-${baml.sys.pid()}`);
    root.std.create_dir_all(dir);
    let p = root.std.path_join(dir, "a.scss");
    // The digest rule keys on a whole-second mtime, and `set_modified`
    // (1.75) is above this crate's MSRV — so ask `Stamp::of` what it
    // would do with one, through the same private field the rule sets.
    let stamp_with = (text: string) -> root.watch.Stamp {
        root.std.write_file(p, text);
        let live = root.watch.Stamp.of(p);
        root.watch.Stamp {
            modified: epoch_plus_secs(1700000000),
            len: live.len,
            digest: root.watch.digest_of(p, false),
            mode: live.mode,
        }
    };
    // Same length, same second: only the contents differ.
    let first = stamp_with("$c: red00;\n");
    let second = stamp_with("$c: blue0;\n");
    // two same-length saves in one second must not look identical
    assert.is_true(first != second);
    // a whole-second mtime should have been digested
    assert.is_true(first.digest != 0n);
    // …and the rule that decides it: a precise mtime reads nothing.
    //
    // Guarded by `subsecond_is_fine` itself, not by `subsec_nanos != 0`.
    // The two are not the same question — the rule also rejects a whole
    // number of microseconds — and on a 100 ns clock the gap is reachable:
    // every NTFS subsecond is a multiple of 100, so one in ten is also a
    // multiple of 1000, and on those runs `Stamp::of` digests while the
    // weaker guard still demanded that it had not. That is why this test
    // failed roughly one Windows run in ten, on master as well as here.
    let p2 = root.std.path_join(dir, "b.scss");
    root.std.write_file(p2, "$c: red00;\n");
    let precise = root.watch.Stamp.of(p2);
    // PORT: `modified.and_then(|t| t.duration_since(UNIX_EPOCH).ok())
    // .map_or(0, |d| d.subsec_nanos())` as explicit `if`s.
    let pm = precise.modified;
    let subsec = if (pm == null) {
        0
    } else if (pm < 0n) {
        0
    } else {
        root.std.int_of(pm % 1000000000n)
    };
    if (root.watch.subsecond_is_fine(subsec)) {
        // a precise mtime ({subsec} ns) should not read the file
        assert.equal(precise.digest, 0n);
    } else {
        // The other half of the same rule, so neither branch is a way
        // through this test that checks nothing: a clock this coarse is
        // exactly when the contents MUST be read, which is what the two
        // saves above rely on.
        // a coarse mtime ({subsec} ns) should have read the file
        assert.is_true(precise.digest != 0n);
    }
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    };
}

// A directory's digest is its entries, because `fs::read` cannot read
// one — digesting a directory as though it were a file returned 0 every
// time, so on a coarse clock all three fields stayed put and a
// dependency arriving in it was never seen. That is the half of the
// watch that recovers from a missing `@use`.
test "a_directorys_digest_is_what_is_in_it" {
    let dir = root.std.path_join(temp_dir(), `sasso-dirdig-${baml.sys.pid()}`);
    root.std.create_dir_all(dir);
    let empty = root.watch.digest_of(dir, true);
    root.std.write_file(root.std.path_join(dir, "_a.scss"), "$a: 1;\n");
    let one = root.watch.digest_of(dir, true);
    root.std.write_file(root.std.path_join(dir, "_b.scss"), "$b: 2;\n");
    let two = root.watch.digest_of(dir, true);
    // …and a file's CONTENTS changing is not a directory change: that is
    // the file's own stamp's job, and counting it here would recompile
    // twice for one save.
    root.std.write_file(root.std.path_join(dir, "_a.scss"), "$a: 999;\n");
    let after_edit = root.watch.digest_of(dir, true);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    };

    // a file appeared
    assert.is_true(empty != one);
    // another file appeared
    assert.is_true(one != two);
    // editing a file is not a directory change
    assert.equal(two, after_edit);
    // Reading a directory as a file is where this started.
    assert.equal(root.watch.digest_of(temp_dir(), false), 0n)
}

// A directory we did NOT write into keeps its stamp, so a dependency
// created while the compile was running is still a change. Without
// this the watch records the arrival as the baseline and sits on the
// failed result with the fix already on disk.
test "a_directory_changed_during_the_compile_is_still_a_change" {
    let s = root.watch.Snapshot.default();
    let d = "/sub";
    s.follow([], [d], [], (_p: string) -> root.watch.Stamp {
        stamp_of(1)
    });
    // The compile ran; `_new.scss` appeared in it; we wrote nothing
    // there ourselves.
    s.follow([], [d], [], (_p: string) -> root.watch.Stamp {
        stamp_of(2)
    });
    // the arrival during the compile was absorbed
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(2)
        }),
    )
}

// A sub-second part that is merely NON-ZERO proves nothing: a
// millisecond clock reports one and still cannot tell two saves inside
// one tick apart. What the value says is the resolution — its trailing
// zeros — and that is what decides whether the contents have to be
// read.
test "the_resolution_is_read_from_the_timestamp_not_assumed" {
    // Whole seconds, and the two coarse-but-non-zero cases the old test
    // called precise.
    // FAT and friends
    assert.is_true(!root.watch.subsecond_is_fine(0));
    // a millisecond clock
    assert.is_true(!root.watch.subsecond_is_fine(1000000));
    // still a millisecond clock
    assert.is_true(!root.watch.subsecond_is_fine(123000000));
    // a microsecond clock
    assert.is_true(!root.watch.subsecond_is_fine(456000));
    // Anything finer than a microsecond can tell two saves apart.
    // a 100 ns clock
    assert.is_true(root.watch.subsecond_is_fine(100));
    // nanoseconds
    assert.is_true(root.watch.subsecond_is_fine(123456789));
    // the finest there is
    assert.is_true(root.watch.subsecond_is_fine(1))
}

// Becoming readable is a change, and it is the one a watch is waiting
// for when a dependency exists but cannot be read. `chmod` moves no
// mtime, no length and no byte, so without the mode the stamp is
// identical before and after and the fix reaches nothing.
// PORT: `#[cfg(unix)]` — the unix build is the one ported.
test "a_permission_change_is_a_change" {
    // PORT: `use std::os::unix::fs::PermissionsExt;` /
    // `set_permissions(&p, Permissions::from_mode(m))` → `baml.fs.chmod(p, m)`.
    let dir = root.std.path_join(temp_dir(), `sasso-mode-${baml.sys.pid()}`);
    root.std.create_dir_all(dir);
    let p = root.std.path_join(dir, "_v.scss");
    root.std.write_file(p, "$c: red;\n");
    baml.fs.chmod(p, 0o000);
    let locked = root.watch.Stamp.of(p);
    baml.fs.chmod(p, 0o644);
    let opened = root.watch.Stamp.of(p);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    };
    // chmod 000 -> 644 must be a change
    assert.is_true(locked != opened)
}

// Two units, one dependency, read either side of a save. The later
// stamp used to win, which makes the new bytes the baseline and leaves
// the first unit's output built from the old ones forever.
test "the_earliest_observation_of_a_shared_dependency_wins" {
    let s = root.watch.Snapshot.default();
    let shared = "/_v.scss";
    // Unit A read it at 1; unit B, after the save, at 2.
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: shared, _1: stamp_of(1) }, root.std.Tuple2<string, root.watch.Stamp> { _0: shared, _1: stamp_of(2) }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        stamp_of(2)
    });
    // the save one unit compiled against was adopted as the baseline
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(2)
        }),
    );
    // …and the order it arrives in does not decide it.
    let s = root.watch.Snapshot.default();
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: shared, _1: stamp_of(2) }, root.std.Tuple2<string, root.watch.Stamp> { _0: shared, _1: stamp_of(1) }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        stamp_of(2)
    });
    // …in either order
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(2)
        }),
    )
}

// A file one unit could not find at all is the earliest observation
// there is: whatever the other saw, "not there" differs the moment it
// appears.
test "a_missing_observation_beats_a_present_one" {
    let s = root.watch.Snapshot.default();
    let p = "/_v.scss";
    s.follow([root.std.Tuple2<string, root.watch.Stamp> { _0: p, _1: stamp_of(5) }, root.std.Tuple2<string, root.watch.Stamp> { _0: p, _1: root.watch.Stamp.MISSING() }], [], [], (
        _p: string,
    ) -> root.watch.Stamp {
        stamp_of(5)
    });
    // the file is there and one unit had not seen it
    assert.is_true(
        s.changed((_p: string) -> root.watch.Stamp {
            stamp_of(5)
        }),
    )
}

// A directory this watch wrote into is judged by what is in it apart
// from our own files.
//
// This replaces `a_directory_is_restamped_because_our_own_writes_move_it`,
// which asserted the older contract — `ours` was a list of DIRECTORIES
// and such a directory was re-stamped wholesale. That is what hid an
// arrival landing during the same compile. Both halves of the property
// are here: our own write is not a change, and somebody else's is — so the output landing there is not an arrival,
// and a dependency arriving there during the same compile is not
// hidden by it. Re-stamping such a directory wholesale did hide one.
test "a_directory_we_wrote_into_still_sees_somebody_elses_arrival" {
    let dir = root.std.path_join(temp_dir(), `sasso-minus-${baml.sys.pid()}`);
    root.std.create_dir_all(dir);
    root.std.write_file(root.std.path_join(dir, "main.scss"), "a{b:1}\n");
    let out = root.std.path_join(dir, "main.css");

    // PORT: `Stamp::of` passed as the `stamp` function → a closure calling it.
    let stamp_fn = (p: string) -> root.watch.Stamp {
        root.watch.Stamp.of(p)
    };
    let s = root.watch.Snapshot.default();
    // The compile created its own output here.
    root.std.write_file(out, "a{b:1}\n");
    // PORT: `std::slice::from_ref(&out)` → `[out]`.
    s.follow([], [dir], [out], stamp_fn);
    // our own output is not a change
    assert.is_true(!s.changed(stamp_fn));

    // Overwriting it is not one either.
    root.std.write_file(out, "a{b:2}\n");
    // and neither is rewriting it
    assert.is_true(!s.changed(stamp_fn));

    // Somebody else's file is.
    root.std.write_file(root.std.path_join(dir, "_v.scss"), "$c: red;\n");
    let seen = s.changed(stamp_fn);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    };
    // a dependency arrived and the directory was ours
    assert.is_true(seen)
}
