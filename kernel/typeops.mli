
(* $Id$ *)

(*i*)
open Names
open Sign
open Univ
open Term
open Evd
open Environ
(*i*)


(* Basic operations of the typing machine. *)

val make_judge : constr -> typed_type -> unsafe_judgment

val j_val_only : unsafe_judgment -> constr

(* If [j] is the judgement $c:t:s$, then [typed_type_of_judgment env j]
   constructs the typed type $t:s$, while [assumption_of_judgement env j]
   cosntructs the type type $c:t$, checking that $t$ is a sort. *)

val typed_type_of_judgment : 
  env -> 'a evar_map -> unsafe_judgment -> typed_type
val assumption_of_judgment : 
  env -> 'a evar_map -> unsafe_judgment -> typed_type
val assumption_of_type_judgment : unsafe_type_judgment -> typed_type
val type_judgment : 
  env -> 'a evar_map -> unsafe_judgment -> unsafe_type_judgment

val relative : env -> int -> unsafe_judgment

val type_of_constant : env -> 'a evar_map -> constant -> typed_type

val type_of_inductive : env -> 'a evar_map -> inductive -> typed_type

val type_of_constructor : env -> 'a evar_map -> constructor -> typed_type

val type_of_existential : env -> 'a evar_map -> constr -> constr

val type_of_case : env -> 'a evar_map -> case_info
  -> unsafe_judgment -> unsafe_judgment 
    -> unsafe_judgment array -> unsafe_judgment

val type_case_branches :
  env -> 'a evar_map -> Inductive.inductive_type -> constr -> constr
    -> constr -> constr array * constr 

val judge_of_prop_contents : contents -> unsafe_judgment

val judge_of_type : universe -> unsafe_judgment * constraints

val typed_product_without_universes :
  name -> typed_type -> typed_type -> typed_type

val abs_rel : 
  env -> 'a evar_map -> name -> typed_type -> unsafe_judgment 
    -> unsafe_judgment * constraints

val gen_rel :
  env -> 'a evar_map -> name -> unsafe_type_judgment -> unsafe_judgment 
    -> unsafe_judgment * constraints

val sort_of_product : sorts -> sorts -> universes -> sorts * constraints
val sort_of_product_without_univ : sorts -> sorts -> sorts

val cast_rel : 
  env -> 'a evar_map -> unsafe_judgment -> unsafe_judgment 
    -> unsafe_judgment

val apply_rel_list : 
  env -> 'a evar_map -> bool -> unsafe_judgment list -> unsafe_judgment
    -> unsafe_judgment * constraints

val check_fix : env -> 'a evar_map -> fixpoint -> unit
val check_cofix : env -> 'a evar_map -> cofixpoint -> unit
val control_only_guard : env -> 'a evar_map -> constr -> unit

val type_fixpoint : env -> 'a evar_map -> name list -> typed_type array 
    -> unsafe_judgment array -> constraints

open Inductive

val find_case_dep_nparams :
  env -> 'a evar_map -> constr * constr -> inductive_family -> constr -> bool

val hyps_inclusion : env -> 'a evar_map -> var_context -> var_context -> bool

val keep_hyps : var_context -> Idset.t -> var_context
