
(* $Id$ *)

(*i*)
open Names
(*i*)

(* Universes. *)

type universe = { u_sp : section_path; u_num : int }

val dummy_univ : universe

val prop_univ : universe
val prop_univ_univ : universe
val prop_univ_univ_univ : universe

val new_univ : section_path -> universe

(*s Graphs of universes. *)

type universes

val initial_universes : universes

(*s Constraints. *)

type constraint_type = Gt | Geq | Eq

type univ_constraint = universe * constraint_type * universe

module Constraint : Set.S with type elt = univ_constraint

type constraints = Constraint.t

type constraint_function = universe -> universe -> constraints -> constraints

val enforce_gt : constraint_function
val enforce_geq : constraint_function
val enforce_eq : constraint_function

val super : universe -> universe * constraints

val super_super : universe -> universe * universe * constraints

val sup : universe -> universe -> universes -> universe * constraints

(*s Merge of constraints in a universes graph. 
  The function [merge_constraints] merges a set of constraints in a given
  universes graph. It raises the exception [UniverseInconsistency] if the
  constraints are not satisfiable. *)

exception UniverseInconsistency

val merge_constraints : constraints -> universes -> universes

(*s Pretty-printing of universes. *)

val pr_universes : universes -> Pp.std_ppcmds
