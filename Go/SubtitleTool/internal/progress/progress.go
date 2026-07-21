package progress

type Reporter interface {
	Start(total int, modeName string, outputPath string)
	Step(index, total int, filename string)
	Log(format string, args ...any)
	Fail(filename string, err error)
	Done(succeeded, failed int)
}
