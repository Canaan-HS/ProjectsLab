package ffmpeg

import (
	"fmt"
	"path/filepath"

	"SubtitleTool/internal/types"
)

func ExtractSubtitle(
	video string,
	track types.SubtitleTrack,
	lang string,
	outputDir string,
) error {
	base := filepath.Base(video)
	name := base[:len(base)-len(filepath.Ext(base))]
	filename := name + "." + lang + "." + track.Extension()

	output := ""
	if outputDir == "" {
		output = filepath.Join(filepath.Dir(video), filename)
	} else {
		output = filepath.Join(outputDir, filename)
	}

	args := commonArgs(video)
	args = append(args,
		"-map", fmt.Sprintf("0:%d", track.Index),
		output,
	)

	return runFFmpeg(args)
}
