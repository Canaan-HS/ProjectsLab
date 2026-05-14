package operation

import (
	"fmt"
	"path/filepath"

	"SubtitleTool/internal/ffmpeg"
	"SubtitleTool/internal/output"
	"SubtitleTool/internal/subtitle"
	"SubtitleTool/internal/types"
)

func Embed(
	video string,
	opt types.Options,
) {
	info, err := ffmpeg.Probe(video)

	if err != nil {
		fmt.Printf(" ✗ Error: probe failed: %v\n", err)
		return
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

		fmt.Printf(" → Using subtitle: %s (%s)\n", filepath.Base(opt.SubtitlePath), displayName)
	} else {
		subs = subtitle.FindExternalSubtitles(video)
	}

	if len(subs) == 0 {
		fmt.Printf("   No external subtitle files found\n")
		fmt.Println()
		return
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

	var outPath string
	if opt.Overwrite {
		outPath = output.OverwritePath(video, opt.OutputPath)
	} else {
		outPath = output.NewPath(video, "embed", opt.OutputPath)
	}

	fmt.Printf(" → Embedding %d subtitle(s) into: %s\n", len(subs), filepath.Base(video))

	err = ffmpeg.EmbedSubtitle(
		video,
		keepTracks,
		subs,
		outPath,
	)

	if err != nil {
		fmt.Printf(" ✗ Error: embed failed: %v\n", err)
		return
	}

	fmt.Printf(" ✓ Done → %s\n", filepath.Base(outPath))

	if opt.Overwrite {
		extra := make([]string, len(subs))
		for i, s := range subs {
			extra[i] = s.Path
		}
		output.FinalizeOverwrite(video, outPath, extra...)
	}

	fmt.Println()
}
