package operation

import (
	"fmt"
	"path/filepath"

	"SubtitleTool/internal/ffmpeg"
	"SubtitleTool/internal/subtitle"
	"SubtitleTool/internal/types"
)

func Extract(
	video string,
	opt types.Options,
) {
	info, err := ffmpeg.Probe(video)

	if err != nil {
		fmt.Printf(" ✗ Error: probe failed: %v\n", err)
		return
	}

	fmt.Printf(" → Probing: %s\n", filepath.Base(video))
	fmt.Printf(" → Found %d subtitle track(s)\n", len(info.Subtitles))

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

		fmt.Printf(" → Extracting: %s\n", lang)

		err = ffmpeg.ExtractSubtitle(
			video,
			sub,
			lang,
			opt.OutputPath,
		)

		if err != nil {
			fmt.Printf("   ✗ Error: %v\n", err)
			continue
		}

		fmt.Printf("   ✓ Done\n")
		count++
	}

	if count == 0 {
		fmt.Printf("   No matching subtitle tracks found\n")
	}

	fmt.Println()
}
