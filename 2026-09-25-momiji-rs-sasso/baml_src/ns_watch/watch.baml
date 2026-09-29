// Ported from sasso `src/watch.rs` (namespace `root.watch`).
//
// `--watch` without a file-watching dependency: what to poll, how often, and
// when a change becomes a compile.
//
// # Why polling
//
// Every native watcher — inotify, kqueue, `ReadDirectoryChangesW` — is a
// syscall this crate cannot make. `[dependencies]` is empty and that is a
// selling point, and `unsafe_code = "deny"` outside the Miri-verified arena,
// so the FFI declarations those APIs need are not available either. What is
// left in `std` is `fs::metadata`, and asking it repeatedly is a watcher.
//
// It is not a worse one here than it sounds. Measured on this machine, one
// sweep of `fs::metadata` costs about 1.3 microseconds per file:
//
// | files | per sweep | at a 50 ms interval |
// |---|---|---|
// | 10 | 0.014 ms | 0.0% of a core |
// | 200 | 0.262 ms | 0.5% |
// | 500 | 0.665 ms | 1.3% |
// | 2000 | 3.191 ms | 6.4% |
// | 5000 | 9.138 ms | 18.3% |
//
// A stylesheet tree is the small end of that: a `--watch` session follows the
// files ONE entry actually loaded, not a whole repository. But 18% of a core
// for a tree that big is a real cost to leave running all afternoon, so the
// interval is not a constant — see [`next_interval`].
//
// # Why the pieces here are pure
//
// The same reason `_coalesce.mjs` is its own module on the npm side: how many
// compiles a burst of saves costs cannot be asserted from a `--watch` test.
// The obvious check — save eight times, count the compiles — measures the
// spacing of the writes against the window rather than the rule, and there is
// no bound that both catches a regression and survives a loaded CI machine
// stretching those gaps. Driven by a clock the test supplies, N changes
// inside one window is exactly two runs, on any machine, every time.

/// The floor on the poll interval: fast enough that a save feels immediate,
/// and 50 ms is also the npm CLI's coalescing window, so the two front ends
/// answer a burst the same way.
function MIN_INTERVAL() -> baml.time.Duration {
    baml.time.Duration.from_milliseconds(50)
}

/// The ceiling. A tree big enough to reach this is one where a person is
/// waiting on the compile anyway, and half a second of latency beats a
/// watcher that eats a core.
function MAX_INTERVAL() -> baml.time.Duration {
    baml.time.Duration.from_milliseconds(500)
}

/// One part in this that the watcher may spend asking the filesystem
/// questions — 2%, which the measured 1.3 us per file turns into a 50 ms
/// interval for anything under about 800 files.
function SWEEP_BUDGET() -> int {
    50
}

/// How long to coalesce after a run, matching the npm CLI's `windowMs`.
function WINDOW() -> baml.time.Duration {
    baml.time.Duration.from_milliseconds(50)
}

/// The next poll interval, from what the last sweep cost.
///
/// The watcher spends at most one part in `budget` of its time asking the
/// filesystem questions — 2% by default, which at the measured 1.3 us per
/// file is 50 ms for anything under about 800 files and stretches from there.
/// A constant interval cannot do that: 50 ms is free for ten files and 18% of
/// a core for five thousand.
function next_interval(sweep: baml.time.Duration, budget: int) -> baml.time.Duration {
    let want = sweep * budget;
    // PORT: `Duration::clamp` — BAML's `Duration` is not `Compare`, so the
    // bounds are compared as nanosecond counts.
    let min = MIN_INTERVAL();
    let max = MAX_INTERVAL();
    if (want.to_nanoseconds() < min.to_nanoseconds()) {
        min
    } else if (want.to_nanoseconds() > max.to_nanoseconds()) {
        max
    } else {
        want
    }
}

