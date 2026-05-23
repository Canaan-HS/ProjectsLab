package ffmpeg

import (
	"encoding/json"
	"os"
	"os/exec"

	"SubtitleTool/internal/types"
)

type probeResult struct {
	Streams []stream `json:"streams"`
}

type stream struct {
	Index     int    `json:"index"`
	CodecType string `json:"codec_type"`
	CodecName string `json:"codec_name"`

	Tags struct {
		Language string `json:"language"`
		Title    string `json:"title"`
	} `json:"tags"`
}

func Probe(video string) (*types.MediaInfo, error) {

	cmd := exec.Command(

		"ffprobe",

		"-v", "quiet",

		"-show_streams",

		"-show_format",

		"-print_format", "json",

		video,
	)

	cmd.Stderr = os.Stderr

	output, err := cmd.Output()

	if err != nil {
		return nil, err
	}

	var probe probeResult

	err = json.Unmarshal(output, &probe)

	if err != nil {
		return nil, err
	}

	info := &types.MediaInfo{}

	for _, s := range probe.Streams {

		if s.CodecType != "subtitle" {
			continue
		}

		info.Subtitles = append(

			info.Subtitles,

			types.SubtitleTrack{

				Index: s.Index,

				Language: s.Tags.Language,

				Codec: s.CodecName,

				Title: s.Tags.Title,
			},
		)

	}

	return info, nil

}
