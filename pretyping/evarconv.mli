
(* $Id$ *)

(*i*)
open Term
open Sign
open Environ
open Reduction
open Evarutil
(*i*)

val reset_problems : unit -> unit

val the_conv_x : env -> unit evar_defs -> constr -> constr -> bool

val the_conv_x_leq : env -> unit evar_defs -> constr -> constr -> bool

(* For debugging *)
val solve_pb : 
  env -> unit evar_defs -> conv_pb * constr * constr -> bool

val evar_conv_x : 
  env -> unit evar_defs ->
    conv_pb -> constr -> constr -> bool

val evar_eqappr_x : 
  env -> unit evar_defs ->
    conv_pb -> constr * constr list -> constr * constr list -> bool
