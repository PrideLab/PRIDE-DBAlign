# Makefile created by Yuanxin Pan (yxpan@whu.edu.cn), on Nov 25, 2017
# Modified by Songfeng Yang (sfyang@whu.edu.cn) --- add multi-GNSS PPP

LIB := libcom.a
all : $(LIB)

DIR_GUARD = @mkdir -p $(@D)
OBJ_PATH = .obj/

# Flags
FTN = gfortran
FFLAGS = -g -O3

SRC := dot.f90 \
       earth_rotation.f90 \
       ef2int.f90 \
       findkey.f90 \
       get_valid_unit.f90 \
       left_justify_string.f90 \
       mjd2doy.f90 \
       modified_julday.f90 \
       pointer_string.f90 \
       rdsp3.f90 \
       read_bias.f90 \
       read_igserp.f90 \
       read_satclk.f90 \
       taiutc.f90 \
       timdif.f90 \
       timinc.f90 \
       trig_poly_extrap.f90 \
       yeardoy2monthday.f90 \
       yr2year.f90
SRC_FOR := $(wildcard sofa/*.for)
SRC_F := $(wildcard iers/*.F)
OBJ := $(SRC:.f90=.o)
OBJ += $(SRC_FOR:.for=.o)
OBJ += $(SRC_F:.F=.o) 
OBJ := $(addprefix $(OBJ_PATH), $(OBJ))
 
$(LIB) : $(OBJ)
	ar -rv $(LIB) $(OBJ)

$(OBJ_PATH)%.o : %.f90 Makefile
	$(DIR_GUARD)
	$(FTN) $(FFLAGS) -c $< -o $@
	@/bin/echo -n "$(OBJ_PATH)$*.o : " > $(@:.o=.d)
	@sed -n "s/^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]*['\"]\(.*\.h\)['\"].*/\1/p" $< | xargs >> $(@:.o=.d)

$(OBJ_PATH)%.o : %.for Makefile
	$(DIR_GUARD)
	$(FTN) $(FFLAGS) -c $< -o $@
	@/bin/echo -n "$(OBJ_PATH)$*.o : " > $(@:.o=.d)
	@sed -n "s/^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]*['\"]\(.*\.h\)['\"].*/\1/p" $< | xargs >> $(@:.o=.d)

$(OBJ_PATH)%.o : %.F Makefile
	$(DIR_GUARD)
	$(FTN) $(FFLAGS) -c $< -o $@
	@/bin/echo -n "$(OBJ_PATH)$*.o : " > $(@:.o=.d)
	@sed -n "s/^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]*['\"]\(.*\.h\)['\"].*/\1/p" $< | xargs >> $(@:.o=.d)
.PHONY : clean
clean :
	rm -f $(LIB)
	rm -rf $(OBJ_PATH)

-include $(OBJ:.o=.d)
