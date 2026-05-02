package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"

	"SubtitleTool/internal/cli"
	"SubtitleTool/internal/operation"
	"SubtitleTool/internal/scan"
	"SubtitleTool/internal/types"
)

func main() {
	opt, err := cli.Parse()

	if err != nil {
		if errors.Is(err, cli.ErrHelp) {
			return
		}
		fmt.Println(err)
		return
	}

	if _, err := exec.LookPath("ffmpeg"); err != nil {
		fmt.Println(" ✗ ffmpeg not found. Please install ffmpeg and ensure it's in your PATH.")
		return
	}

	if _, err := exec.LookPath("ffprobe"); err != nil {
		fmt.Println(" ✗ ffprobe not found. Please install ffmpeg and ensure it's in your PATH.")
		return
	}

	if opt.SubtitlePath != "" {
		info, err := os.Stat(opt.Path)

		if err != nil {
			fmt.Printf(" ✗ Error: %v\n", err)
			return
		}

		if info.IsDir() {
			fmt.Println(" ✗ Error: -input must be a file (not a directory) when -sub is specified")
			return
		}
	}

	if opt.OutputPath != "" {
		if err := os.MkdirAll(opt.OutputPath, 0755); err != nil {
			fmt.Printf(" ✗ Error: failed to create output directory: %v\n", err)
			return
		}
	}

	videos, err := scan.FindVideos(opt.Path, opt.Recursive)

	if err != nil {
		fmt.Println(err)
		return
	}

	for _, video := range videos {
		switch opt.Mode {
		case types.Extract:
			operation.Extract(video, opt)
		case types.Remove:
			operation.Remove(video, opt)
		case types.Embed:
			operation.Embed(video, opt)
		}
	}
}
