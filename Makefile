DC = dmd
DFLAGS = -wi -g
BUILD_DIR = build
INSTALL_DIR = /usr/local/bin

debug: DFLAGS += -debug
debug: all

release: DFLAGS += -O -release
release: all

all: $(BUILD_DIR)/promptoglyph-path $(BUILD_DIR)/promptoglyph-vcs

package: clean release
	mkdir promptoglyph
	cp $(BUILD_DIR)/promptoglyph-path $(BUILD_DIR)/promptoglyph-vcs promptoglyph
	tar cf promptoglyph.tar promptoglyph
	gzip -f9 promptoglyph.tar
	rm -r promptoglyph

$(BUILD_DIR)/promptoglyph-path: promptoglyph-path.d systempath.d help.d
	@mkdir -p $(BUILD_DIR)
	$(DC) $(DFLAGS) -of$@ $^

$(BUILD_DIR)/promptoglyph-vcs: promptoglyph-vcs.d systempath.d help.d vcs.d time.d color.d git.d
	@mkdir -p $(BUILD_DIR)
	$(DC) $(DFLAGS) -of$@ $^

install: clean release
	cp $(BUILD_DIR)/promptoglyph-path $(BUILD_DIR)/promptoglyph-vcs $(INSTALL_DIR)

clean:
	rm -rf $(BUILD_DIR) promptoglyph.tar.gz

.PHONY: clean debug release all package install
