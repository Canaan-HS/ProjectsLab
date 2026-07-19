.PHONY: build run test vet clean

APP_NAME = subt

build:
	go build -o $(APP_NAME).exe .

run:
	go run . -- $(ARGS)

test:
	go test ./...

vet:
	go vet ./...

clean:
	rm -f $(APP_NAME).exe
