
SUBDIR = lib algirc

DBALIGN_EXE = $(patsubst %.f90,%,$(wildcard algirc/algirc*.f90))

all : lib algirc

lib :
	$(MAKE) -j4 -C $@

algirc : lib
	$(MAKE) -j4 -C $@

install : all
	@mkdir -p ../bin/
	rm -f ../bin/algirc*
	cp -f $(DBALIGN_EXE) ../bin/

.PHONY : all $(SUBDIR) install clean
clean :
	-$(MAKE) -C lib clean
	-$(MAKE) -C algirc clean
	-rm -f ../bin/algirc*
