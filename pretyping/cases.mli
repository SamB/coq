(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

(*i*)
open Names
open Term
open Evd
open Environ
open Inductiveops
open Rawterm
open Evarutil
(*i*)

type pattern_matching_error =
  | BadPattern of constructor * constr
  | BadConstructor of constructor * inductive
  | WrongNumargConstructor of constructor * int
  | WrongPredicateArity of constr * constr * constr
  | NeedsInversion of constr * constr
  | UnusedClause of cases_pattern list
  | NonExhaustive of cases_pattern list
  | CannotInferPredicate of (constr * types) array

exception PatternMatchingError of env * pattern_matching_error

(* Used for old cases in pretyping *)

val branch_scheme : 
  env -> evar_defs -> bool -> inductive * constr list -> constr array

val pred_case_ml_onebranch : loc -> env -> evar_map -> bool ->
  inductive_type -> int * unsafe_judgment -> constr 

(* Compilation of pattern-matching. *)

val compile_cases :
  loc -> (type_constraint -> env -> rawconstr -> unsafe_judgment)
  * evar_defs -> type_constraint -> env ->
    rawconstr option * rawconstr list *
    (loc * identifier list * cases_pattern list * rawconstr) list ->
    unsafe_judgment
