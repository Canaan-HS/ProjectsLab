package subtitle

import (
	"strings"

	"SubtitleTool/internal/types"
)

func MatchLanguage(track types.SubtitleTrack, target string) bool {

	target = strings.ToLower(target)

	lang := strings.ToLower(track.Language)

	title := strings.ToLower(track.Title)

	switch target {

	case "tc":

		return strings.Contains(title, "big5") ||
			strings.Contains(title, "traditional") ||
			strings.Contains(title, "cht")

	case "sc":

		return strings.Contains(title, "gb") ||
			strings.Contains(title, "simplified") ||
			strings.Contains(title, "chs")

	case "en":

		return lang == "eng" ||
			strings.Contains(title, "english")

	case "jp":

		return lang == "jpn" ||
			strings.Contains(title, "japanese")

	case "kr":

		return lang == "kor" ||
			strings.Contains(title, "korean")

	}

	return lang == target
}
