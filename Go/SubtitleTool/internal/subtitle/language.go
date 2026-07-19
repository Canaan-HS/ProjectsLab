package subtitle

import (
	"strings"

	"SubtitleTool/internal/types"
)

type langDef struct {
	ShortCode string
	Ffprobe   string
	Keywords  []string
}

var langDefs = []langDef{
	{ShortCode: "tc", Ffprobe: "chi", Keywords: []string{"big5", "traditional", "cht"}},
	{ShortCode: "sc", Ffprobe: "chi", Keywords: []string{"gb", "simplified", "chs"}},
	{ShortCode: "en", Ffprobe: "eng", Keywords: []string{"english"}},
	{ShortCode: "jp", Ffprobe: "jpn", Keywords: []string{"japanese"}},
	{ShortCode: "kr", Ffprobe: "kor", Keywords: []string{"korean"}},
}

func MatchLanguage(track types.SubtitleTrack, target string) bool {
	target = strings.ToLower(target)
	lang := strings.ToLower(track.Language)
	title := strings.ToLower(track.Title)

	for _, d := range langDefs {
		if d.ShortCode == target {
			return lang == d.Ffprobe || containsAny(title, d.Keywords)
		}
	}

	return lang == target
}

func ResolveLanguage(track types.SubtitleTrack) string {
	lang := strings.ToLower(track.Language)
	title := strings.ToLower(track.Title)

	for _, d := range langDefs {
		if lang == d.Ffprobe && containsAny(title, d.Keywords) {
			return d.ShortCode
		}
	}

	if lang == "chi" {
		return "tc"
	}

	if lang != "" {
		return lang
	}

	return "und"
}

func containsAny(s string, keywords []string) bool {
	for _, kw := range keywords {
		if strings.Contains(s, kw) {
			return true
		}
	}
	return false
}
