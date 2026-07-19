package operation

import (
	"fmt"

	"SubtitleTool/internal/ffmpeg"
	"SubtitleTool/internal/fileutil"
	"SubtitleTool/internal/subtitle"
	"SubtitleTool/internal/types"
)

func Remove(
	video string,
	opt types.Options,
) {

	info, err := ffmpeg.Probe(video)

	if err != nil {

		fmt.Println(
			"Probe error:",
			video,
			err,
		)

		return
	}

	var removeTracks []types.SubtitleTrack

	// 沒指定語言
	// 先全部刪除
	if len(opt.Languages) == 0 {

		removeTracks = info.Subtitles

	} else {

		for _, sub := range info.Subtitles {

			for _, lang := range opt.Languages {

				if subtitle.MatchLanguage(
					sub,
					lang,
				) {

					removeTracks = append(
						removeTracks,
						sub,
					)

					break
				}

			}

		}

	}

	if len(removeTracks) == 0 {

		return

	}

	output := fileutil.NewOutputPath(
		video,
	)

	fmt.Println(
		"Remove subtitles:",
		video,
	)

	err = ffmpeg.RemoveSubtitle(
		video,
		info.Subtitles,
		removeTracks,
		output,
	)

	if err != nil {

		fmt.Println(
			"Remove error:",
			err,
		)

		return
	}

	fmt.Println(
		"Created:",
		output,
	)

}
