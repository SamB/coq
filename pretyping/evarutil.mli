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
open Rawterm
open Term
open Sign
open Evd
open Environ
open Reductionops
(*i*)

(*s This modules provides useful functions for unification modulo evars *)

(* [whd_ise] raise [Uninstantiated_evar] if an evar remains uninstantiated; *)
(* *[whd_evar]* and *[nf_evar]* leave uninstantiated evar as is *)

val nf_evar :  evar_map -> constr -> constr
val j_nf_evar :  evar_map -> unsafe_judgment -> unsafe_judgment
val jl_nf_evar :
   evar_map -> unsafe_judgment list -> unsafe_judgment list
val jv_nf_evar :
   evar_map -> unsafe_judgment array -> unsafe_judgment array
val tj_nf_evar :
   evar_map -> unsafe_type_judgment -> unsafe_type_judgment

val nf_evar_info : evar_map -> evar_info -> evar_info

(* Replacing all evars *)
exception Uninstantiated_evar of existential_key
val whd_ise :  evar_map -> constr -> constr
val whd_castappevar :  evar_map -> constr -> constr

(* Creating new existential variables *)
val new_evar : unit -> evar
val new_evar_in_sign : env -> constr

val evar_env :  evar_info -> env

type evar_defs
val evars_of :  evar_defs ->  evar_map

val non_instantiated : evar_map -> (evar * evar_info) list

val create_evar_defs :  evar_map ->  evar_defs
val evars_reset_evd :  evar_map ->  evar_defs -> evar_defs
val evar_source : existential_key -> evar_defs -> loc * hole_kind

type evar_constraint = conv_pb * constr * constr
val add_conv_pb :  evar_constraint -> evar_defs -> evar_defs

val is_defined_evar :  evar_defs -> existential -> bool
val ise_undefined :  evar_defs -> constr -> bool
val has_undefined_isevars :  evar_defs -> constr -> bool

val new_isevar_sign :
 Environ.env -> Evd.evar_map -> Term.constr -> Term.constr list ->
  Evd.evar_map * Term.constr

val new_isevar :  evar_defs -> env -> loc * hole_kind -> constr ->
  evar_defs * constr

(* the same with side-effects *)
val e_new_isevar : evar_defs ref -> env -> loc * hole_kind -> constr -> constr

val is_eliminator : constr -> bool
val head_is_embedded_evar :  evar_defs -> constr -> bool
val solve_simple_eqn :
  (env ->  evar_defs -> conv_pb -> constr -> constr -> evar_defs * bool)
  -> env ->  evar_defs -> conv_pb * existential * constr ->
    evar_defs * bool

val define_evar_as_arrow : evar_defs -> existential -> evar_defs * types
val define_evar_as_sort : evar_defs -> existential -> evar_defs * sorts

(* Value/Type constraints *)

val new_Type_sort : unit -> sorts
val new_Type : unit -> constr
val judge_of_new_Type : unit -> unsafe_judgment
val refresh_universes : types -> types

type type_constraint = constr option
type val_constraint = constr option

val empty_tycon : type_constraint
val mk_tycon : constr -> type_constraint
val empty_valcon : val_constraint
val mk_valcon : constr -> val_constraint

val split_tycon :
  loc -> env ->  evar_defs -> type_constraint -> 
    evar_defs * (name * type_constraint * type_constraint)

val valcon_of_tycon : type_constraint -> val_constraint

val lift_tycon : type_constraint -> type_constraint

(* Metas *)
val nf_meta       : meta_map -> constr -> constr
val meta_type     : meta_map -> metavariable -> types
val meta_instance : meta_map -> constr freelisted -> constr
