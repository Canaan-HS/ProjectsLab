package operation

import (
	"fmt"

	"SubtitleTool/internal/ffmpeg"
	"SubtitleTool/internal/subtitle"
	"SubtitleTool/internal/types"
)

func Extract(
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

	for _, sub := range info.Subtitles {

		lang := ""

		if len(opt.Languages) == 0 {

			lang = subtitle.ResolveLanguage(sub)

		} else {

			for _, target := range opt.Languages {

				if subtitle.MatchLanguage(
					sub,
					target,
				) {

					lang = target
					break

				}

			}

		}

		if lang == "" {
			continue
		}

		fmt.Println(
			"Extract:",
			video,
			lang,
		)

		err = ffmpeg.ExtractSubtitle(
			video,
			sub,
			lang,
		)

		if err != nil {

			fmt.Println(
				"Extract error:",
				err,
			)

		}

	}

}
