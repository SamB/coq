(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

(*i*)
open Evd
open Names
open Term
open Sign
open Environ
open Evarutil
open Rawterm
(*i*)

(*s Coercions. *)

(* [inh_app_fun env isevars j] coerces [j] to a function; i.e. it
   inserts a coercion into [j], if needed, in such a way it gets as
   type a product; it returns [j] if no coercion is applicable *)
val inh_app_fun :
  env -> evar_defs -> unsafe_judgment -> unsafe_judgment

(* [inh_coerce_to_sort env isevars j] coerces [j] to a type; i.e. it
   inserts a coercion into [j], if needed, in such a way it gets as
   type a sort; it fails if no coercion is applicable *)
val inh_coerce_to_sort :
  env -> evar_defs -> unsafe_judgment -> unsafe_type_judgment

(* [inh_conv_coerce_to loc env isevars j t] coerces [j] to an object of type 
   [t]; i.e. it inserts a coercion into [j], if needed, in such a way [t] and
   [j.uj_type] are convertible; it fails if no coercion is applicable *)
val inh_conv_coerce_to : Rawterm.loc -> 
  env -> evar_defs -> unsafe_judgment -> constr -> unsafe_judgment

(* [inh_pattern_coerce_to loc env isevars pat ind1 ind2] coerces the Cases
   pattern [pat] typed in [ind1] into a pattern typed in [ind2];
   raises [Not_found] if no coercion found *)
val inh_pattern_coerce_to :
  Rawterm.loc  -> cases_pattern -> inductive -> inductive -> cases_pattern
