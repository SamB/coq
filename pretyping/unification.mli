(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i $Id$ i*)

(*i*)
open Util
open Names
open Term
open Sign
open Environ
open Evd
open Evarutil
(*i*)

val w_Declare : env -> evar -> types -> evar_defs -> evar_defs
val w_Define : evar -> constr -> evar_defs -> evar_defs

(* The "unique" unification fonction *)
val w_unify :
  bool -> env -> Reductionops.conv_pb -> constr -> constr ->
  evar_defs -> evar_defs

(* [w_unify_to_subterm env (c,t) m] performs unification of [c] with a
   subterm of [t]. Constraints are added to [m] and the matched
   subterm of [t] is also returned. *)
val w_unify_to_subterm :
  env -> constr * constr -> evar_defs -> evar_defs * constr

(*i This should be in another module i*)

(* [abstract_list_all env sigma t c l]                     *)
(* abstracts the terms in l over c to get a term of type t *)
(* (used in inv.ml) *)
val abstract_list_all :
  env -> evar_map -> constr -> constr -> constr list -> constr
