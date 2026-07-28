package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"

	"SubtitleTool/internal/cli"
	"SubtitleTool/internal/concurrency"
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

	conc := concurrency.ForMode(opt.Mode, opt.Path, detectOutputPath(opt))

	r := progress.New()
	r.Start(len(videos), modeName(opt.Mode), opt.OutputPath)

	var (
		mu        sync.Mutex
		succeeded int
		skipped   int
		failed    int
	)

	sem := make(chan struct{}, conc)
	var wg sync.WaitGroup

	for _, video := range videos {
		sem <- struct{}{}
		wg.Add(1)

		go func(v string) {
			defer func() { <-sem }()
			defer wg.Done()

			var (
				done  bool
				opErr error
			)

			switch opt.Mode {
			case types.Extract:
				done, opErr = operation.Extract(v, opt, r)
			case types.Remove:
				done, opErr = operation.Remove(v, opt, r)
			case types.Embed:
				done, opErr = operation.Embed(v, opt, r)
			}

			mu.Lock()
			switch {
			case opErr != nil:
				r.Fail(filepath.Base(v), opErr)
				failed++
			case done:
				r.Success(filepath.Base(v))
				succeeded++
			default:
				r.Skipped(filepath.Base(v))
				skipped++
			}
			mu.Unlock()
		}(video)
	}

	wg.Wait()
	r.Done(succeeded, skipped, failed)
}

func detectOutputPath(opt types.Options) string {
	if opt.OutputPath != "" {
		return opt.OutputPath
	}
	return opt.Path
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
