(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i $Id$ i*)

(*i*)
open Declarations
open Environ
open Entries
open Mod_subst
(*i*)


val translate_module : env -> module_entry -> module_body

val translate_struct_entry : env -> module_struct_entry -> 
  struct_expr_body * substitution

val add_modtype_constraints : env -> module_type_body -> env

val add_module_constraints : env -> module_body -> env

val add_struct_expr_constraints : env -> struct_expr_body -> env

val struct_expr_constraints : struct_expr_body -> Univ.constraints

val module_constraints : module_body -> Univ.constraints
