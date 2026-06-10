//go:build windows

package disk

import (
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

const (
	driveRamdisk = 6
	driveRemote  = 4
	driveCdrom   = 5

	ioctlStorageQueryProperty        = 0x002d1400
	storageDeviceSeekPenaltyProperty = 7
	propertyStandardQuery            = 0
	fileAnyAccess                    = 0
	fileShareRead                    = 0x00000001
	fileShareWrite                   = 0x00000002
	openExisting                     = 3
	fileAttributeNormal              = 0x80
)

type storagePropertyQuery struct {
	PropertyId uint32
	QueryType  uint32
	Additional [1]byte
}

type storageDeviceSeekPenaltyDescriptor struct {
	Version           uint32
	Size              uint32
	IncursSeekPenalty byte
}

var (
	kernel32            = syscall.NewLazyDLL("kernel32.dll")
	procCreateFileW     = kernel32.NewProc("CreateFileW")
	procDeviceIoControl = kernel32.NewProc("DeviceIoControl")
	procGetDriveTypeW   = kernel32.NewProc("GetDriveTypeW")
)

func DetectDriveType(path string) DriveType {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return Unknown
	}

	root := filepath.VolumeName(absPath)
	if root == "" {
		return Unknown
	}

	rootPathForType := root + `\`
	driveTypeRet, _, _ := procGetDriveTypeW.Call(uintptr(unsafe.Pointer(syscall.StringToUTF16Ptr(rootPathForType))))

	switch driveTypeRet {
	case driveRamdisk:
		return SSD
	case driveRemote, driveCdrom:
		return HDD
	}

	if strings.HasPrefix(root, `\\`) {
		return HDD
	}

	devicePath := `\\.\` + root
	handle, _, _ := procCreateFileW.Call(
		uintptr(unsafe.Pointer(syscall.StringToUTF16Ptr(devicePath))),
		fileAnyAccess,
		fileShareRead|fileShareWrite, 0, openExisting, fileAttributeNormal, 0,
	)

	h := syscall.Handle(handle)
	if h == syscall.InvalidHandle {
		return Unknown
	}
	defer syscall.CloseHandle(h)

	var query storagePropertyQuery
	query.PropertyId = storageDeviceSeekPenaltyProperty
	query.QueryType = propertyStandardQuery

	var desc storageDeviceSeekPenaltyDescriptor
	var bytesReturned uint32

	ret, _, _ := procDeviceIoControl.Call(
		uintptr(h), ioctlStorageQueryProperty,
		uintptr(unsafe.Pointer(&query)), uintptr(unsafe.Sizeof(query)),
		uintptr(unsafe.Pointer(&desc)), uintptr(unsafe.Sizeof(desc)),
		uintptr(unsafe.Pointer(&bytesReturned)), 0,
	)

	if ret == 0 {
		return Unknown
	}

	if desc.IncursSeekPenalty != 0 {
		return HDD
	}
	return SSD
}
