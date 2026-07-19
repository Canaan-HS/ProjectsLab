package fileutil

import (
	"path/filepath"
)

func NewOutputPath(
	input string,
) string {

	ext := filepath.Ext(input)

	base := input[:len(input)-len(ext)]

	return base + ".new" + ext
}
