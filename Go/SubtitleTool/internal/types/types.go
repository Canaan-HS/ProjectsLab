package types

type Mode int

const (
	Extract Mode = iota
	Remove
	Embed
)

type Options struct {
	Mode      Mode
	Path      string
	Languages []string
	Recursive bool
	DryRun    bool
	Yes       bool
}

func (s SubtitleTrack) Extension() string {

	switch s.Codec {

	case "ass":
		return "ass"

	case "ssa":
		return "ass"

	case "subrip":
		return "srt"

	case "srt":
		return "srt"

	default:
		return "srt"
	}

}
