CC = cc
CFLAGS = -O3 -DNDEBUG -fvisibility=hidden -fvisibility-inlines-hidden -I../../src
OBJCFLAGS = -fobjc-arc
LDFLAGS = -framework Foundation -Wl,-S -Wl,-x -Wl,-dead_strip

OBJECTS := $(patsubst %.c,%.o,$(wildcard ../../src/*.c)) \
           $(patsubst %.m,%.o,$(wildcard ../../src/*.m)) \
           $(patsubst %.m,%.o,$(wildcard *.m))

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.m
	$(CC) $(CFLAGS) $(OBJCFLAGS) -c -o $@ $<

user: $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^

clean:
	rm -f $(OBJECTS) user

.PHONY: clean
