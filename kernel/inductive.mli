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
open Univ
open Term
open Declarations
open Environ
(*i*)

exception Induc

(*s Extracting an inductive type from a constructions *)

(* [find_m*type env sigma c] coerce [c] to an recursive type (I args).
   [find_rectype], [find_inductive] and [find_coinductive]
   respectively accepts any recursive type, only an inductive type and
   only a coinductive type.
   They raise [Induc] if not convertible to a recursive type. *)

val find_rectype     : env -> constr -> inductive * constr list
val find_inductive   : env -> constr -> inductive * constr list
val find_coinductive : env -> constr -> inductive * constr list

(*s Fetching information in the environment about an inductive type.
    Raises Induc if the inductive type is not found. *)
val lookup_mind_specif :
  env -> inductive -> mutual_inductive_body * one_inductive_body

(*s Functions to build standard types related to inductive *)

val type_of_inductive    : env -> inductive -> types

(* Return type as quoted by the user *)
val type_of_constructor  : env -> constructor -> types

(* Return constructor types in normal form *)
val arities_of_constructors : env -> inductive -> types array


exception Arity of (constr * constr * string) option

(* [type_case_branches env (I,args) (p:A) c] computes useful types
   about the following Cases expression:
      <p>Cases (c :: (I args)) of b1..bn end
   It computes the type of every branch (pattern variables are
   introduced by products), the type for the whole expression, and
   the universe constraints generated.
 *)
val type_case_branches :
  env -> inductive * constr list -> unsafe_judgment -> constr
    -> types array * types * constraints

(* Check a case_info actually correspond to a Case expression on the
   given inductive type. *)
val check_case_info : env -> inductive -> case_info -> unit

(*s Guard conditions for fix and cofix-points. *)
val check_fix : env -> fixpoint -> unit
val check_cofix : env -> cofixpoint -> unit

(********************)
(* TODO: remove (used in pretyping only...) *)
val find_case_dep_nparams :
  env -> constr * unsafe_judgment -> inductive * constr list ->
    bool * constraints
