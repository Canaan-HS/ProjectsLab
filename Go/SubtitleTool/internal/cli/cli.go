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

	var mode, path, lang, sub, output string
	var recursive, showHelp, overwrite bool

	fs.StringVar(&mode, "mode", "", "")
	fs.StringVar(&mode, "m", "", "")
	fs.StringVar(&path, "input", "", "")
	fs.StringVar(&path, "i", "", "")
	fs.StringVar(&output, "output", "", "")
	fs.StringVar(&output, "o", "", "")
	fs.StringVar(&lang, "lang", "", "")
	fs.StringVar(&lang, "l", "", "")
	fs.StringVar(&sub, "sub", "", "")
	fs.StringVar(&sub, "s", "", "")
	fs.BoolVar(&recursive, "recursive", true, "")
	fs.BoolVar(&recursive, "r", true, "")
	fs.BoolVar(&overwrite, "overwrite", false, "")
	fs.BoolVar(&overwrite, "ow", false, "")
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
		fmt.Fprintln(os.Stderr, "Error: -input is required")
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

	if overwrite && m == types.Extract {
		fmt.Fprintln(os.Stderr, "Warning: -overwrite is not supported for extract mode")
		fmt.Fprintln(os.Stderr)
		overwrite = false
	}

	var langs []string

	if lang != "" {
		langs = strings.Split(lang, ",")
	}

	return types.Options{
		Mode:         m,
		Path:         path,
		OutputPath:   output,
		Languages:    langs,
		SubtitlePath: sub,
		Recursive:    recursive,
		Overwrite:    overwrite,
	}, nil
}

func UsageText(exe string) string {
	return exe + ` - MKV Subtitle Manager

Usage:
  ` + exe + ` -mode <mode> -input <path> [options]

Modes:
  extract    Extract subtitle tracks from MKV files
  remove     Remove subtitle tracks from MKV files
  embed      Embed external subtitles into MKV files

Options:
  -m, -mode <mode>        Operation mode (required)
  -i, -input <path>       Video file or directory (required)
  -o, -output <path>      Output directory (default: same as input)
  -l, -lang <list>        Language filter: tc,sc,en,jp,kr (comma-separated)
  -s, -sub <file>         Subtitle file to embed (embed mode only, implies -input is a single file)
  -r, -recursive          Scan directories recursively (default: true)
  -ow, -overwrite         Overwrite original file (remove/embed only)
  -h, -help               Show this help message

Examples:
  ` + exe + ` -m extract -i video.mkv
  ` + exe + ` -m extract -i ./videos -l en,jp
  ` + exe + ` -m remove -i video.mkv -l jp
  ` + exe + ` -m remove -i video.mkv -l jp -ow
  ` + exe + ` -m embed -i video.mkv
  ` + exe + ` -m embed -i video.mkv -s subtitle.tc.srt
  ` + exe + ` -m embed -i video.mkv -s sub.cht.ass -ow
`
}
