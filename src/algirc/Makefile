# Makefile created by Jihang Lin (jihanglin@whu.edu.cn), on Feb 23, 2023 

# Library (should be compiled first)
LIBCOM = ../lib/libcom.a

# Flags
FTN = gfortran 
FFLAGS = -g -O3

# Compile each module separately; keep module files with the objects.
OBJ_PATH = .obj
MODULES = get_config form_combination calc_stats cp_file \
          wrt_clock wrt_orbit wrt_bias
MODULE_OBJ = $(addprefix $(OBJ_PATH)/,$(addsuffix .o,$(MODULES)))
HEADER_FILES = $(wildcard ../header/*.h)

all : algirc

algirc : $(OBJ_PATH)/algirc.o $(MODULE_OBJ) $(LIBCOM)
	$(FTN) $(FFLAGS) $^ -o $@

$(OBJ_PATH)/algirc.o : $(MODULE_OBJ)
$(OBJ_PATH)/wrt_clock.o $(OBJ_PATH)/wrt_orbit.o : $(OBJ_PATH)/cp_file.o

$(OBJ_PATH)/%.o : %.f90 $(HEADER_FILES) | $(OBJ_PATH)
	$(FTN) $(FFLAGS) -J$(OBJ_PATH) -I$(OBJ_PATH) -c $< -o $@

$(OBJ_PATH):
	mkdir -p $@

.PHONY : all clean
clean :
	rm -f algirc
	rm -rf $(OBJ_PATH)
