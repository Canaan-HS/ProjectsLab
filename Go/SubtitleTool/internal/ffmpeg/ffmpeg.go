package ffmpeg

import (
	"os"
	"os/exec"
)

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

func runFFmpeg(args []string) error {
	cmd := exec.Command("ffmpeg", args...)
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
