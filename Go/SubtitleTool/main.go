package main

import (
	"fmt"

	"SubtitleTool/internal/cli"
	"SubtitleTool/internal/operation"
	"SubtitleTool/internal/scan"
	"SubtitleTool/internal/types"
)

func main() {

	opt, err := cli.Parse()

	if err != nil {

		fmt.Println(err)
		return
	}

	videos, err := scan.FindVideos(
		opt.Path,
		opt.Recursive,
	)

	if err != nil {

		fmt.Println(err)
		return
	}

	for _, video := range videos {

		switch opt.Mode {

		case types.Extract:

			operation.Extract(
				video,
				opt,
			)

		case types.Remove:

			operation.Remove(
				video,
				opt,
			)

		case types.Embed:

			operation.Embed(
				video,
				opt,
			)

		}

	}

}