/// What the watcher remembers about one file: enough to tell a save from a
/// touch, and cheap enough to take every tick.
///
/// The length sits beside the modification time because a filesystem with a
/// coarse timestamp — HFS+ and some network mounts keep whole seconds — can
/// leave the mtime unchanged across two saves a person makes in the same
/// second. Two fields disagree less often than one, but "less often" is not
/// "never": two same-length writes inside one tick of that clock are
/// indistinguishable, and the watch would leave stale CSS indefinitely.
///
/// So a third field, and it costs nothing where it is not needed. A
/// **whole-second mtime is itself the signal** that the clock is coarse, so
/// the digest is computed only for files whose timestamp has no sub-second
/// part. Measured on this machine (APFS), 40 same-length writes 1 ms apart:
/// 40 distinct mtimes, all with a sub-second part, 0 of 39 pairs
/// indistinguishable — so nothing is read. On a filesystem that keeps whole
/// seconds every file is read every sweep, and the poll interval already
/// scales with what a sweep costs (see [`next_interval`]), so that pays for
/// itself rather than pinning a core.
// PORT: `modified` is the `SystemTime` as nanoseconds since the Unix epoch.
class Stamp {
    modified: bigint?,
    len: int,
    /// FNV-1a of the contents, or `0` when the timestamp was precise enough
    /// not to need one.
    digest: bigint,
    /// The permission bits, because becoming READABLE is a change a watch
    /// has to act on and none of the three fields above moves for it.
    ///
    /// A dependency that exists and cannot be read fails the compile; the
    /// fix is `chmod`, which touches neither mtime nor length nor contents.
    /// Measured before this: `chmod 000` a dependency, then `chmod 644`, and
    /// the watch NEVER SAW it — a permanent dead end rather than a delay.
    ///
    /// The mode where there is one; elsewhere the one bit `std` exposes.
    /// `readonly()` alone would miss `000 -> 444`, which is exactly the
    /// unreadable-to-readable transition this exists for.
    mode: int,

    /// A file that cannot be stat'd — deleted, or never there. It compares
    /// equal to itself, so a dependency that is missing and stays missing is
    /// not a change on every tick.
    function MISSING() -> Stamp {
        // PORT: `len: u64::MAX` does not fit an `int`; `INT_MAX` is just as
        // impossible for a real file, which is all the sentinel needs.
        Stamp { modified: null, len: root.std.INT_MAX(), digest: 0n, mode: 0 }
    }

    function of(path: string) -> Stamp {
        let m = metadata(path);
        if (m == null) {
            return Stamp.MISSING();
        }
        let modified = m.modified;
        // `map_or`, not `is_none_or`: that one is stable since 1.82 and this
        // crate's MSRV is 1.74.
        // PORT: `duration_since(UNIX_EPOCH)` fails for a time before the
        // epoch, which reads as coarse like a missing time does.
        let coarse = if (modified == null) {
            true
        } else if (modified < 0n) {
            true
        } else {
            !subsecond_is_fine(root.std.int_of(modified % 1000000000n))
        };
        Stamp {
            modified: modified,
            len: m.len,
            digest: if (coarse) {
                digest_of(path, m.is_dir)
            } else {
                0n
            },
            mode: mode_of(m),
        }
    }

    /// A directory judged by what is in it EXCEPT the given names.
    ///
    /// No mtime and no length: ours moved both, so neither can answer the
    /// question. What is left is the entry set, which our own writes are
    /// taken out of and nobody else's are.
    function of_dir_minus(dir: string, ours: string[]) -> Stamp {
        let entries = root.std.read_dir_names(dir) catch (e) {
            let _io: baml.errors.Io => {
                return Stamp.MISSING();
            }
        };
        let names: string[] = entries.filter((n: string) -> bool {
            !ours.includes(n)
        });
        root.std.sort_strings(names);
        let h: bigint = 0xcbf29ce484222325n;
        for (let n in names) {
            let bytes = n.to_utf8();
            let i = 0;
            while (i < bytes.length()) {
                h = h ^ root.std.bigint_of(bytes[i]);
                h = root.std.u64_wrapping_mul(h, 0x100000001b3n);
                i += 1;
            }
            h = h ^ 0n;
            h = root.std.u64_wrapping_mul(h, 0x100000001b3n);
        }
        Stamp { modified: null, len: 0, digest: h, mode: 0 }
    }
}

/// Which of two observations of one file came first.
///
/// A missing file counts as earliest: whatever the other unit saw, "it was
/// not there" is the observation that will differ once it is.
function earlier(a: Stamp, b: Stamp) -> bool {
    let x = a.modified;
    let y = b.modified;
    if (x == null) {
        true
    } else if (y == null) {
        false
    } else {
        x < y
    }
}

/// The permission bits, as far as this platform will say.
function mode_of(m: Metadata) -> int {
    // PORT: `MetadataExt::mode` — `st_mode`, file-type bits included.
    m.mode
}

/// PORT: the part of `std::fs::Metadata` that `Stamp::of` reads. BAML has no
/// `stat`, so all four facts come from one `stat(1)` run (see [`metadata`]).
class Metadata {
    /// `m.modified().ok()`, as nanoseconds since the Unix epoch.
    modified: bigint?,
    /// `m.len()`.
    len: int,
    /// `m.is_dir()`.
    is_dir: bool,
    /// `m.mode()` (`st_mode`).
    mode: int,
}

