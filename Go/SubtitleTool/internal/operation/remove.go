package operation

import (
	"fmt"
	"path/filepath"

	"SubtitleTool/internal/ffmpeg"
	"SubtitleTool/internal/output"
	"SubtitleTool/internal/progress"
	"SubtitleTool/internal/subtitle"
	"SubtitleTool/internal/types"
)

func Remove(
	video string,
	opt types.Options,
	r progress.Reporter,
) (bool, error) {
	info, err := ffmpeg.Probe(video)

	if err != nil {
		return false, fmt.Errorf("probe failed: %w", err)
	}

	if opt.Overwrite && len(opt.Languages) == 0 && len(info.Subtitles) > 1 {
		return false, fmt.Errorf("multiple subtitle tracks found (%d). Use -l to specify which to keep", len(info.Subtitles))
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
		r.Log("No subtitle tracks to remove")
		return false, nil
	}

	outPath := output.ResolvePath(video, "remove", opt.OutputPath, opt.Overwrite)

	r.Log("Removing %d subtitle track(s)", len(removeTracks))

	err = ffmpeg.RemoveSubtitle(
		video,
		info.Subtitles,
		removeTracks,
		outPath,
	)

	if err != nil {
		return false, fmt.Errorf("remove failed: %w", err)
	}

	r.Log("✓ Done → %s", filepath.Base(outPath))

	if opt.Overwrite {
		output.FinalizeOverwrite(video, outPath)
	}

	return true, nil
}
