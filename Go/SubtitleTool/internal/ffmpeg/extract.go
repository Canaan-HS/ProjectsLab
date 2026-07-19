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
) error {
	dir := filepath.Dir(video)
	base := filepath.Base(video)
	name := base[:len(base)-len(filepath.Ext(base))]

	output := filepath.Join(
		dir,
		name+"."+lang+"."+track.Extension(),
	)

	args := commonArgs(video)
	args = append(args,
		"-map", fmt.Sprintf("0:%d", track.Index),
		output,
	)

	return runFFmpeg(args)
}
