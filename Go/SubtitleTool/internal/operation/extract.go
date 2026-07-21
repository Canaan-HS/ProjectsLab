package operation

import (
	"fmt"
	"path/filepath"

	"SubtitleTool/internal/ffmpeg"
	"SubtitleTool/internal/progress"
	"SubtitleTool/internal/subtitle"
	"SubtitleTool/internal/types"
)

func Extract(
	video string,
	opt types.Options,
	r progress.Reporter,
) error {
	info, err := ffmpeg.Probe(video)

	if err != nil {
		return fmt.Errorf("probe failed: %w", err)
	}

	r.Log("Found %d subtitle track(s) in %s", len(info.Subtitles), filepath.Base(video))

	count := 0

	for _, sub := range info.Subtitles {
		lang := ""

		if len(opt.Languages) == 0 {
			lang = subtitle.ResolveLanguage(sub)
		} else {
			for _, target := range opt.Languages {
				if subtitle.MatchLanguage(sub, target) {
					lang = target
					break
				}
			}
		}

		if lang == "" {
			continue
		}

		err = ffmpeg.ExtractSubtitle(
			video,
			sub,
			lang,
			opt.OutputPath,
		)

		if err != nil {
			r.Log("  ✗ failed to extract %s: %v", lang, err)
			continue
		}

		count++
	}

	if count == 0 {
		r.Log("No matching subtitle tracks found")
		return nil
	}

	return nil
}