/// PORT: `std::fs::metadata(path).ok()` — follows symlinks, like Rust's.
///
/// One `stat(1)` process for everything `Stamp::of` needs: the BSD/macOS
/// spelling first, then GNU's (the same order as `root.std.mtime_nanos`).
/// `None` when the path cannot be stat'd.
function metadata(path: string) -> Metadata? {
    // Nothing there (or a dangling symlink): no process to spawn.
    if (!root.std.exists(path)) {
        return null;
    }
    // BSD: mtime with nanoseconds, size, mode in octal.
    let bsd = baml.sys.exec("stat", ["-L", "-f", "%Fm %z %p", path], null) catch (e) {
        _ => null
    };
    if (bsd != null) {
        if (bsd.exit_code == 0) {
            let text = string.from_utf8(bsd.stdout) catch (e) {
                _ => null
            };
            if (text != null) {
                let m = metadata__parse(text, 8);
                if (m != null) {
                    return m;
                }
            }
        }
    }
    // GNU: mtime with nanoseconds, size, raw mode in hex.
    let gnu = baml.sys.exec("stat", ["-L", "-c", "%.9Y %s %f", path], null) catch (e) {
        _ => null
    };
    if (gnu != null) {
        if (gnu.exit_code == 0) {
            let text = string.from_utf8(gnu.stdout) catch (e) {
                _ => null
            };
            if (text != null) {
                return metadata__parse(text, 16);
            }
        }
    }
    null
}

/// PORT: parse `<secs>[.<frac>] <size> <mode>` as printed by [`metadata`]'s
/// `stat` run; `mode_radix` is 8 for BSD `%p`, 16 for GNU `%f`.
function metadata__parse(text: string, mode_radix: int) -> Metadata? {
    let fields = root.std.trim_end_matches(text, "\n").split(" ");
    if (fields.length() != 3) {
        return null;
    }
    let t = fields[0];
    let dot = t.index_of(".");
    let secs_s = if (dot == null) {
        t
    } else {
        t.slice(0, dot)
    };
    let frac_s = if (dot == null) {
        ""
    } else {
        t.slice(dot + 1, t.length())
    };
    frac_s = (frac_s + "000000000").slice(0, 9);
    let secs = baml.Bigint.parse(secs_s) catch (e) {
        _ => null
    };
    let frac = baml.Bigint.parse(frac_s) catch (e) {
        _ => null
    };
    let modified: bigint? = null;
    if (secs != null) {
        if (frac != null) {
            modified
                = if (secs < 0n) {
                    secs * 1000000000n - frac
                } else {
                    secs * 1000000000n + frac
                };
        }
    }
    let len = baml.Int.parse(fields[1]) catch (e) {
        _ => {
            return null;
        }
    };
    let mode = 0;
    for (let c in fields[2].chars()) {
        let d = root.std.to_digit(c, mode_radix);
        if (d == null) {
            return null;
        }
        mode = mode * mode_radix + d;
    }
    Metadata {
        modified: modified,
        len: len,
        // `S_IFMT` / `S_IFDIR`.
        is_dir: (mode & 0o170000) == 0o040000,
        mode: mode,
    }
}

/// Whether a timestamp's sub-second part is fine enough to tell two saves
/// apart.
///
/// A non-zero sub-second part is NOT that proof, which is what this used to
/// test: a filesystem with millisecond stamps reports one, and two
/// same-length writes inside the same millisecond still share it. What the
/// value itself says is how far the clock actually ticks — a 1 ms clock can
/// only ever produce multiples of 1,000,000 ns, a 100 ns clock multiples of
/// 100 — so the trailing zeros are the resolution, and no extra syscall is
/// needed to learn it.
///
/// The line is one microsecond. Two saves inside a millisecond is an editor
/// and a formatter racing, which happens; two inside a microsecond is not a
/// thing a person's tooling does. A precise clock landing on an exact
/// multiple by chance costs one file one digest on one sweep.
function subsecond_is_fine(subsec_nanos: int) -> bool {
    subsec_nanos != 0 && subsec_nanos % 1000 != 0
}

