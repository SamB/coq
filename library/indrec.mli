
(* $Id$ *)

(*i*)
open Names
open Term
open Inductive
open Environ
open Evd
(*i*)

(* Eliminations. *)

val make_case_dep : env -> 'a evar_map -> constr -> sorts -> constr
val make_case_nodep : env -> 'a evar_map -> constr -> sorts -> constr
val make_case_gen : env -> 'a evar_map -> constr -> sorts -> constr

val make_indrec : env -> 'a evar_map -> 
  (mind_specif * bool * sorts) list -> constr -> constr array

val mis_make_indrec : env -> 'a evar_map -> 
  (mind_specif * bool * sorts) list -> mind_specif -> constr array

val instanciate_indrec_scheme : sorts -> int -> constr -> constr

val build_indrec : 
  env -> 'a evar_map -> (constr * bool * sorts) list -> constr array

val type_rec_branches : bool -> env -> 'c evar_map -> constr 
  -> constr -> constr -> constr -> constr * constr array * constr

val make_rec_branch_arg : 
  env -> 'a evar_map ->
    constr array * ('b * constr) option array * int ->
    constr -> constr -> recarg list -> constr

(*i Info pour JCF : d�plac� dans pretyping, sert � Program
val transform_rec : env -> 'c evar_map -> (constr array) 
  -> (constr * constr) -> constr
i*)

val is_mutind : env -> 'a evar_map -> constr -> bool 

val branch_scheme : 
  env -> 'a evar_map -> bool -> int -> constr -> constr

val pred_case_ml : env -> 'c evar_map -> bool -> (constr * constr) 
  ->  constr array -> (int*constr)  ->constr

val pred_case_ml_onebranch : env ->'c evar_map -> bool ->
  constr * constr ->int * constr * constr -> constr 

val make_case_ml :
  bool -> constr -> constr -> case_info -> constr array -> constr


(*s Auxiliary functions. TODO: les d�placer ailleurs. *)

val prod_create : env -> constr * constr -> constr
