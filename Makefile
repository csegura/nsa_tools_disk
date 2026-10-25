Z80ASM ?= z80asm
BUILD ?= build

TOOLS := cat wc head tail grep crlf cmp diff df rm cp mv dis xmodem term
TOOL_SRC := $(wildcard src/tools/*.asm)
COMMON := $(wildcard src/common/*.asm)
NSADB := $(wildcard src/nsadb/*.asm)
TOOL_ASM = $(Z80ASM) -I src/common -I src/tools -I src/nsadb
NSADB_ASM = $(Z80ASM) -I src/common -I src/nsadb
ASM = $(Z80ASM) -I src/vi/core -I src/vi/cpm -I src/vi/adv -I src/common

.DEFAULT_GOAL := all
.PHONY: all small-tools clean help

all: $(BUILD)/vi_adv.com $(BUILD)/vi.com $(BUILD)/urun.com $(BUILD)/nsadb.com $(BUILD)/mkdbg.com $(BUILD)/ls.com $(BUILD)/less.com $(BUILD)/term.com $(TOOLS:%=$(BUILD)/%.com)

small-tools: $(TOOLS:%=$(BUILD)/%.com)

$(BUILD):
	mkdir -p $@

$(BUILD)/%.com: src/tools/%.asm $(TOOL_SRC) $(COMMON) $(NSADB) | $(BUILD)
	$(TOOL_ASM) -o $@ $<

$(BUILD)/vi.com: src/vi/cpm/vi.asm src/vi/cpm/vi_cpm_platform.asm src/vi/cpm/vi_cpm_stack.asm $(wildcard src/vi/core/*.asm) $(COMMON) | $(BUILD)
	$(ASM) -o $@ $<

$(BUILD)/vi_adv.com: src/vi/adv/vi_adv.asm src/vi/adv/vi_adv_platform.asm $(wildcard src/vi/core/*.asm) $(COMMON) | $(BUILD)
	$(ASM) -o $@ $<

$(BUILD)/urun.com: src/urun/urun.asm $(COMMON) | $(BUILD)
	$(Z80ASM) -I src/common -o $@ $<

$(BUILD)/nsadb.com: $(NSADB) $(COMMON) | $(BUILD)
	$(NSADB_ASM) -o $@ src/nsadb/nsadb.asm

$(BUILD)/mkdbg.com: src/mkdbg/mkdbg.asm $(COMMON) | $(BUILD)
	$(Z80ASM) -I src/common -o $@ $<

$(BUILD)/ls.com: src/ls/ls.asm $(COMMON) | $(BUILD)
	$(Z80ASM) -I src/common -o $@ $<

$(BUILD)/less.com: src/less/less.asm $(COMMON) | $(BUILD)
	$(Z80ASM) -I src/common -o $@ $<

$(BUILD)/term.com: src/term/term.asm $(COMMON) | $(BUILD)
	$(Z80ASM) -I src/common -o $@ $<

help:
	@printf 'Targets: all, small-tools, clean\n'
	@printf 'Builds COM files with z80asm. disk_image/TOOLS.NSI is the supplied prebuilt disk image.\n'

clean:
	rm -rf $(BUILD)
