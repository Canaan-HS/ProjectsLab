package subtitle

import (
	"strings"

	"SubtitleTool/internal/types"
)

type langDef struct {
	ShortCode   string
	Ffprobe     string
	DisplayName string
	Aliases     []string
	Keywords    []string
}

var langDefs = []langDef{
	{
		ShortCode:   "tc",
		Ffprobe:     "chi",
		DisplayName: "Traditional Chinese",
		Aliases:     []string{"tc", "cht", "tchi", "zht", "traditional", "big5", "chi", "zh-tw", "zh_hk", "zh-hk"},
		Keywords:    []string{"big5", "traditional", "cht"},
	},
	{
		ShortCode:   "sc",
		Ffprobe:     "chi",
		DisplayName: "Simplified Chinese",
		Aliases:     []string{"sc", "chs", "zhs", "simplified", "gb", "zh-cn", "zh_cn"},
		Keywords:    []string{"gb", "simplified", "chs"},
	},
	{
		ShortCode:   "en",
		Ffprobe:     "eng",
		DisplayName: "English",
		Aliases:     []string{"en", "eng", "english", "us", "uk"},
		Keywords:    []string{"english"},
	},
	{
		ShortCode:   "jp",
		Ffprobe:     "jpn",
		DisplayName: "Japanese",
		Aliases:     []string{"jp", "jpn", "japanese", "ja"},
		Keywords:    []string{"japanese"},
	},
	{
		ShortCode:   "kr",
		Ffprobe:     "kor",
		DisplayName: "Korean",
		Aliases:     []string{"kr", "kor", "korean", "ko", "hangul"},
		Keywords:    []string{"korean"},
	},
}

var aliasMap map[string]*langDef

func init() {
	aliasMap = make(map[string]*langDef)
	for i := range langDefs {
		for _, a := range langDefs[i].Aliases {
			aliasMap[a] = &langDefs[i]
		}
	}
}

func GetDisplayName(code string) string {
	code = strings.ToLower(code)
	if d, ok := aliasMap[code]; ok {
		return d.DisplayName
	}
	return ""
}

func GetFfprobe(code string) string {
	code = strings.ToLower(code)
	if d, ok := aliasMap[code]; ok {
		return d.Ffprobe
	}
	return ""
}

func ResolveSubtitleLanguage(path string) (ffprobeLang, displayName string) {
	detected := GetFilenameLanguage(path)
	if detected == "" {
		return "", "Undetermined"
	}
	return GetFfprobe(detected), GetDisplayName(detected)
}

func MatchLanguage(track types.SubtitleTrack, target string) bool {
	target = strings.ToLower(target)
	lang := strings.ToLower(track.Language)
	title := strings.ToLower(track.Title)

	d, ok := aliasMap[target]
	if ok {
		return lang == d.Ffprobe || containsAny(title, d.Keywords)
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
