all : _build/coqoune _build/parse_expr

_build/parse_expr : _build/parse_expr.cmo
	ocamlc $^ -o _build/parse_expr

_build/parse_expr.cmo : parse_expr.ml
	ocamlc $^ -c -o _build/parse_expr.cmo

_build/coqoune : _build/xml.cmo _build/data.cmo _build/usercmd.cmo _build/interface.cmo _build/coqoune.cmo
	ocamlc -I _build unix.cma $^ -o _build/coqoune

_build/coqoune.cmo : _build/xml.cmo _build/data.cmo _build/usercmd.cmo _build/interface.cmo coqoune.ml
	ocamlc -I _build -c -o _build/coqoune.cmo coqoune.ml

_build/xml.cmo : xml.ml
	ocamlc -I _build -c -o $@ $<
	
_build/data.cmo : data.ml _build/xml.cmo 
	ocamlc -I _build -c -o $@ $<
	
_build/usercmd.cmo : usercmd.ml _build/data.cmo
	ocamlc -I _build -c -o $@ $<
	
_build/interface.cmo : interface.ml _build/xml.cmo _build/data.cmo
	ocamlc -I _build -c -o $@ $<
