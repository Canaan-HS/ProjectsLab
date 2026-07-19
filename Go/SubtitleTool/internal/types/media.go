package types

type MediaInfo struct {
	Path string

	Subtitles []SubtitleTrack
}

type SubtitleTrack struct {
	Index int

	Language string

	Title string

	Codec string

	Default bool

	Forced bool

	Alias string
}
