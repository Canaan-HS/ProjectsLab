package subtitle

import (
	"path/filepath"
	"strings"
)

func GetFilenameLanguage(
	filename string,
) string {

	name := strings.TrimSuffix(
		filepath.Base(filename),
		filepath.Ext(filename),
	)

	parts := strings.Split(
		name,
		".",
	)

	if len(parts) < 2 {
		return ""
	}

	lang := strings.ToLower(
		parts[len(parts)-1],
	)

	switch lang {

	case "tc",
		"sc",
		"en",
		"jp",
		"kr":

		return lang

	}

	return ""
}
