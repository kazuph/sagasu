.PHONY: build test run app install package clean

build:
	SWIFTPM_DISABLE_SANDBOX=1 swift build -c release --disable-sandbox

test:
	swift test

run:
	swift run Sagasu

app:
	./Scripts/build_app.sh

install:
	./Scripts/build-and-open-app.sh

package:
	./Scripts/package_release.sh

clean:
	swift package clean
	rm -rf dist
