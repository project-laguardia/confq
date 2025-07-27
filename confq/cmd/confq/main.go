package main

import (
	"io"
	"os"

	"github.com/project-laguardia/confq/internal/cli"

	_ "github.com/tomwright/dasel/parsing/csv"
	_ "github.com/tomwright/dasel/parsing/d"
	_ "github.com/tomwright/dasel/parsing/hcl"
	_ "github.com/tomwright/dasel/parsing/json"
	_ "github.com/tomwright/dasel/parsing/toml"
	_ "github.com/tomwright/dasel/parsing/xml"
	_ "github.com/tomwright/dasel/parsing/yaml"
)

func main() {
	var stdin io.Reader = os.Stdin

	stat, err := os.Stdin.Stat()
	if err != nil || (stat.Mode() & os.ModeNamedPipe) == 0 {
		stdin = nil
	}
	cli.MustRun(stdin, os.Stdout, os.Stderr)
}