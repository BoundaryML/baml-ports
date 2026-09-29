// Port of tests/doc/YAML-1.1.spec.ts

function tspec11_warn(tag: string) -> map<string, unknown> {
  { "message": `Unresolved tag: ${tag}` }
}

testset "doc/YAML-1.1.spec" {
  test "Use preceding directives if none defined" {
    let src = source(`
    !bar "First document"
    ...
    %TAG ! !foo
    ---
    !bar "With directives"
    ---
    !bar "Using previous TAG directive"
    ...
    %YAML 1.1
    ---
    !bar "Reset settings"
    ---
    !bar "Using previous YAML directive"
  `);
    let docs = parseAllDocuments(src, Options { prettyErrors: false, version: "1.1" }).docs;
    expect_toMatchObject(docs, [
      {
        "directives": { "yaml": { "version": "1.1", "explicit": false } },
        "errors": [],
        "warnings": [tspec11_warn("!bar")],
      },
      {
        "directives": { "yaml": { "version": "1.1", "explicit": false } },
        "errors": [],
        "warnings": [tspec11_warn("!foobar")],
      },
      {
        "directives": { "yaml": { "version": "1.1", "explicit": false } },
        "errors": [],
        "warnings": [tspec11_warn("!foobar")],
      },
      {
        "directives": { "yaml": { "version": "1.1", "explicit": true } },
        "errors": [],
        "warnings": [tspec11_warn("!bar")],
      },
      {
        "directives": { "yaml": { "version": "1.1", "explicit": true } },
        "errors": [],
        "warnings": [tspec11_warn("!bar")],
      },
    ]);
    expect_toMatchObject(docs.map((doc: Document) -> string { doc.toString(null) }), [
      "!bar \"First document\"\n...\n",
      "%TAG ! !foo\n---\n!bar \"With directives\"\n",
      "%TAG ! !foo\n---\n!bar \"Using previous TAG directive\"\n...\n",
      "%YAML 1.1\n---\n!bar \"Reset settings\"\n",
      "%YAML 1.1\n---\n!bar \"Using previous YAML directive\"\n",
    ])
  }
}
