
(* $Id$ *)

(*i*)
open Names
open Univ
open Term
open Sign
open Declarations
open Inductive
open Environ
open Safe_typing
(*i*)

(* This module defines the global environment of Coq. 
   The functions below are exactly the same as the ones in [Typing],
   operating on that global environment. *)

val safe_env : unit -> safe_environment
val env : unit -> env

val universes : unit -> universes
val context : unit -> context
val named_context : unit -> named_context

val push_named_assum : identifier * constr -> unit
val push_named_def : identifier * constr -> unit

val add_constant : section_path -> constant_entry -> unit
val add_parameter : section_path -> constr -> unit
val add_mind : section_path -> mutual_inductive_entry -> unit
val add_constraints : constraints -> unit

val pop_named_decls : identifier list -> unit

val lookup_named : identifier -> constr option * types
(*i val lookup_rel : int -> name * types i*)
val lookup_constant : section_path -> constant_body
val lookup_mind : section_path -> mutual_inductive_body
val lookup_mind_specif : inductive -> inductive_instance

val export : string -> compiled_env
val import : compiled_env -> unit

(*s Some functions of [Environ] instanciated on the global environment. *)

val id_of_global : global_reference -> identifier

(*s Function to get an environment from the constants part of the global
    environment and a given context. *)

val env_of_context : named_context -> env

(*s Re-exported functions of [Inductive], composed with 
    [lookup_mind_specif]. *)

val mind_is_recursive : inductive -> bool
val mind_nconstr : inductive -> int
val mind_nparams : inductive -> int
val mind_nf_arity : inductive -> constr
val mind_nf_lc : inductive -> constr array

