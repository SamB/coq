
(* $Id$ *)

open Names
open Term
open Constant
open Inductive
open Evd
open Univ

type 'a unsafe_env

val evar_map : 'a unsafe_env -> 'a evar_map
val universes : 'a unsafe_env -> universes
val metamap : 'a unsafe_env -> (int * constr) list

val push_var : identifier * constr -> 'a unsafe_env -> 'a unsafe_env
val push_rel : name * constr -> 'a unsafe_env -> 'a unsafe_env

val add_constant : constant_entry -> 'a unsafe_env -> 'a unsafe_env
val add_mind : mind_entry -> 'a unsafe_env -> 'a unsafe_env

val new_meta : unit -> int

val lookup_var : identifier -> 'a unsafe_env -> constr
val loopup_rel : int -> 'a unsafe_env -> name * constr
val lookup_constant : section_path -> 'a unsafe_env -> constant_entry

val id_of_global : 'a unsafe_env -> sorts oper -> identifier
val id_of_name_using_hdchar : 'a unsafe_env -> constr -> name -> identifier
val named_hd : 'a unsafe_env -> constr -> name -> name

val translucent_abst : 'a unsafe_env -> constr -> bool
val evaluable_abst : 'a unsafe_env -> constr -> bool
val abst_value : 'a unsafe_env -> constr -> constr

val defined_const : 'a unsafe_env -> constr -> bool
val translucent_const : 'a unsafe_env -> constr -> bool
val evaluable_const : 'a unsafe_env -> constr -> bool
val const_value : 'a unsafe_env -> constr -> constr
val const_type : 'a unsafe_env -> constr -> constr
val const_of_path : 'a unsafe_env -> section_path -> constant_entry

val is_existential : constr -> bool

val const_abst_opt_value : 'a unsafe_env -> constr -> constr option

val mind_of_path : section_path -> mutual_inductive_entry
val mind_path : constr -> section_path
val mind_nparams : 'a unsafe_env -> constr -> int
val mindsp_nparams : 'a unsafe_env -> section_path -> int
