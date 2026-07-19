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

	if opt.Overwrite && len(opt.Languages) == 0 && len(info.Subtitles) > 1 {
		fmt.Printf(" ✗ Error: multiple subtitle tracks found (%d). Use -l to specify which to keep.\n", len(info.Subtitles))
		return
	}

	var removeTracks []types.SubtitleTrack

	if opt.Overwrite {
		for _, sub := range info.Subtitles {
			keep := false
			for _, lang := range opt.Languages {
				if subtitle.MatchLanguage(sub, lang) {
					keep = true
					break
				}
			}
			if !keep {
				removeTracks = append(removeTracks, sub)
			}
		}
	} else if len(opt.Languages) == 0 {
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
		fmt.Printf("   No subtitle tracks to remove\n")
		fmt.Println()
		return
	}

	outPath := output.ResolvePath(video, "remove", opt.OutputPath, opt.Overwrite)

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

	if opt.Overwrite {
		output.FinalizeOverwrite(video, outPath)
	}

	fmt.Println()
}
