APP = CodexUsage.app
DIST = .build/release
EXEC = CodexUsage

.PHONY: help run app install icon clean

help:
	@echo "Targets:"
	@echo "  make run     - run from source (debug)"
	@echo "  make app     - build release bundle at ./$(APP)"
	@echo "  make install - install to ~/Applications (Alfred: 'codex usage')"
	@echo "  make icon    - regenerate Resources/AppIcon.icns"
	@echo "  make clean   - remove build artifacts"

run:
	swift run $(EXEC)

app:
	@[ -f Resources/AppIcon.icns ] || $(MAKE) icon
	swift build -c release
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp "$(DIST)/$(EXEC)" "$(APP)/Contents/MacOS/$(EXEC)"
	@cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	@codesign --force --sign - "$(APP)"
	@echo "Built $(CURDIR)/$(APP)"

install: app
	@mkdir -p "$(HOME)/Applications"
	@rm -rf "$(HOME)/Applications/$(APP)"
	@cp -R "$(APP)" "$(HOME)/Applications/$(APP)"
	@echo "Installed $(HOME)/Applications/$(APP) - launch 'Codex Usage' from Alfred"

icon:
	swift Scripts/MakeIcon.swift CodexUsage.iconset
	iconutil -c icns CodexUsage.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build "$(APP)" CodexUsage.iconset
