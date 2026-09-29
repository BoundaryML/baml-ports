package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"

	"github.com/yuin/goldmark/v2/extension"
	"github.com/yuin/goldmark/v2/parser"
	"github.com/yuin/goldmark/v2/renderer/html"
)

type pair struct {
	Input  string `json:"input"`
	Output string `json:"output"`
}

func main() {
	var pairs []pair
	data, _ := os.ReadFile(os.Args[1])
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		_ = json.Unmarshal([]byte(s), &pairs)
	} else {
		_ = json.Unmarshal(data, &pairs)
	}
	mismatch := 0
	for i, pr := range pairs {
		p := parser.New(
			parser.WithAutoHeadingID(),
			parser.WithAttribute(),
			parser.WithExtensions(
				extension.NewDefinitionListParser(),
				extension.NewFootnoteParser(),
				extension.NewGFMParser(),
				extension.NewTypographerParser(),
				extension.NewLinkifyParser(),
				extension.NewTableParser(),
				extension.NewTaskListItemParser(),
			),
		)
		r := html.New(
			html.WithUnsafe(),
			html.WithXHTML(),
			html.WithExtensions(
				extension.NewDefinitionListHTMLRenderer(),
				extension.NewFootnoteHTMLRenderer(),
				extension.NewGFMHTMLRenderer(),
				extension.NewTableHTMLRenderer(),
				extension.NewTaskListItemHTMLRenderer(),
			),
		)
		src := []byte(pr.Input)
		var b bytes.Buffer
		_ = r.Render(&b, src, p.Parse(src))
		if b.String() != pr.Output {
			mismatch++
			if mismatch <= 8 {
				fmt.Printf("=== #%d input %q\n--- go:   %q\n--- baml: %q\n", i, pr.Input, b.String(), pr.Output)
			}
		}
	}
	fmt.Printf("total=%d mismatches=%d\n", len(pairs), mismatch)
}
