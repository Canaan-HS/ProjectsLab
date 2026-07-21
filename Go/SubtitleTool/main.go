package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"SubtitleTool/internal/cli"
	"SubtitleTool/internal/operation"
	"SubtitleTool/internal/progress"
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

	r := progress.NewSequential()
	r.Start(len(videos), modeName(opt.Mode), opt.OutputPath)

	succeeded, failed := 0, 0

	for i, video := range videos {
		r.Step(i+1, len(videos), filepath.Base(video))

		var opErr error

		switch opt.Mode {
		case types.Extract:
			opErr = operation.Extract(video, opt, r)
		case types.Remove:
			opErr = operation.Remove(video, opt, r)
		case types.Embed:
			opErr = operation.Embed(video, opt, r)
		}

		if opErr != nil {
			r.Fail(filepath.Base(video), opErr)
			failed++
		} else {
			succeeded++
		}
	}

	r.Done(succeeded, failed)
}

func modeName(m types.Mode) string {
	switch m {
	case types.Extract:
		return "Extracting"
	case types.Remove:
		return "Removing"
	case types.Embed:
		return "Embedding"
	default:
		return "Processing"
	}
}
