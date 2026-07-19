package ffmpeg

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"SubtitleTool/internal/types"
)

func EmbedSubtitle(
	video string,
	existingSubtitleCount int,
	subtitles []types.ExternalSubtitle,
	output string,
) error {

	args := []string{

		"-hide_banner",

		"-loglevel",
		"warning",

		"-y",

		"-i",
		video,
	}

	for _, sub := range subtitles {

		args = append(
			args,

			"-i",
			sub.Path,
		)

	}

	// 保留原影片內容

	args = append(
		args,

		"-map",
		"0:v?",

		"-map",
		"0:a?",

		"-map",
		"0:s?",
	)

	// 計算原字幕數量

	subtitleOffset := existingSubtitleCount

	// 外部字幕 stream index

	for i, sub := range subtitles {

		outputSubtitleIndex := subtitleOffset + i

		args = append(
			args,

			"-map",
			fmt.Sprintf(
				"%d:0",
				i+1,
			),

			"-metadata:s:s:"+strconv.Itoa(outputSubtitleIndex),
			"title="+sub.Title,

			"-metadata:s:s:"+strconv.Itoa(outputSubtitleIndex),
			"language="+sub.Language,
		)

		// 設定第一個新增字幕為 default

		if i == 0 || sub.Default {

			args = append(
				args,

				"-disposition:s:"+strconv.Itoa(outputSubtitleIndex),
				"default",
			)

		}

	}

	args = append(
		args,

		"-map_metadata",
		"0",

		"-map_chapters",
		"0",

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
