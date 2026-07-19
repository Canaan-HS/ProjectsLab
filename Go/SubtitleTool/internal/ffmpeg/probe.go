package ffmpeg

import (
	"encoding/json"
	"os"
	"os/exec"

	"SubtitleTool/internal/types"
)

type probeResult struct {
	Streams []stream `json:"streams"`

	Format format `json:"format"`
}

type format struct {
	Filename string `json:"filename"`

	FormatName string `json:"format_name"`

	Duration string `json:"duration"`
}

type stream struct {
	Index     int    `json:"index"`
	CodecType string `json:"codec_type"`
	CodecName string `json:"codec_name"`

	Disposition struct {
		Default int `json:"default"`
		Forced  int `json:"forced"`
	} `json:"disposition"`

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

	info := &types.MediaInfo{

		Path: video,
	}

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

				Default: s.Disposition.Default == 1,

				Forced: s.Disposition.Forced == 1,
			},
		)

	}

	return info, nil

}
