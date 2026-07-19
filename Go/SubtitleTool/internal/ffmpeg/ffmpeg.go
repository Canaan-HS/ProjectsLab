package ffmpeg

func commonArgs(input string) []string {
	return []string{
		"-hide_banner",
		"-loglevel", "warning",
		"-y",
		"-i", input,
	}
}

func suffixArgs(output string) []string {
	return []string{
		"-map_metadata", "0",
		"-map_chapters", "0",
		"-c", "copy",
		output,
	}
}
