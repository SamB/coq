
# Main Makefile for Coq

include config/Makefile

noargument:
	@echo Please use either
	@echo "   ./configure"
	@echo "   make world"
	@echo "   make install"
	@echo "   make cleanall"
	@echo or make archclean

BYTEFLAGS=$(INCLUDES) $(CAMLDEBUG)
OPTFLAGS=$(INCLUDES) $(CAMLTIMEPROF)
OCAMLDEP=ocamldep
DEPFLAGS=$(INCLUDES)

INCLUDES=-I config -I lib -I kernel

# Objects files 

CONFIG=config/coq_config.cmo

LIB=lib/pp_control.cmo lib/pp.cmo lib/util.cmo lib/hashcons.cmo \
    lib/dyn.cmo

KERNEL=kernel/names.cmo kernel/generic.cmo kernel/term.cmo \
       kernel/sign.cmo kernel/evd.cmo \
       kernel/closure.cmo kernel/reduction.cmo \
       kernel/mach.cmo

OBJS=$(CONFIG) $(LIB) $(KERNEL)

# Targets

world: $(OBJS)

MLI=$(OBJS:.cmo=.mli)
LPFILES=doc/macros.tex $(MLI)
lp: doc/coq.ps
doc/coq.ps: doc/coq.tex
	cd doc; make coq.ps
doc/coq.tex: $(LPFILES)
	ocamlweb -o doc/coq.tex $(LPFILES)

# Default rules

.SUFFIXES: .ml .mli .cmo .cmi .cmx

.ml.cmo:
	$(OCAMLC) $(BYTEFLAGS) -c $<

.mli.cmi:
	$(OCAMLC) $(BYTEFLAGS) -c $<

.ml.cmx:
	$(OCAMLOPT) $(OPTFLAGS) -c $<

# Cleaning

archclean::
	rm -f config/*.cmx config/*.[so]
	rm -f lib/*.cmx lib/*.[so]
	rm -f kernel/*.cmx kernel/*.[so]

cleanall:: archclean
	rm -f *~
	rm -f config/*.cm[io] config/*~
	rm -f lib/*.cm[io] lib/*~
	rm -f kernel/*.cm[io] kernel/*~

cleanconfig::
	rm -f config/Makefile config/coq_config.ml

# Dependencies

depend:
	$(OCAMLDEP) $(DEPFLAGS) */*.mli */*.ml > .depend

include .depend
