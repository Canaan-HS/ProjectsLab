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

func Embed(
	video string,
	opt types.Options,
	r progress.Reporter,
) (bool, error) {
	info, err := ffmpeg.Probe(video)

	if err != nil {
		return false, fmt.Errorf("probe failed: %w", err)
	}

	var subs []types.ExternalSubtitle

	if opt.SubtitlePath != "" {
		ffprobeLang, displayName := subtitle.ResolveSubtitleLanguage(
			opt.SubtitlePath,
		)

		subs = []types.ExternalSubtitle{
			{
				Path:     opt.SubtitlePath,
				Language: ffprobeLang,
				Title:    displayName,
			},
		}

		r.Log("Using subtitle: %s (%s)", filepath.Base(opt.SubtitlePath), displayName)
	} else {
		subs = subtitle.FindExternalSubtitles(video)
	}

	if len(subs) == 0 {
		r.Log("No external subtitle files found")
		return false, nil
	}

	var keepTracks []types.SubtitleTrack

	if opt.Overwrite {
		if len(opt.Languages) > 0 {
			for _, sub := range info.Subtitles {
				for _, lang := range opt.Languages {
					if subtitle.MatchLanguage(sub, lang) {
						keepTracks = append(keepTracks, sub)
						break
					}
				}
			}
		} else {
			keepTracks = []types.SubtitleTrack{}
		}
	}

	outPath := output.ResolvePath(video, "embed", opt.OutputPath, opt.Overwrite)

	r.Log("Embedding %d subtitle(s)", len(subs))

	err = ffmpeg.EmbedSubtitle(
		video,
		keepTracks,
		subs,
		outPath,
	)

	if err != nil {
		return false, fmt.Errorf("embed failed: %w", err)
	}

	r.Log("✓ Done → %s", filepath.Base(outPath))

	if opt.Overwrite {
		extra := make([]string, len(subs))
		for i, s := range subs {
			extra[i] = s.Path
		}
		output.FinalizeOverwrite(video, outPath, extra...)
	}

	return true, nil
}
