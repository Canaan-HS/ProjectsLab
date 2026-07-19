package subtitle

import (
	"strings"

	"SubtitleTool/internal/types"
)

func ResolveLanguage(
	track types.SubtitleTrack,
) string {

	lang := strings.ToLower(track.Language)

	title := strings.ToLower(track.Title)

	switch {

	case lang == "chi":

		if strings.Contains(title, "gb") ||
			strings.Contains(title, "chs") ||
			strings.Contains(title, "simplified") {

			return "sc"
		}

		if strings.Contains(title, "big5") ||
			strings.Contains(title, "cht") ||
			strings.Contains(title, "traditional") {

			return "tc"
		}

	case lang == "eng":

		return "en"

	case lang == "jpn":

		return "jp"

	case lang == "kor":

		return "kr"

	}

	// 其他語言直接使用 ffprobe code
	if lang != "" {

		return lang
	}

	return "und"
}