/// FNV-1a over what makes this path different from itself a moment ago.
///
/// For a FILE that is its bytes. For a DIRECTORY it is the sorted names it
/// contains — `fs::read` cannot read a directory at all, so digesting one as
/// if it were a file returned 0 every time and left a coarse-clock directory
/// with three fields that never move. That is the half of the watch that
/// notices a dependency ARRIVING, so it has to be the half that works: a
/// directory's own mtime is the only other signal, and on a filesystem that
/// keeps whole seconds two entries created in one second are one mtime.
///
/// Names, not their metadata: a file's own contents are watched through its
/// own stamp, and what a directory is asked here is only "is the same set of
/// things in you".
function digest_of(path: string, is_dir: bool) -> bigint {
    let h: bigint = 0xcbf29ce484222325n;
    let eat = (bytes: uint8array) -> void {
        let i = 0;
        while (i < bytes.length()) {
            h = h ^ root.std.bigint_of(bytes[i]);
            h = root.std.u64_wrapping_mul(h, 0x100000001b3n);
            i += 1;
        }
    };
    if (is_dir) {
        let entries = root.std.read_dir_names(path) catch (e) {
            let _io: baml.errors.Io => {
                return 0n;
            }
        };
        // Sorted, because `read_dir` promises no order and an unstable one
        // would read as a change on every sweep.
        let names: string[] = root.std.clone_vec(entries);
        root.std.sort_strings(names);
        for (let n in names) {
            eat(n.to_utf8());
            eat("\0".to_utf8());
        }
    } else {
        let bytes = root.std.read_bytes(path) catch (e) {
            let _io: baml.errors.Io => {
                return 0n;
            }
        };
        eat(bytes);
    }
    h
}

/// The set of files a watch is following, and what they looked like last time.
///
/// `BTreeMap` rather than a hash map: the sweep order is then stable, which
/// makes a failure reproducible and the cost above predictable.
// PORT: the maps are iterated through `root.std.sorted_keys` for that order.
class Snapshot {
    files: map<string, Stamp>,
    /// For a directory this watch WROTE into: the names it put there.
    ///
    /// Such a directory cannot be judged by its mtime, because ours moved
    /// it — but re-stamping it wholesale is worse, since a dependency that
    /// arrived during the same compile is then folded into the new
    /// baseline and never seen. So it is judged by its entry set with our
    /// own files taken out: our write cannot look like an arrival, and
    /// cannot hide one either.
    minus: map<string, string[]>,

    /// derive(Default)
    function default() -> Snapshot {
        Snapshot { files: {}, minus: {} }
    }

    /// Replace the watched set. Called after every compile, because the
    /// dependency set changes when an `@use` is added or removed.
    ///
    /// The two groups are treated differently, and the difference is the
    /// whole correctness of this:
    ///
    /// - a `file` already followed KEEPS the stamp it had, and one this
    ///   compile met for the first time takes the stamp the CALLER supplies
    ///   — which is what the file looked like when the compiler read it.
    ///   Stamping either of them here instead records whatever is on disk
    ///   NOW as the baseline for a build made from what was there earlier,
    ///   so a save that lands while a compile is running is absorbed and
    ///   never compiled. Measured before each half: 1 in 4 lost writing
    ///   into a 680 ms compile, and 3 in 5 lost writing into the FIRST
    ///   compile, where every file is new and there is no earlier stamp to
    ///   keep.
    /// - a `dir` keeps its stamp too, for the same reason and one more: a
    ///   dependency CREATED while the compile was running changes the
    ///   directory that was waiting for it, and re-stamping would record
    ///   that arrival as the baseline — the watch would sit on the failed
    ///   result with the fix already on disk.
    /// - a directory in `ours` — one this compile WROTE into — is always
    ///   re-stamped, because creating a file changes its directory's mtime
    ///   and keeping the old stamp would make the watch answer its own
    ///   output forever.
    ///
    /// `stamp` is injected so a test can drive this without a filesystem.
    function follow(
        self,
        files: root.std.Tuple2<string, Stamp>[],
        dirs: string[],
        ours: string[],
        stamp: (string) -> Stamp throws unknown,
    ) -> void {
        // `ours` is the FILES this compile created or removed. A directory
        // holding one of them is judged by its entry set minus those names
        // from here on.
        let minus: map<string, string[]> = {};
        for (let f in ours) {
            let d = root.std.path_parent(f);
            let n = root.std.path_file_name(f);
            if (d != null) {
                if (n != null) {
                    minus.get_or_insert(d, []).push(n);
                }
            }
        }
        // Once ours, always ours: a file we created last compile and only
        // overwrote this one is still not somebody else's arrival.
        for (let d in root.std.sorted_keys(self.minus)) {
            let names = self.minus[d];
            let e = minus.get_or_insert(d, []);
            for (let n in names) {
                if (!e.includes(n)) {
                    e.push(n);
                }
            }
        }
        let next: map<string, Stamp> = {};
        for (let pair in files) {
            let p = pair._0;
            let at_read = pair._1;
            let s = self.files.get(p) ?? at_read;
            // Two units can load the same dependency, and each brings the
            // stamp from when IT read the file. If one read before a save
            // and the other after, taking the later one makes the newer
            // bytes the baseline and the first unit's output is never
            // recompiled. The earliest observation is the one that still
            // differs from what is on disk, so that is the one to keep.
            let prev = next.get(p);
            match (prev) {
                let seen: Stamp if !earlier(s, seen) => {},
                _ => {
                    let _ = next.set(p, s);
                },
            }
        }
        for (let d in dirs) {
            let names = minus.get(d);
            let s = match (names) {
                // Ours: its mtime is meaningless to us now, so the stamp is
                // the entry set without our files. Taken fresh, because an
                // arrival is a difference in THAT, not in the mtime our own
                // write already moved.
                let names: string[] => Stamp.of_dir_minus(d, names),
                // Not ours: keep what we knew, or an arrival during the
                // compile becomes the baseline.
                _ => self.files.get(d) ?? stamp(d),
            };
            let _ = next.set(d, s);
        }
        self.files = next;
        self.minus = minus;
    }

