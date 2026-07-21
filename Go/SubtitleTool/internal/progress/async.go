package progress

import (
	"fmt"
	"os"
	"strings"
)

type asyncReporter struct {
	modeName string
}

func NewAsync() Reporter {
	return &asyncReporter{}
}

func (a *asyncReporter) Start(total int, modeName string, outputPath string) {
	a.modeName = modeName
	fmt.Printf("Processing %d file(s) in %s mode:\n", total, strings.ToLower(modeName))
}

func (a *asyncReporter) Step(index, total int, filename string) {
}

func (a *asyncReporter) Log(format string, args ...any) {
}

func (a *asyncReporter) Fail(filename string, err error) {
	fmt.Fprintf(os.Stderr, "✗ %s | %v\n", filename, err)
}

func (a *asyncReporter) Done(succeeded, failed int) {
	if succeeded+failed > 0 {
		fmt.Println()
	}
	fmt.Printf("── Done: %d succeeded, %d failed ──\n", succeeded, failed)
}
