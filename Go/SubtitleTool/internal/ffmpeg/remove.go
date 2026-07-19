package ffmpeg

import (
	"fmt"
	"os"
	"os/exec"

	"SubtitleTool/internal/types"
)

func RemoveSubtitle(
	video string,
	allTracks []types.SubtitleTrack,
	removeTracks []types.SubtitleTrack,
	output string,
) error {
	removeMap := make(map[int]bool)

	for _, track := range removeTracks {
		removeMap[track.Index] = true
	}

	args := commonArgs(video)

	args = append(args,
		"-map", "0:v?",
		"-map", "0:a?",
		"-map", "0:t?",
	)

	for _, track := range allTracks {
		if removeMap[track.Index] {
			continue
		}

		args = append(args,
			"-map",
			fmt.Sprintf("0:%d", track.Index),
		)
	}

	args = append(args, suffixArgs(output)...)

	cmd := exec.Command("ffmpeg", args...)
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
