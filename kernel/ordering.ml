(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

open Term
open Util
open Symbol

(* CiME *)
open Orderings_generalities

(* multiset extension *)
let mul_extension ord vt vt' =
  multiset_extension ord (Array.to_list vt) (Array.to_list vt')

(* lexicographic extension *)
let lex_extension ord vt vt' =
  lexicographic_extension ord (Array.to_list vt) (Array.to_list vt')

(* reverse lexico extension *)
let revlex_extension ord vt vt' =
  lexicographic_extension ord (array_to_rev_list vt) (array_to_rev_list vt')

(* combination of elements of [vt] whose indices are given by [l] *)
let select vt =
  (* elements of [vt] whose indices are given by [m] *)
  let rec sel m =
    match m with
      | i::m' -> vt.(i)::(sel m')
      | _ -> []
  in
  let rec selc l =
    match l with
      | m::l' -> (sel m)::(selc l')
      | _ -> []
  in selc

(* combination extension *)
let comb_extension l ord vt vt' =
  lexicographic_extension (multiset_extension ord) (select vt l) (select vt' l)

(* status extension *)
let extension s =
  match s with
    | Mul -> mul_extension
    | Lex -> lex_extension
    | RevLex -> revlex_extension
    | Comb l -> comb_extension l

(* structurally compare t and u *)
let struct_compare t =
  let rec greater_than_t u =
    if eq_constr t u then Equivalent
    else
      match kind_of_term u with
	| App (f,va) ->
	    if eq_constr t f then Equivalent
	    else if array_exists is_greater_than_t va then Less_than
	    else Uncomparable
	| _ -> Uncomparable
  and is_greater_than_t u = greater_than_t u <> Uncomparable
  in greater_than_t

(* say if [vt] is structurally smaller than [vu] wrt status [s] *)
let is_struct_smaller_vec s vt vu =
  extension s struct_compare vt vu = Less_than

