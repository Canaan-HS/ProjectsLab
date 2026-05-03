package output

import (
	"path/filepath"
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
