package output

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func NewPath(input, op, outputDir string) string {
	ext := filepath.Ext(input)
	base := filepath.Base(input[:len(input)-len(ext)])
	ts := time.Now().Format("20060102_150405")
	filename := base + "_" + op + "_" + ts + ext
	if outputDir == "" {
		return filepath.Join(filepath.Dir(input), filename)
	}
	return filepath.Join(outputDir, filename)
}

func OverwritePath(input, outputDir string) string {
	ext := filepath.Ext(input)
	base := filepath.Base(input[:len(input)-len(ext)])
	filename := base + "_temp" + ext
	if outputDir == "" {
		return filepath.Join(filepath.Dir(input), filename)
	}
	return filepath.Join(outputDir, filename)
}

func FinalizeOverwrite(originalPath, tempPath string, extraFiles ...string) {
	for _, p := range extraFiles {
		if p == "" {
			continue
		}
		if err := os.Remove(p); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to delete %s: %v\n", p, err)
		}
	}

	if err := os.Remove(originalPath); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to delete original %s: %v\n", originalPath, err)
	}

	ext := filepath.Ext(tempPath)
	base := strings.TrimSuffix(tempPath, ext)
	if !strings.HasSuffix(base, "_temp") {
		fmt.Fprintf(os.Stderr, "Warning: unexpected temp file name: %s\n", tempPath)
		return
	}
	finalPath := strings.TrimSuffix(tempPath, "_temp"+ext) + ext

	if err := os.Rename(tempPath, finalPath); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to rename %s to %s: %v\n", tempPath, finalPath, err)
	}
}
