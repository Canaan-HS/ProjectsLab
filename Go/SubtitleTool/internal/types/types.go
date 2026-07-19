package types

type Mode int

const (
	Extract Mode = iota
	Remove
	Embed
)

type Options struct {
	Mode         Mode
	Path         string
	OutputPath   string
	Languages    []string
	SubtitlePath string
	Recursive    bool
	Overwrite    bool
}

type MediaInfo struct {
	Subtitles []SubtitleTrack
}

type SubtitleTrack struct {
	Index    int
	Language string
	Title    string
	Codec    string
}

func (s SubtitleTrack) Extension() string {
	switch s.Codec {
	case "ass", "ssa":
		return "ass"
	default:
		return "srt"
	}
}

type ExternalSubtitle struct {
	Path     string
	Language string
	Title    string
}
