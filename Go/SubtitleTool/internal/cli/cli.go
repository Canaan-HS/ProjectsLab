package cli

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"SubtitleTool/internal/types"
)

var ErrHelp = errors.New("help requested")

func Parse() (types.Options, error) {
	fs := flag.NewFlagSet("SubtitleTool", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)

	var mode, path, lang, sub string
	var recursive, dry, yes, showHelp bool

	fs.StringVar(&mode, "mode", "", "")
	fs.StringVar(&mode, "m", "", "")
	fs.StringVar(&path, "path", "", "")
	fs.StringVar(&path, "p", "", "")
	fs.StringVar(&lang, "lang", "", "")
	fs.StringVar(&lang, "l", "", "")
	fs.StringVar(&sub, "sub", "", "")
	fs.StringVar(&sub, "s", "", "")
	fs.BoolVar(&recursive, "recursive", true, "")
	fs.BoolVar(&recursive, "r", true, "")
	fs.BoolVar(&dry, "dry-run", false, "")
	fs.BoolVar(&yes, "yes", false, "")
	fs.BoolVar(&yes, "y", false, "")
	fs.BoolVar(&showHelp, "help", false, "")
	fs.BoolVar(&showHelp, "h", false, "")

	fs.Usage = func() {
		fmt.Fprint(os.Stderr, UsageText(filepath.Base(os.Args[0])))
	}

	if err := fs.Parse(os.Args[1:]); err != nil {
		return types.Options{}, ErrHelp
	}

	if showHelp {
		fs.Usage()
		return types.Options{}, ErrHelp
	}

	if mode == "" {
		fmt.Fprintln(os.Stderr, "Error: -mode is required")
		fmt.Fprintln(os.Stderr)
		fs.Usage()
		return types.Options{}, ErrHelp
	}

	if path == "" {
		fmt.Fprintln(os.Stderr, "Error: -path is required")
		fmt.Fprintln(os.Stderr)
		fs.Usage()
		return types.Options{}, ErrHelp
	}

	var m types.Mode

	switch mode {
	case "extract":
		m = types.Extract
	case "remove":
		m = types.Remove
	case "embed":
		m = types.Embed
	default:
		fmt.Fprintf(os.Stderr, "Error: invalid mode %q (must be extract, remove, or embed)\n", mode)
		fmt.Fprintln(os.Stderr)
		fs.Usage()
		return types.Options{}, ErrHelp
	}

	if sub != "" && m != types.Embed {
		fmt.Fprintln(os.Stderr, "Error: -sub can only be used with -mode embed")
		fmt.Fprintln(os.Stderr)
		fs.Usage()
		return types.Options{}, ErrHelp
	}

	var langs []string

	if lang != "" {
		langs = strings.Split(lang, ",")
	}

	return types.Options{
		Mode:         m,
		Path:         path,
		Languages:    langs,
		SubtitlePath: sub,
		Recursive:    recursive,
		DryRun:       dry,
		Yes:          yes,
	}, nil
}

func UsageText(exe string) string {
	return exe + ` - MKV Subtitle Manager

Usage:
  ` + exe + ` -mode <mode> -path <path> [options]

Modes:
  extract    Extract subtitle tracks from MKV files
  remove     Remove subtitle tracks from MKV files
  embed      Embed external subtitles into MKV files

Options:
  -m, -mode <mode>       Operation mode (required)
  -p, -path <path>       Video file or directory (required)
  -l, -lang <list>       Language filter: tc,sc,en,jp,kr (comma-separated)
  -s, -sub <file>        Subtitle file to embed (embed mode only, implies -path is a single file)
  -r, -recursive         Scan directories recursively (default: true)
  -y, -yes               Skip confirmation prompts
      -dry-run           Preview changes without applying
  -h, -help              Show this help message

Examples:
  ` + exe + ` -m extract -p video.mkv
  ` + exe + ` -m extract -p ./videos -l en,jp
  ` + exe + ` -m remove -p video.mkv -l jp
  ` + exe + ` -m embed -p video.mkv
  ` + exe + ` -m embed -p video.mkv -s subtitle.tc.srt
`
}
