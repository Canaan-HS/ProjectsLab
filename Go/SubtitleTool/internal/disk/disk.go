package disk

type DriveType int

const (
	Unknown DriveType = iota
	HDD
	SSD
)

func (d DriveType) String() string {
	switch d {
	case HDD:
		return "HDD"
	case SSD:
		return "SSD"
	default:
		return "Unknown"
	}
}

func DetectDriveType(path string) DriveType {
	return Unknown
}
