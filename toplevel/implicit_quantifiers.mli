(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i $Id: classes.ml 6748 2005-02-18 22:17:50Z herbelin $ i*)

(*i*)
open Names
open Decl_kinds
open Term
open Sign
open Evd
open Environ
open Nametab
open Mod_subst
open Topconstr
open Util
open Typeclasses
(*i*)

val compute_constrs_freevars : env -> constr_expr list -> identifier list
val compute_constrs_freevars_binders : env -> constr_expr list -> (identifier located * constr_expr) list
val resolve_class_binders : env -> typeclass_context -> 
  (identifier located * constr_expr) list * typeclass_context

val full_class_binders : env -> typeclass_context -> typeclass_context

val generalize_class_binders : env -> typeclass_context -> local_binder list * local_binder list

val ctx_of_class_binders : env -> typeclass_context -> local_binder list

val implicits_of_binders : local_binder list -> (Topconstr.explicitation * (bool * bool)) list

val nf_named_context : evar_map -> named_context -> named_context
val nf_rel_context : evar_map -> rel_context -> rel_context
val nf_env : evar_map -> env -> env

val constr_expr_of_constraint : identifier located -> constr_expr list -> constr_expr
