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
open Entries
open Indtypes
open Safe_typing
   (*i*)

(* This module defines the global environment of Coq.  The functions
   below are exactly the same as the ones in [Safe_typing], operating on
   that global environment. [add_*] functions perform name verification,
   i.e. check that the name given as argument match those provided by
   [Safe_typing]. *)



val safe_env : unit -> safe_environment
val env : unit -> Environ.env

val universes : unit -> universes
val named_context : unit -> Sign.named_context

(*s Extending env with variables and local definitions *)
val push_named_assum : (identifier * types) -> Univ.constraints
val push_named_def   : (identifier * constr * types option) -> Univ.constraints

(*s Adding constants, inductives, modules and module types.  All these
  functions verify that given names match those generated by kernel *)

val add_constant : 
  dir_path -> identifier -> global_declaration -> kernel_name
val add_mind        : 
  dir_path -> identifier -> mutual_inductive_entry -> kernel_name

val add_module      : identifier -> module_entry -> module_path
val add_modtype     : identifier -> module_type_entry -> kernel_name

val add_constraints : constraints -> unit

(*s Interactive modules and module types *)
(* Both [start_*] functions take the [dir_path] argument to create a 
   [mod_self_id]. This should be the name of the compilation unit. *)

(* [start_*] functions return the [module_path] valid for components
   of the started module / module type *)

val start_module : 
  dir_path -> identifier -> (mod_bound_id * module_type_entry) list 
    -> module_type_entry option 
      -> module_path

val end_module :
  identifier -> module_path

val start_modtype :
  dir_path -> identifier -> (mod_bound_id * module_type_entry) list
    -> module_path

val end_modtype :
  identifier -> kernel_name


(* Queries *)
val lookup_named     : variable -> named_declaration
val lookup_constant  : constant -> constant_body
val lookup_inductive : inductive -> mutual_inductive_body * one_inductive_body
val lookup_mind      : mutual_inductive -> mutual_inductive_body
val lookup_module    : module_path -> module_body
val lookup_modtype   : kernel_name -> module_type_body

(* Compiled modules *)
val start_library : dir_path -> module_path
val export : dir_path -> compiled_library
val import : compiled_library -> Digest.t -> module_path

(*s Function to get an environment from the constants part of the global
 * environment and a given context. *)
  
val type_of_global : Libnames.global_reference -> types
val env_of_context : Sign.named_context -> Environ.env

