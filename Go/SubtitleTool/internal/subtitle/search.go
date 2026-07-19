package subtitle

import (
	"os"
	"path/filepath"
	"strings"

	"SubtitleTool/internal/types"
)

func FindExternalSubtitles(
	video string,
) []types.ExternalSubtitle {

	dir := filepath.Dir(video)

	base := filepath.Base(video)

	name := strings.TrimSuffix(
		base,
		filepath.Ext(base),
	)

	var result []types.ExternalSubtitle

	files, err := os.ReadDir(dir)

	if err != nil {
		return result
	}

	for _, file := range files {

		if file.IsDir() {
			continue
		}

		ext := strings.ToLower(
			filepath.Ext(file.Name()),
		)

		if ext != ".ass" &&
			ext != ".ssa" &&
			ext != ".srt" {

			continue
		}

		filename := strings.TrimSuffix(
			file.Name(),
			ext,
		)

		if !strings.Contains(
			filename,
			name,
		) {

			continue
		}

		path := filepath.Join(
			dir,
			file.Name(),
		)

		ffprobeLang, displayName := ResolveSubtitleLanguage(
			file.Name(),
		)

		result = append(
			result,
			types.ExternalSubtitle{
				Path:     path,
				Language: ffprobeLang,
				Title:    displayName,
			},
		)

	}

	return result
}
