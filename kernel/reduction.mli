
(* $Id$ *)

(*i*)
open Names
open Generic
open Term
open Univ
open Evd
open Environ
open Closure
(*i*)

(* Reduction Functions. *)

exception Redelimination
exception Induc
exception Elimconst

type 'a reduction_function = unsafe_env -> 'a evar_map -> constr -> constr

type 'a stack_reduction_function = 
    unsafe_env -> 'a evar_map -> constr -> constr list -> constr * constr list

val whd_stack : 'a stack_reduction_function

(*s Reduction Function Operators *)
val under_casts : 'a reduction_function -> 'a reduction_function
val strong : 'a reduction_function -> 'a reduction_function
val strong_prodspine : 'a reduction_function -> 'a reduction_function
val stack_reduction_of_reduction : 
  'a reduction_function -> 'a stack_reduction_function

(*s Generic Optimized Reduction Functions using Closures *)

(* 1. lazy strategy *)
val clos_norm_flags : Closure.flags -> 'a reduction_function
(* Same as [(strong whd_beta[delta][iota])], but much faster on big terms *) 
val nf_beta : 'a reduction_function
val nf_betaiota : 'a reduction_function
val nf_betadeltaiota : 'a reduction_function

(* 2. call by value strategy *)
val cbv_norm_flags : flags -> 'a reduction_function
val cbv_beta : 'a reduction_function
val cbv_betaiota : 'a reduction_function
val cbv_betadeltaiota : 'a reduction_function

(* 3. lazy strategy, weak head reduction *)
val whd_beta : 'a reduction_function
val whd_betaiota : 'a reduction_function
val whd_betadeltaiota : 'a reduction_function

val whd_beta_stack : 'a stack_reduction_function
val whd_betaiota_stack : 'a stack_reduction_function
val whd_betadeltaiota_stack : 'a stack_reduction_function


(*s Head normal forms *)
val whd_const_stack : section_path list -> 'a stack_reduction_function
val whd_const : section_path list -> 'a reduction_function
val whd_delta_stack : 'a stack_reduction_function
val whd_delta : 'a reduction_function
val whd_betadelta_stack : 'a stack_reduction_function
val whd_betadelta : 'a reduction_function
val whd_betadeltat_stack : 'a stack_reduction_function
val whd_betadeltat : 'a reduction_function
val whd_betadeltatiota_stack : 'a stack_reduction_function
val whd_betadeltatiota : 'a reduction_function
val whd_betadeltaiotaeta_stack : 'a stack_reduction_function
val whd_betadeltaiotaeta : 'a reduction_function

val beta_applist : (constr * constr list) -> constr


val hnf_prod_app : 
  unsafe_env -> 'a evar_map -> string -> constr -> constr -> constr
val hnf_prod_appvect : 
  unsafe_env -> 'a evar_map -> string -> constr -> constr array -> constr
val hnf_prod_applist : 
  unsafe_env -> 'a evar_map -> string -> constr -> constr list -> constr
val hnf_lam_app : 
  unsafe_env -> 'a evar_map -> string -> constr -> constr -> constr
val hnf_lam_appvect : 
  unsafe_env -> 'a evar_map -> string -> constr -> constr array -> constr
val hnf_lam_applist : 
  unsafe_env -> 'a evar_map -> string -> constr -> constr list -> constr
val splay_prod : 
  unsafe_env -> 'a evar_map -> constr -> (name * constr) list * constr
val decomp_prod : unsafe_env -> 'a evar_map -> constr -> int * constr
val decomp_n_prod : 
  unsafe_env -> 'a evar_map -> int -> constr -> ((name * constr) list) * constr

val is_arity : unsafe_env -> 'a evar_map -> constr -> bool
val is_info_arity : unsafe_env -> 'a evar_map -> constr -> bool
val is_info_sort : unsafe_env -> 'a evar_map -> constr -> bool
val is_logic_arity : unsafe_env -> 'a evar_map -> constr -> bool
val is_type_arity : unsafe_env -> 'a evar_map -> constr -> bool
val is_info_type : unsafe_env -> 'a evar_map -> typed_type -> bool
val is_info_cast_type : unsafe_env -> 'a evar_map -> constr -> bool
val contents_of_cast_type : unsafe_env -> 'a evar_map -> constr -> contents
val poly_args : unsafe_env -> 'a evar_map -> constr -> int list

val whd_programs : 'a reduction_function

val unfoldn : 
  (int list * section_path) list -> 'a reduction_function
val fold_one_com : constr -> 'a reduction_function
val fold_commands : constr list -> 'a reduction_function
val subst_term_occ : int list -> constr -> constr -> constr
val pattern_occs : (int list * constr * constr) list -> 'a reduction_function
val compute : 'a reduction_function


(*s Conversion Functions (uses closures, lazy strategy) *)

type conv_pb = 
  | CONV 
  | CONV_LEQ

val pb_is_equal : conv_pb -> bool
val pb_equal : conv_pb -> conv_pb

type conversion_test = constraints -> constraints

exception NotConvertible

val sort_cmp : conv_pb -> sorts -> sorts -> conversion_test
val base_sort_cmp : conv_pb -> sorts -> sorts -> bool

val bool_and_convert : bool -> conversion_test -> conversion_test
val convert_and : conversion_test -> conversion_test -> conversion_test
val convert_or : conversion_test -> conversion_test -> conversion_test
val convert_forall2 : 
  ('a -> 'b -> conversion_test) -> 'a array -> 'b array -> conversion_test

type 'a conversion_function = 
    unsafe_env -> 'a evar_map -> constr -> constr -> constraints

val fconv : conv_pb -> 'a conversion_function

(* [fconv] has 2 instances: [conv = fconv CONV] i.e. conversion test, and
   [conv_leq = fconv CONV_LEQ] i.e. cumulativity test. *)

val conv : 'a conversion_function
val conv_leq : 'a conversion_function

val conv_forall2 : 
  'a conversion_function -> unsafe_env -> 'a evar_map -> constr array 
    -> constr array -> constraints

val conv_forall2_i : 
  (int -> 'a conversion_function) -> unsafe_env -> 'a evar_map
    -> constr array -> constr array -> constraints

val is_conv : unsafe_env -> 'a evar_map -> constr -> constr -> bool
val is_conv_leq : unsafe_env -> 'a evar_map -> constr -> constr -> bool


(*s Special-Purpose Reduction Functions *)

val whd_meta : 'a reduction_function
val plain_instance : (int * constr) list -> constr -> constr
val instance : (int * constr) list -> 'a reduction_function

val whd_ise : 'a reduction_function
val whd_ise1 : 'a reduction_function
val nf_ise1 : 'a reduction_function
val whd_ise1_metas : 'a reduction_function


(*s Obsolete Reduction Functions *)

val hnf : unsafe_env -> 'a evar_map -> constr -> constr * constr list
val apprec : 'a stack_reduction_function
val red_product : 'a reduction_function
val find_mrectype : 
  unsafe_env -> 'a evar_map -> constr -> constr * constr list
val find_minductype : 
  unsafe_env -> 'a evar_map -> constr -> constr * constr list
val find_mcoinductype : 
  unsafe_env -> 'a evar_map -> constr -> constr * constr list
val check_mrectype_spec : unsafe_env -> 'a evar_map -> constr -> constr
val minductype_spec : unsafe_env -> 'a evar_map -> constr -> constr
val mrectype_spec : unsafe_env -> 'a evar_map -> constr -> constr

(* Special function, which keep the key casts under Fix and MutCase. *)
val strip_all_casts : constr -> constr
