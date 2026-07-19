package scan

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var videoExt = map[string]bool{
	".mkv": true,
}

func FindVideos(path string, recursive bool) ([]string, error) {

	info, err := os.Stat(path)

	if err != nil {
		return nil, err
	}

	// 指定單一檔案
	if !info.IsDir() {

		ext := strings.ToLower(
			filepath.Ext(path),
		)

		if !videoExt[ext] {

			return nil, fmt.Errorf(
				"unsupported video format: %s (only mkv is supported)",
				ext,
			)
		}

		return []string{path}, nil
	}

	var videos []string

	// 遞迴掃描
	if recursive {

		err := filepath.WalkDir(
			path,
			func(
				p string,
				d os.DirEntry,
				err error,
			) error {

				if err != nil {
					return err
				}

				if d.IsDir() {
					return nil
				}

				if videoExt[strings.ToLower(filepath.Ext(p))] {

					videos = append(
						videos,
						p,
					)
				}

				return nil
			},
		)

		if err != nil {
			return nil, err
		}

	} else {

		files, err := os.ReadDir(path)

		if err != nil {
			return nil, err
		}

		for _, f := range files {

			if f.IsDir() {
				continue
			}

			full := filepath.Join(
				path,
				f.Name(),
			)

			if videoExt[strings.ToLower(filepath.Ext(full))] {

				videos = append(
					videos,
					full,
				)
			}

		}

	}

	return videos, nil
}
