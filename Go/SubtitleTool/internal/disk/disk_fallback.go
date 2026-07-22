//go:build !windows

package disk

func DetectDriveType(path string) DriveType { return Unknown }
