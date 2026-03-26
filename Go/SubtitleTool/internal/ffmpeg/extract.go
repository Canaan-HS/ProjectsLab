package ffmpeg

import (
	"fmt"
	"os"
	"os/exec"
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

	cmd := exec.Command("ffmpeg", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
