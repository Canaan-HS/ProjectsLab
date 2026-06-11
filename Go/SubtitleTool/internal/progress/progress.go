package progress

type Reporter interface {
	Start(total int, modeName string, outputPath string)
	Step(index, total int, filename string)
	Log(format string, args ...any)
	Success(filename string)
	Fail(filename string, err error)
	Done(succeeded, failed int)
}
