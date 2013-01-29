SRC = $(wildcard *.m)
SRC += $(wildcard ../../src/*.c)
SRC += $(wildcard ../../src/*.m)

user: $(SRC)
	clang -fobjc-arc -framework Foundation -I../../src -o $@ $(SRC)
