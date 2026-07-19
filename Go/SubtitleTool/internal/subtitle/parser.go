package subtitle

import (
	"path/filepath"
	"strings"
)

func ParseSubtitleFilename(
	filename string,
) (string, string) {

	name := strings.TrimSuffix(
		filepath.Base(filename),
		filepath.Ext(filename),
	)

	parts := strings.Split(
		name,
		".",
	)

	if len(parts) < 2 {
		return "", ""
	}

	code := strings.ToLower(
		parts[len(parts)-1],
	)

	switch code {

	case "tc":
		return "tc", "TC"

	case "sc":
		return "sc", "SC"

	case "en":
		return "en", "EN"

	case "jp":
		return "jp", "JP"

	case "kr":
		return "kr", "KR"

	default:
		return code, code
	}

}
