.PHONY: all build dev clean
all: build
build:
	typst compile --pdf-standard a-2b --font-path lib/fonts/ main.typ
dev:
	typst watch --font-path lib/fonts/ main.typ
clean:
	rm -f main.pdf

example:
	typst compile --root . --font-path ./lib/fonts --pdf-standard a-2b --input style=legacy lib/example.typ example_legacy.pdf
	typst compile --root . --font-path ./lib/fonts --pdf-standard a-2b --input style=modern lib/example.typ example_modern.pdf
	typst compile --root . --font-path ./lib/fonts --pdf-standard a-2b --input style=minimal lib/example.typ example_minimal.pdf
