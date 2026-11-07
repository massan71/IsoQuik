.PHONY: build run clean test icon dmg

build:
	./build.sh

run: build
	open build/IsoQuik.app

test:
	./test.sh

dmg:
	./make_dmg.sh

icon:
	./Tools/make_icon.sh

clean:
	rm -rf build
