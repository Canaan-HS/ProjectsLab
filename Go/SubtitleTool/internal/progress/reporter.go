package progress

import (
	"fmt"
	"os"
	"time"
)

type reporter struct {
	outputPath string
	startTime  time.Time
}

func New() Reporter {
	return &reporter{}
}

func (r *reporter) Start(total int, modeName string, outputPath string) {
	r.outputPath = outputPath
	r.startTime = time.Now()
	fmt.Printf("\n── Process: %d file(s), %s ──\n\n", total, modeName)
}

func (r *reporter) Step(index, total int, filename string) {}

func (r *reporter) Log(format string, args ...any) {}

func (r *reporter) Success(filename string) {
	fmt.Printf("✓ %s\n", filename)
}

func (r *reporter) Fail(filename string, err error) {
	fmt.Fprintf(os.Stderr, "✗ %s | %v\n", filename, err)
}

func (r *reporter) Done(succeeded, failed int) {
	elapsed := time.Since(r.startTime)
	if succeeded+failed > 0 {
		fmt.Print("\n")
	}
	if r.outputPath != "" {
		fmt.Printf("Output: %s\n", r.outputPath)
	}
	fmt.Printf("\n── Done: %d succeeded, %d failed (%s) ──\n", succeeded, failed, formatDuration(elapsed))
}

func formatDuration(d time.Duration) string {
	d = d.Round(time.Second)
	h := d / time.Hour
	d -= h * time.Hour
	m := d / time.Minute
	s := d % time.Minute / time.Second
	if h > 0 {
		return fmt.Sprintf("%dh%dm%ds", h, m, s)
	}
	if m > 0 {
		return fmt.Sprintf("%dm%ds", m, s)
	}
	return fmt.Sprintf("%ds", s)
}
