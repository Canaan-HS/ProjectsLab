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

	args := []string{

		"-hide_banner",

		"-loglevel",
		"warning",

		"-y",

		"-i",
		video,

		// video
		"-map",
		"0:v?",

		// audio
		"-map",
		"0:a?",

		// attachments
		"-map",
		"0:t?",
	}

	// 保留沒有刪除的字幕

	for _, track := range allTracks {

		if removeMap[track.Index] {

			continue

		}

		args = append(
			args,

			"-map",

			fmt.Sprintf(
				"0:%d",
				track.Index,
			),
		)

	}

	args = append(
		args,

		// metadata
		"-map_metadata",
		"0",

		// chapters
		"-map_chapters",
		"0",

		// 不重新編碼
		"-c",
		"copy",

		output,
	)

	cmd := exec.Command(
		"ffmpeg",
		args...,
	)

	cmd.Stderr = os.Stderr

	return cmd.Run()
}
