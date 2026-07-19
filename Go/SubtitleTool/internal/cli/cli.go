package cli

import (
	"errors"
	"flag"
	"strings"

	"SubtitleTool/internal/types"
)

func Parse() (types.Options, error) {

	var mode string
	var path string
	var lang string

	var recursive bool
	var dry bool
	var yes bool

	flag.StringVar(&mode, "mode", "", "extract/remove/embed")
	flag.StringVar(&path, "path", "", "video or folder")
	flag.StringVar(&lang, "lang", "", "tc,sc,en,jp,kr")

	flag.BoolVar(&recursive, "recursive", true, "")
	flag.BoolVar(&dry, "dry-run", false, "")
	flag.BoolVar(&yes, "yes", false, "")

	flag.Parse()

	if path == "" {
		return types.Options{}, errors.New("path required")
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
		return types.Options{}, errors.New("invalid mode")
	}

	var langs []string

	if lang != "" {
		langs = strings.Split(lang, ",")
	}

	return types.Options{

		Mode:      m,
		Path:      path,
		Languages: langs,
		Recursive: recursive,
		DryRun:    dry,
		Yes:       yes,
	}, nil

}
