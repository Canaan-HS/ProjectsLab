package subtitle

import (
	"path/filepath"
	"strings"
)

func GetFilenameLanguage(filename string) string {
	name := strings.TrimSuffix(filepath.Base(filename), filepath.Ext(filename))
	parts := strings.Split(name, ".")
	if len(parts) < 2 {
		return ""
	}
	code := strings.ToLower(parts[len(parts)-1])
	for _, d := range langDefs {
		if d.ShortCode == code {
			return code
		}
	}
	return ""
}
