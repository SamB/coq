
(* $Id$ *)

(*i*)
open Names
open Term
open Sign
(*i*)

(* Constants. *)

type discharge_recipe

type recipe =
  | Cooked of constr
  | Recipe of discharge_recipe

type constant_entry = {
  const_entry_body : constr;
  const_entry_type : constr option }

type constant_body = {
  const_kind : path_kind;
  const_body : recipe ref option;
  const_type : typed_type;
  const_hyps : typed_type signature;
  mutable const_opaque : bool }

val is_defined : constant_body -> bool

val is_opaque : constant_body -> bool

