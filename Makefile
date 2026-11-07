.PHONY: build run clean test icon

build:
	./build.sh

run: build
	open build/IsoQuik.app

test:
	./test.sh

icon:
	./Tools/make_icon.sh

clean:
	rm -rf build
