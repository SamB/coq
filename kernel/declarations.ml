
(* $Id$ *)

open Names
open Univ
open Generic
open Term
open Sign

(* Constant entries *)

type lazy_constant_value =
  | Cooked of constr
  | Recipe of (unit -> constr)

type constant_value = lazy_constant_value ref

type constant_body = {
  const_kind : path_kind;
  const_body : constant_value option;
  const_type : typed_type;
  const_hyps : typed_type signature;
  const_constraints : constraints;
  mutable const_opaque : bool }

let is_defined cb = 
  match cb.const_body with Some _ -> true | _ -> false

let is_opaque cb = cb.const_opaque

let cook_constant = function
  | { contents = Cooked c } -> c
  | { contents = Recipe f } as v -> let c = f () in v := Cooked c; c

type constant_entry = {
  const_entry_body : lazy_constant_value;
  const_entry_type : constr option }

(* Inductive entries *)

type recarg = 
  | Param of int 
  | Norec 
  | Mrec of int 
  | Imbr of inductive_path * recarg list

type one_inductive_body = {
  mind_consnames : identifier array;
  mind_typename : identifier;
  mind_lc : typed_type array;
  mind_arity : typed_type;
  mind_sort : sorts;
  mind_nrealargs : int;
  mind_kelim : sorts list;
  mind_listrec : (recarg list) array;
  mind_finite : bool }

type mutual_inductive_body = {
  mind_kind : path_kind;
  mind_ntypes : int;
  mind_hyps : typed_type signature;
  mind_packets : one_inductive_body array;
  mind_constraints : constraints;
  mind_singl : constr option;
  mind_nparams : int }

let mind_type_finite mib i = mib.mind_packets.(i).mind_finite

(*s Declaration. *)

type mutual_inductive_entry = {
  mind_entry_nparams : int;
  mind_entry_finite : bool;
  mind_entry_inds : (identifier * constr * identifier list * constr list) list}

let mind_nth_type_packet mib n = mib.mind_packets.(n)
