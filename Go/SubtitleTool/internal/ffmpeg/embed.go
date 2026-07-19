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
	args := commonArgs(video)

	for _, sub := range subtitles {
		args = append(args, "-i", sub.Path)
	}

	args = append(args,
		"-map", "0:v?",
		"-map", "0:a?",
		"-map", "0:s?",
	)

	subtitleOffset := existingSubtitleCount

	for i, sub := range subtitles {
		outputSubtitleIndex := subtitleOffset + i

		args = append(args,
			"-map", fmt.Sprintf("%d:0", i+1),
			"-metadata:s:s:"+strconv.Itoa(outputSubtitleIndex),
			"title="+sub.Title,
			"-metadata:s:s:"+strconv.Itoa(outputSubtitleIndex),
			"language="+sub.Language,
		)

		if i == 0 || sub.Default {
			args = append(args,
				"-disposition:s:"+strconv.Itoa(outputSubtitleIndex),
				"default",
			)
		}
	}

	args = append(args, suffixArgs(output)...)

	cmd := exec.Command("ffmpeg", args...)
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
