// Checks the `std` path shims against std::path results printed by rustc.

testset "path" {
    test "path_0" {
        let p = "";
        assert.equal(path_parent(p), null);
        assert.equal(path_file_name(p), null);
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), null);
        assert.equal(path_with_extension(p, "css"), "");
        assert.equal(path_join("base/dir", p), "base/dir/");
        assert.equal(path_components(p), [])
    }
    test "path_1" {
        let p = "/";
        assert.equal(path_parent(p), null);
        assert.equal(path_file_name(p), null);
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), null);
        assert.equal(path_with_extension(p, "css"), "/");
        assert.equal(path_join("base/dir", p), "/");
        assert.equal(path_components(p), ["/"])
    }
    test "path_2" {
        let p = "a";
        assert.equal(path_parent(p), "");
        assert.equal(path_file_name(p), "a");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "a");
        assert.equal(path_with_extension(p, "css"), "a.css");
        assert.equal(path_join("base/dir", p), "base/dir/a");
        assert.equal(path_components(p), ["a"])
    }
    test "path_3" {
        let p = "a/b";
        assert.equal(path_parent(p), "a");
        assert.equal(path_file_name(p), "b");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "b");
        assert.equal(path_with_extension(p, "css"), "a/b.css");
        assert.equal(path_join("base/dir", p), "base/dir/a/b");
        assert.equal(path_components(p), ["a", "b"])
    }
    test "path_4" {
        let p = "/a/b/";
        assert.equal(path_parent(p), "/a");
        assert.equal(path_file_name(p), "b");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "b");
        assert.equal(path_with_extension(p, "css"), "/a/b.css");
        assert.equal(path_join("base/dir", p), "/a/b/");
        assert.equal(path_components(p), ["/", "a", "b"])
    }
    test "path_5" {
        let p = "a//b";
        assert.equal(path_parent(p), "a");
        assert.equal(path_file_name(p), "b");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "b");
        assert.equal(path_with_extension(p, "css"), "a//b.css");
        assert.equal(path_join("base/dir", p), "base/dir/a//b");
        assert.equal(path_components(p), ["a", "b"])
    }
    test "path_6" {
        let p = "./a";
        assert.equal(path_parent(p), ".");
        assert.equal(path_file_name(p), "a");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "a");
        assert.equal(path_with_extension(p, "css"), "./a.css");
        assert.equal(path_join("base/dir", p), "base/dir/./a");
        assert.equal(path_components(p), [".", "a"])
    }
    test "path_7" {
        let p = "a/./b";
        assert.equal(path_parent(p), "a");
        assert.equal(path_file_name(p), "b");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "b");
        assert.equal(path_with_extension(p, "css"), "a/./b.css");
        assert.equal(path_join("base/dir", p), "base/dir/a/./b");
        assert.equal(path_components(p), ["a", "b"])
    }
    test "path_8" {
        let p = "a/..";
        assert.equal(path_parent(p), "a");
        assert.equal(path_file_name(p), null);
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), null);
        assert.equal(path_with_extension(p, "css"), "a/..");
        assert.equal(path_join("base/dir", p), "base/dir/a/..");
        assert.equal(path_components(p), ["a", ".."])
    }
    test "path_9" {
        let p = "../a";
        assert.equal(path_parent(p), "..");
        assert.equal(path_file_name(p), "a");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "a");
        assert.equal(path_with_extension(p, "css"), "../a.css");
        assert.equal(path_join("base/dir", p), "base/dir/../a");
        assert.equal(path_components(p), ["..", "a"])
    }
    test "path_10" {
        let p = "foo.tar.gz";
        assert.equal(path_parent(p), "");
        assert.equal(path_file_name(p), "foo.tar.gz");
        assert.equal(path_extension(p), "gz");
        assert.equal(path_file_stem(p), "foo.tar");
        assert.equal(path_with_extension(p, "css"), "foo.tar.css");
        assert.equal(path_join("base/dir", p), "base/dir/foo.tar.gz");
        assert.equal(path_components(p), ["foo.tar.gz"])
    }
    test "path_11" {
        let p = ".bashrc";
        assert.equal(path_parent(p), "");
        assert.equal(path_file_name(p), ".bashrc");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), ".bashrc");
        assert.equal(path_with_extension(p, "css"), ".bashrc.css");
        assert.equal(path_join("base/dir", p), "base/dir/.bashrc");
        assert.equal(path_components(p), [".bashrc"])
    }
    test "path_12" {
        let p = "foo.";
        assert.equal(path_parent(p), "");
        assert.equal(path_file_name(p), "foo.");
        assert.equal(path_extension(p), "");
        assert.equal(path_file_stem(p), "foo");
        assert.equal(path_with_extension(p, "css"), "foo.css");
        assert.equal(path_join("base/dir", p), "base/dir/foo.");
        assert.equal(path_components(p), ["foo."])
    }
    test "path_13" {
        let p = "/x/y.scss";
        assert.equal(path_parent(p), "/x");
        assert.equal(path_file_name(p), "y.scss");
        assert.equal(path_extension(p), "scss");
        assert.equal(path_file_stem(p), "y");
        assert.equal(path_with_extension(p, "css"), "/x/y.css");
        assert.equal(path_join("base/dir", p), "/x/y.scss");
        assert.equal(path_components(p), ["/", "x", "y.scss"])
    }
    test "path_14" {
        let p = "dir/_part.scss";
        assert.equal(path_parent(p), "dir");
        assert.equal(path_file_name(p), "_part.scss");
        assert.equal(path_extension(p), "scss");
        assert.equal(path_file_stem(p), "_part");
        assert.equal(path_with_extension(p, "css"), "dir/_part.css");
        assert.equal(path_join("base/dir", p), "base/dir/dir/_part.scss");
        assert.equal(path_components(p), ["dir", "_part.scss"])
    }
    test "path_15" {
        let p = "a/b/c.d/e";
        assert.equal(path_parent(p), "a/b/c.d");
        assert.equal(path_file_name(p), "e");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "e");
        assert.equal(path_with_extension(p, "css"), "a/b/c.d/e.css");
        assert.equal(path_join("base/dir", p), "base/dir/a/b/c.d/e");
        assert.equal(path_components(p), ["a", "b", "c.d", "e"])
    }
    test "path_16" {
        let p = ".";
        assert.equal(path_parent(p), "");
        assert.equal(path_file_name(p), null);
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), null);
        assert.equal(path_with_extension(p, "css"), ".");
        assert.equal(path_join("base/dir", p), "base/dir/.");
        assert.equal(path_components(p), ["."])
    }
    test "path_17" {
        let p = "..";
        assert.equal(path_parent(p), "");
        assert.equal(path_file_name(p), null);
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), null);
        assert.equal(path_with_extension(p, "css"), "..");
        assert.equal(path_join("base/dir", p), "base/dir/..");
        assert.equal(path_components(p), [".."])
    }
    test "path_18" {
        let p = "/a";
        assert.equal(path_parent(p), "/");
        assert.equal(path_file_name(p), "a");
        assert.equal(path_extension(p), null);
        assert.equal(path_file_stem(p), "a");
        assert.equal(path_with_extension(p, "css"), "/a.css");
        assert.equal(path_join("base/dir", p), "/a");
        assert.equal(path_components(p), ["/", "a"])
    }
}
