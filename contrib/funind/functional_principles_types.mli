open Names
open Term
val generate_functional_principle : 
  (* do we accept interactive proving *)
  bool ->
  (* induction principle on rel *) 
  types ->
  (* *)
  sorts array option -> 
  (* Name of the new principle *) 
  (identifier) option -> 
  (* the compute functions to use   *)
  constant array -> 
  (* We prove the nth- principle *)
  int  ->
  (* The tactic to use to make the proof w.r
     the number of params
  *)
  (constr array -> int -> Tacmach.tactic) -> 
  unit



val compute_new_princ_type_from_rel : constr array -> sorts array -> 
  types -> types

val make_scheme : (identifier*identifier*Rawterm.rawsort) list ->  unit
val make_case_scheme : (identifier*identifier*Rawterm.rawsort)  ->  unit
