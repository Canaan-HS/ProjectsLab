package operation

import (
	"fmt"
	"path/filepath"

	"SubtitleTool/internal/ffmpeg"
	"SubtitleTool/internal/output"
	"SubtitleTool/internal/subtitle"
	"SubtitleTool/internal/types"
)

func Remove(
	video string,
	opt types.Options,
) {
	info, err := ffmpeg.Probe(video)

	if err != nil {
		fmt.Printf(" ✗ Error: probe failed: %v\n", err)
		return
	}

	var removeTracks []types.SubtitleTrack

	if len(opt.Languages) == 0 {
		removeTracks = info.Subtitles
	} else {
		for _, sub := range info.Subtitles {
			for _, lang := range opt.Languages {
				if subtitle.MatchLanguage(sub, lang) {
					removeTracks = append(removeTracks, sub)
					break
				}
			}
		}
	}

	if len(removeTracks) == 0 {
		return
	}

	outPath := output.NewPath(video, "remove", opt.OutputPath)

	fmt.Printf(" → Removing %d subtitle track(s) from: %s\n", len(removeTracks), filepath.Base(video))

	err = ffmpeg.RemoveSubtitle(
		video,
		info.Subtitles,
		removeTracks,
		outPath,
	)

	if err != nil {
		fmt.Printf(" ✗ Error: remove failed: %v\n", err)
		return
	}

	fmt.Printf(" ✓ Done → %s\n", filepath.Base(outPath))
	fmt.Println()
}
