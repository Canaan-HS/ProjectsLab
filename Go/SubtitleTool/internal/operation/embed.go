package operation

import (
	"fmt"

	"SubtitleTool/internal/ffmpeg"
	"SubtitleTool/internal/fileutil"
	"SubtitleTool/internal/subtitle"
	"SubtitleTool/internal/types"
)

func Embed(
	video string,
	opt types.Options,
) {

	info, err := ffmpeg.Probe(video)

	if err != nil {

		fmt.Println(
			"Probe error:",
			err,
		)

		return
	}

	subs := subtitle.FindExternalSubtitles(
		video,
	)

	if len(subs) == 0 {

		return

	}

	output := fileutil.NewOutputPath(
		video,
	)

	fmt.Println(
		"Embed:",
		video,
	)

	err = ffmpeg.EmbedSubtitle(
		video,
		len(info.Subtitles),
		subs,
		output,
	)

	if err != nil {

		fmt.Println(
			"Embed error:",
			err,
		)

		return

	}

	fmt.Println(
		"Created:",
		output,
	)

}
