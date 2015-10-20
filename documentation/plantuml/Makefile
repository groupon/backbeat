TARGETS = $(shell ls -1 | sed -n 's/\.txt$$/\.png/p')

all: $(TARGETS)

%.png: %.txt
	java -Djava.awt.headless=true -jar plantuml.jar -pipe < $< > $@

kqwait: kqwait.c
	gcc -std=c99 -Wall -g -o kqwait kqwait.c

.PHONY: clean
clean:
	@rm -f $(TARGETS) kqwait kqwait.dSYM core
