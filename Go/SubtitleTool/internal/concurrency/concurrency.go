package concurrency

import (
	"SubtitleTool/internal/disk"
	"SubtitleTool/internal/types"
)

type drivePair struct {
	input  disk.DriveType
	output disk.DriveType
}

// 目前趨向保守, 待測試
var table = map[types.Mode]map[drivePair]int{
	types.Extract: {
		{disk.SSD, disk.SSD}: 5,
		{disk.SSD, disk.HDD}: 3,
		{disk.HDD, disk.SSD}: 3,
		{disk.HDD, disk.HDD}: 2,
	},
	types.Remove: {
		{disk.SSD, disk.SSD}: 3,
		{disk.SSD, disk.HDD}: 1,
		{disk.HDD, disk.SSD}: 1,
		{disk.HDD, disk.HDD}: 1,
	},
	types.Embed: {
		{disk.SSD, disk.SSD}: 3,
		{disk.SSD, disk.HDD}: 1,
		{disk.HDD, disk.SSD}: 1,
		{disk.HDD, disk.HDD}: 1,
	},
}

func ForMode(mode types.Mode, inputPath, outputPath string) int {
	input := normalize(disk.DetectDriveType(inputPath))
	output := normalize(disk.DetectDriveType(outputPath))

	if m, ok := table[mode]; ok {
		if v, ok := m[drivePair{input, output}]; ok {
			return v
		}
	}
	return 1
}

func normalize(d disk.DriveType) disk.DriveType {
	if d == disk.Unknown {
		return disk.HDD
	}
	return d
}
