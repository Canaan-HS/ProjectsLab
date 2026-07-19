package output

import (
	"path/filepath"
	"time"
)

func NewPath(input, op string) string {
	ext := filepath.Ext(input)
	base := input[:len(input)-len(ext)]
	ts := time.Now().Format("20060102_150405")
	return base + "_" + op + "_" + ts + ext
}
