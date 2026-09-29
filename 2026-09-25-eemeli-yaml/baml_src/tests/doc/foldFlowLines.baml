// Port of tests/doc/foldFlowLines.ts
//
// `vi.fn()` onFold mocks are replaced by a MockCalls recorder; `beforeEach`
// option resets become a fresh `tffl_opts(calls)` per test.

function tffl_opts(calls: MockCalls) -> FoldOptions {
  FoldOptions {
    indentAtStart: 0,
    lineWidth: 10,
    minContentWidth: 0,
    onFold: () -> void { calls.record([]); },
  }
}

function tffl_map(n: unknown) -> YAMLMap {
  match (n) {
    let m: YAMLMap => m,
    _ => fail("expected YAMLMap, got " + t_show(n)),
  }
}

function tffl_seq(n: unknown) -> YAMLSeq {
  match (n) {
    let s: YAMLSeq => s,
    _ => fail("expected YAMLSeq, got " + t_show(n)),
  }
}

function tffl_scalar(n: unknown) -> Scalar {
  match (n) {
    let s: Scalar => s,
    _ => fail("expected Scalar, got " + t_show(n)),
  }
}

testset "doc/foldFlowLines" {
  testset "plain" {
    let src = "abc def ghi jkl mno pqr stu vwx yz\n";

    test "pass-through" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      options.lineWidth = 40;
      expect_toBe(foldFlowLines(src, "", FOLD_FLOW(), options), src);
      expect_toBe(calls.count(), 0)
    }

    test "simple" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      options.lineWidth = 20;
      expect_toBe(foldFlowLines(src, "", FOLD_FLOW(), options), "abc def ghi jkl mno\npqr stu vwx yz\n");
      expect_true(calls.count() > 0, "expected onFold to have been called")
    }

    test "multiple folds" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      expect_toBe(foldFlowLines(src, "", FOLD_FLOW(), options), "abc def\nghi jkl\nmno pqr\nstu vwx yz\n");
      expect_toBe(calls.count(), 1)
    }

    test "indent" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      expect_toBe(foldFlowLines(src, "  ", FOLD_FLOW(), options), "abc def\n  ghi jkl\n  mno pqr\n  stu vwx\n  yz\n")
    }

    test "indent > lineWidth" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      let indent = "        ";
      options.lineWidth = 7;
      let i = "\n" + indent;
      expect_toBe(foldFlowLines(src, indent, FOLD_FLOW(), options), `abc def${i}ghi${i}jkl${i}mno${i}pqr${i}stu${i}vwx${i}yz\n`)
    }

    test "indent > lineWidth, with minContentWidth" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      let indent = "        ";
      options.lineWidth = 7;
      options.minContentWidth = 7;
      let i = "\n" + indent;
      expect_toBe(foldFlowLines(src, indent, FOLD_FLOW(), options), `abc def${i}ghi jkl${i}mno pqr${i}stu vwx${i}yz\n`)
    }

    test "positive indentAtStart" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      options.indentAtStart = 8;
      expect_toBe(foldFlowLines(src, "", FOLD_FLOW(), options), "abc\ndef ghi\njkl mno\npqr stu\nvwx yz\n")
    }

    test "negative indentAtStart" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      options.indentAtStart = -8;
      expect_toBe(foldFlowLines(src, "", FOLD_FLOW(), options), "abc def ghi jkl\nmno pqr\nstu vwx yz\n")
    }

    test "doubled spaces" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      let src2 = "abc  def  ghi  jkl  mno  pqr  stu  vwx  yz\n";
      expect_toBe(foldFlowLines(src2, "", FOLD_FLOW(), options), src2);
      expect_toBe(calls.count(), 0)
    }
  }

  testset "double-quoted" {
    let src = "\"abc def ghi jkl mnopqrstuvwxyz\n\"";

    test "pass-through" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      options.lineWidth = 40;
      expect_toBe(foldFlowLines(src, "", FOLD_QUOTED(), options), src);
      expect_toBe(calls.count(), 0)
    }

    test "simple" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      options.lineWidth = 20;
      expect_toBe(foldFlowLines(src, "", FOLD_QUOTED(), options), "\"abc def ghi jkl\nmnopqrstuvwxyz\n\"");
      expect_true(calls.count() > 0, "expected onFold to have been called")
    }

    test "multiple folds" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      expect_toBe(foldFlowLines(src, "", FOLD_QUOTED(), options), "\"abc def\nghi jkl\nmnopqrstu\\\nvwxyz\n\"");
      expect_toBe(calls.count(), 1)
    }

    test "short lineWidth" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      options.lineWidth = 3;
      expect_toBe(foldFlowLines(src, "", FOLD_QUOTED(), options), "\"a\\\nbc\ndef\nghi\njkl\nmn\\\nop\\\nqr\\\nst\\\nuv\\\nwx\\\nyz\n\"")
    }

    test "doubled spaces" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      let src2 = "\"abc  def  ghi  jkl  mno  pqr  stu  vwx  yz\n\"";
      options.lineWidth = 9;
      expect_toBe(foldFlowLines(src2, "", FOLD_QUOTED(), options), "\"abc  de\\\nf  ghi  \\\njkl  mno  \\\npqr  stu  \\\nvwx  yz\n\"")
    }

    test "terminal whitespace" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      let src2 = "\" \t \t \t \t \tnext \t\"";
      expect_toBe(foldFlowLines(src2, "", FOLD_QUOTED(), options), "\" \t \t \t \t \t\\\nnext \t\"")
    }

    test "escape longer than lineWidth" {
      let calls = mock_calls();
      let options = tffl_opts(calls);
      let src2 = "\"foo\\U01234567\"";
      expect_toBe(foldFlowLines(src2, "", FOLD_QUOTED(), options), src2)
    }

    testset "Folding double-quoted strings" {
      testset "Split \\\" escape in double-quoted string (#48)" {
        test "minimal" {
          let calls = mock_calls();
          let options = tffl_opts(calls);
          let src2 = "\"01234567\\\"\"";
          expect_toBe(foldFlowLines(src2, "", FOLD_QUOTED(), options), "\"01234567\\\n\\\"\"");
          let src3 = "\"012345678\\\"\"";
          expect_toBe(foldFlowLines(src3, "", FOLD_QUOTED(), options), "\"012345678\\\n\\\"\"")
        }

        test "reported" {
          let x = "{\"module\":\"database\",\"props\":{\"databaseType\":\"postgresql\"},\"extra\":{},\"foo\":\"bar'\"}";
          let str = yaml_stringify({ "x": x });
          let doc = parseDocument(str, null);
          expect_toHaveLength(doc.errors, 0);
          expect_toBe(tffl_scalar(tffl_map(doc.value).get("x")).value, x)
        }
      }

      testset "Fold on multiple escaped characters" {
        test "minimal (#57)" {
          let calls = mock_calls();
          let options = tffl_opts(calls);
          let str = "\"0123\\\"\\\\ '\"";
          expect_toBe(foldFlowLines(str, "", FOLD_QUOTED(), options), "\"0123\\\"\\\\\n'\"")
        }

        test "reported (#57)" {
          let key2 = "!\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"#\"\\ '";
          let str = yaml_stringify([{ "key2": key2 }]);
          let res = yaml_parse(str);
          let first = js_as_object((js_as_array(res) ?? [])[0]) ?? {};
          expect_toBe(first.get("key2"), key2)
        }

        test "minimal (#59)" {
          let calls = mock_calls();
          let options = tffl_opts(calls);
          let str = "\"######\\\\P#\"";
          expect_toBe(foldFlowLines(str, "", FOLD_QUOTED(), options), "\"######\\\\\\\nP#\"")
        }

        test "reported (#59)" {
          let value = ">####################################\"##########################'####\\P#";
          let str = yaml_stringify({ "key": [[value]] });
          let doc = parseDocument(str, null);
          expect_toHaveLength(doc.errors, 0);
          let inner = tffl_seq(tffl_seq(tffl_map(doc.value).get("key")).at(0));
          expect_toBe(tffl_scalar(inner.at(0)).value, value)
        }
      }

      testset "Fold on escaped character (awslabs/cdk8s#494)" {
        test "slash" {
          let calls = mock_calls();
          let options = tffl_opts(calls);
          let str = "\"1234567\\\\ab\"";
          expect_toBe(foldFlowLines(str, "", FOLD_QUOTED(), options), "\"1234567\\\n\\\\ab\"")
        }

        test "null" {
          let calls = mock_calls();
          let options = tffl_opts(calls);
          let str = "\"1234567\\\0ab\"";
          expect_toBe(foldFlowLines(str, "", FOLD_QUOTED(), options), "\"1234567\\\n\\\0ab\"")
        }

        test "space" {
          let calls = mock_calls();
          let options = tffl_opts(calls);
          let str = "\"1234567\\ ab\"";
          expect_toBe(foldFlowLines(str, "", FOLD_QUOTED(), options), "\"1234567\\\n\\ ab\"")
        }
      }
    }

    testset "Folding input with excessive start indentation (#196)" {
      test "quoted" {
        let calls = mock_calls();
        let options = tffl_opts(calls);
        options.indentAtStart = 6;
        options.minContentWidth = 6;
        expect_toBe(foldFlowLines("\"ab cd ef gh\"", " ", FOLD_QUOTED(), options), "\n \"ab cd ef\n gh\"")
      }

      test "plain" {
        let calls = mock_calls();
        let options = tffl_opts(calls);
        options.indentAtStart = 6;
        options.minContentWidth = 6;
        expect_toBe(foldFlowLines("ab cd ef gh", " ", FOLD_FLOW(), options), "\n ab cd ef\n gh")
      }

      test "reported" {
        let input = {
          "testgljrisgjsrligjsrligsjrglisrjgrligjsligrjglisjgrlijgsrilgsejrfiwlahflirgjaelfjafil": "&cLorem ipsum dolor sit amet, consectetur adipiscing elit. Sed sed nibh ac metus elementum venenatis eu vitae diam. Etiam tristique suscipit mauris. Donec pulvinar sed nunc a gravida. Morbi nulla lacus, gravida eu elementum id, ultricies nec ipsum. Cras bibendum tellus ut mollis malesuada. Maecenas eleifend felis at fermentum hendrerit. Nulla porta vitae erat eget faucibus. Sed egestas viverra magna ac vulputate. Suspendisse vel posuere mauris, accumsan dapibus libero. Curabitur bibendum tellus in ex ultricies, quis tempus magna luctus. Maecenas maximus orci est, id fringilla lorem gravida sit amet. Pellentesque a rutrum lorem. Vestibulum ante ipsum primis in faucibus orci.",
        };
        expect_toBe(yaml_stringify(input), "testgljrisgjsrligjsrligsjrglisrjgrligjsligrjglisjgrlijgsrilgsejrfiwlahflirgjaelfjafil:\n  \"&cLorem ipsum dolor sit amet, consectetur adipiscing elit. Sed sed nibh ac\n  metus elementum venenatis eu vitae diam. Etiam tristique suscipit mauris.\n  Donec pulvinar sed nunc a gravida. Morbi nulla lacus, gravida eu elementum id,\n  ultricies nec ipsum. Cras bibendum tellus ut mollis malesuada. Maecenas\n  eleifend felis at fermentum hendrerit. Nulla porta vitae erat eget faucibus.\n  Sed egestas viverra magna ac vulputate. Suspendisse vel posuere mauris,\n  accumsan dapibus libero. Curabitur bibendum tellus in ex ultricies, quis\n  tempus magna luctus. Maecenas maximus orci est, id fringilla lorem gravida sit\n  amet. Pellentesque a rutrum lorem. Vestibulum ante ipsum primis in faucibus\n  orci.\"\n")
      }
    }
  }

  testset "block scalar" {
    test "Indented first line (#422)" {
      // BAML backtick strings drop the final newline that upstream's
      // source`...` keeps, so it is re-appended with `+ "\n"` throughout.
      let obj = {
        "nginx.ingress.kubernetes.io/configuration-snippet": source(`
          location ~* ^/sites/aaaaaaa.aa/files/(.+) {
            return 302 https://process.aaaaaaa.aa/sites/aaaaaaa.aa/files/$1;
          }
          location ~* ^/partner-application/cls/(.+) {
            return 301 https://process.aaaaaaa.aa/partner-application/cls/$1$is_args$args;
          }
          `) + "\n",
      };
      expect_toBe(yaml_stringify(obj), source(`
        nginx.ingress.kubernetes.io/configuration-snippet: >
          location ~* ^/sites/aaaaaaa.aa/files/(.+) {
            return 302 https://process.aaaaaaa.aa/sites/aaaaaaa.aa/files/$1;
          }

          location ~* ^/partner-application/cls/(.+) {
            return 301 https://process.aaaaaaa.aa/partner-application/cls/$1$is_args$args;
          }
      `) + "\n")
    }

    test "block scalar with very long lines (#585)" {
      let str = ("a".repeat(30) + "\n").repeat(3);
      expect_toBe(stringify(str, null, Options { lineWidth: 20 }), source(`
      |
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    `) + "\n")
    }
  }

  testset "end-to-end" {
    let foldOptions = Options { lineWidth: 20, minContentWidth: 0 };

    test "more-indented folded block" {
      let src = source(`
      > # comment with an excessive length that won't get folded
      Text on a line that
      should get folded
      with a line width of
      20 characters.

        Indented text
        that appears to be
      folded but is not.

        Text that is prevented from folding due to being more-indented.

      Unfolded paragraph.
    `) + "\n";
      let doc = parseDocument(src, null);
      expect_toBe(tffl_scalar(doc.value).value, source(`
      Text on a line that should get folded with a line width of 20 characters.

        Indented text
        that appears to be
      folded but is not.

        Text that is prevented from folding due to being more-indented.

      Unfolded paragraph.
    `) + "\n");
      expect_toBe(doc.toString(foldOptions), src)
    }

    test "More-indented first line (#55)" {
      let str = " first more-indented line\nnext line\n";
      let ys = stringify(str, null, foldOptions);
      expect_toBe(ys, ">1\n first more-indented line\nnext line\n")
    }

    test "plain string" {
      let src = source(`
      - plain value with
        enough length to
        fold twice
      - plain with comment # that won't get folded
    `) + "\n";
      let doc = parseDocument(src, null);
      let seq = tffl_seq(doc.value);
      expect_toBe(tffl_scalar(seq.at(0)).value, "plain value with enough length to fold twice");
      expect_toBe(tffl_scalar(seq.at(1)).value, "plain with comment");
      expect_toBe(doc.toString(foldOptions), src)
    }

    test "long line width" {
      let src = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. In laoreet massa eros, dignissim aliquam nunc elementum sit amet. Mauris pulvinar nunc eget ante sodales viverra. Vivamus quis convallis sapien, ut auctor magna. Cras volutpat erat eu lacus luctus facilisis. Aenean sapien leo, auctor sed tincidunt at, scelerisque a urna. Nunc ullamcorper, libero non mollis aliquet, nulla diam lobortis neque, ac rutrum dui nibh iaculis lectus. Aenean lobortis interdum arcu eget sollicitudin.\n\nDuis quam enim, ultricies a enim non, tincidunt lobortis ipsum. Mauris condimentum ultrices eros rutrum euismod. Fusce et mi eget quam dapibus blandit. Maecenas sodales tempor euismod. Phasellus vulputate purus felis, eleifend ullamcorper tortor semper sit amet. Sed nunc quam, iaculis et neque sit amet, consequat egestas lectus. Aenean dapibus lorem sed accumsan porttitor. Curabitur eu magna congue, mattis urna ac, lacinia eros. In in iaculis justo, nec faucibus enim. Fusce id viverra purus, nec ultricies mi. Aliquam eu risus risus. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Suspendisse potenti. \n";
      let exp = "|\n" + src;
      for (let lineWidth in [1000, 0, -1]) {
        expect_toBe(stringify(src, null, Options { lineWidth: lineWidth }), exp);
      }
    }

    test "multiple lines" {
      let src = source(`
      first line which is long enough to be wrapped to another line
      second line which is long enough to be wrapped to another line
       third line which is not wrapped because it's indented
      fourth line which is long enough to be wrapped to another line
    `) + "\n";
      expect_toBe(stringify({ "src": src }, null, Options { lineWidth: 20, minContentWidth: 0 }), source(`
      src: >
        first line which
        is long enough to
        be wrapped to
        another line

        second line which
        is long enough to
        be wrapped to
        another line
         third line which is not wrapped because it's indented
        fourth line which
        is long enough to
        be wrapped to
        another line
    `) + "\n")
    }
  }
}
