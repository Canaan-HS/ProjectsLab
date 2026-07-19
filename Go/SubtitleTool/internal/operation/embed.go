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

	subs := subtitle.FindExternalSubtitles(video)

	if len(subs) == 0 {
		return
	}

	outPath := output.NewPath(video)

	fmt.Printf(" → Embedding %d subtitle(s) into: %s\n", len(subs), filepath.Base(video))

	err = ffmpeg.EmbedSubtitle(
		video,
		len(info.Subtitles),
		subs,
		outPath,
	)

	if err != nil {
		fmt.Printf(" ✗ Error: embed failed: %v\n", err)
		return
	}

	fmt.Printf(" ✓ Done → %s\n", filepath.Base(outPath))
	fmt.Println()
}
