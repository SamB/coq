(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i*)
open Term
open Proof_type
open Tacexpr
(*i*)

val rawwit_hintbases : string list option raw_abstract_argument_type

val e_assumption : tactic

val registered_e_assumption : tactic

val e_resolve_constr :  constr -> tactic

val vernac_e_resolve_constr :  constr -> tactic

val e_give_exact_constr : constr -> tactic
