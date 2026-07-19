package ffmpeg

import (
	"fmt"
	"strconv"

	"SubtitleTool/internal/types"
)

func EmbedSubtitle(
	video string,
	keepTracks []types.SubtitleTrack,
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
	)

	if keepTracks == nil {
		args = append(args, "-map", "0:s?")
	} else {
		for _, t := range keepTracks {
			args = append(args, "-map", fmt.Sprintf("0:%d", t.Index))
		}
	}

	if keepTracks != nil {
		for i := 0; i < len(keepTracks); i++ {
			args = append(args, "-disposition:s:"+strconv.Itoa(i), "0")
		}
	}

	subtitleOffset := 0
	if keepTracks != nil {
		subtitleOffset = len(keepTracks)
	}

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

	return runFFmpeg(args)
}
