CC = cc
CFLAGS = -O2 -std=c11 -Wall -Wextra -Werror
JSON_CFLAGS := $(shell pkg-config --cflags json-c)
JSON_LIB := $(shell pkg-config --variable=libdir json-c)/libjson-c.a

.PHONY: all test
all: runtime/display-control

runtime/display-control: helpers/display_control.c Makefile
	@mkdir -p runtime
	$(CC) $(CFLAGS) $(JSON_CFLAGS) $< $(JSON_LIB) -o $@.tmp
	mv $@.tmp $@

test: all
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_display_control.py'
	lua tests/display.lua
