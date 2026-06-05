package progress

import (
	"fmt"
	"os"
)

type sequentialReporter struct {
	modeName   string
	outputPath string
}

func NewSequential() Reporter {
	return &sequentialReporter{}
}

func (s *sequentialReporter) Start(total int, modeName string, outputPath string) {
	s.modeName = modeName
	s.outputPath = outputPath
	fmt.Printf("── Process: %d file(s), %s ──\n", total, modeName)
}

func (s *sequentialReporter) Step(index, total int, filename string) {
	fmt.Printf("\n[%d/%d] → %s: %s", index, total, s.modeName, filename)
}

func (s *sequentialReporter) Log(format string, args ...any) {
}

func (s *sequentialReporter) Fail(filename string, err error) {
	fmt.Fprintf(os.Stderr, "\n✗ %s | %v\n", filename, err)
}

func (s *sequentialReporter) Done(succeeded, failed int) {
	if succeeded+failed > 0 {
		fmt.Print("\n")
	}
	if s.outputPath != "" {
		fmt.Printf("\nOutput: %s\n\n", s.outputPath)
	}
	fmt.Printf("── Done: %d succeeded, %d failed ──\n", succeeded, failed)
}
