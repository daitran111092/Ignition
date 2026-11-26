FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
USRLIB := /Library/Developer/CommandLineTools/Library/Developer/usr/lib

.PHONY: build test app install run

build:
	swift build -c release

test:
	swift test -Xswiftc -F$(FRAMEWORKS) -Xlinker -F$(FRAMEWORKS) -Xlinker -rpath -Xlinker $(FRAMEWORKS) -Xlinker -rpath -Xlinker $(USRLIB)

app:
	Scripts/make-app.sh

install: app
	rm -rf ~/Applications/Liftoff.app  # the app's name before it became Ignition
	rm -rf ~/Applications/Ignition.app
	mkdir -p ~/Applications
	cp -R build/Ignition.app ~/Applications/Ignition.app

run:
	swift run Liftoff