    /// Has any followed file changed? Updates the remembered stamps, so a
    /// change is reported once.
    function changed(self, stamp: (string) -> Stamp throws unknown) -> bool {
        let changed = false;
        for (let path in root.std.sorted_keys(self.files)) {
            let known = self.files[path];
            // A directory we wrote into is asked the same question it was
            // stamped with — see `Snapshot::minus`.
            let names = self.minus.get(path);
            let now = match (names) {
                let names: string[] => Stamp.of_dir_minus(path, names),
                _ => stamp(path),
            };
            if (now != known) {
                let _ = self.files.set(path, now);
                changed = true;
            }
        }
        changed
    }

    /// How many files are followed. Only the tests ask — the watcher itself
    /// never needs to count them — so it is not compiled into the binary.
    // PORT: `#[cfg(test)]` in Rust; kept here for the test port.
    function len(self) -> int {
        self.files.length()
    }
}

/// What the coalescing rule wants done at a given moment.
interface Step {}

/// Nothing to do yet.
class Step_Wait {
    implements Step {}
}

/// Compile. `provisional` marks the run at the head of a burst, where a
/// failure is likelier to be a half-written file than anything the user
/// did: such a run reports nothing and removes nothing, and is always
/// followed by an authoritative one.
class Step_Run {
    provisional: bool,
    implements Step {}
}

/// The leading-edge-with-catch-up rule, driven by a clock the caller owns.
///
/// The first change runs immediately — the common case is one save with
/// nothing after it, and making it wait for a window that will stay empty is
/// pure latency. A provisional run ALWAYS gets a catch-up, not only when it
/// fails: it compiles what is on disk the instant the change is seen, which
/// is not always what the save finally leaves there, and a run that succeeds
/// on stale content would otherwise be the last word.
///
/// `now_ms` is any monotonically non-decreasing millisecond count.
class Coalesce {
    window_ms: int,
    cooling_until: int?,
    dirty: bool,

    function new(window: baml.time.Duration) -> Coalesce {
        Coalesce {
            window_ms: root.std.int_of(window.to_milliseconds()),
            cooling_until: null,
            dirty: false,
        }
    }

    /// A change was seen.
    function on_change(self, now_ms: int) -> Step {
        if (self.cooling_until != null) {
            self.dirty = true;
            return Step_Wait {  };
        }
        self.start_cooling(now_ms);
        self.dirty = true; // the catch-up a provisional run always earns
        Step_Run { provisional: true }
    }

    /// Time has passed and nothing new was seen.
    function on_tick(self, now_ms: int) -> Step {
        let cooling_until = self.cooling_until;
        match (cooling_until) {
            let until: int if now_ms >= until => {
                self.cooling_until = null;
                if (self.dirty) {
                    self.dirty = false;
                    self.start_cooling(now_ms);
                    // Never provisional. When it was, every run in the chain
                    // declined to report and each failure asked for another,
                    // so a genuinely broken file span forever in silence.
                    Step_Run { provisional: false }
                } else {
                    Step_Wait {  }
                }
            },
            _ => Step_Wait {  },
        }
    }

    /// The outcome of the run this rule asked for. An AUTHORITATIVE failure
    /// must not ask for another, or the error is reported, re-run, reported
    /// again.
    function finished(self, provisional: bool, ok: bool) -> void {
        if (!provisional && !ok) {
            self.dirty = false;
        }
    }

    function start_cooling(self, now_ms: int) -> void {
        self.cooling_until = now_ms + self.window_ms;
    }
}
