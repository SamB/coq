
(* $Id$ *)

(*i*)
open Pp
open Names
open Term
open Sign
open Environ
open Declare
open Proof_type
open Tacmach
(*i*)

(*s Several proofs can be opened simultaneously but at most one is
   focused at some time. The following functions work by side-effect
   on current set of open proofs. In this module, ``proofs'' means an
   open proof (something started by vernacular command [Goal], [Lemma]
   or [Theorem]), and ``goal'' means a subgoal of the current focused
   proof *)

(*s [refining ()] tells if there is some proof in progress, even if a not
   focused one *)

val refining : unit -> bool

(* [check_no_pending_proofs ()] fails if there is still some proof in
   progress *)

val check_no_pending_proofs : unit -> unit

(*s [delete_proof name] deletes proof of name [name] or failed if no proof
    has this name *)

val delete_proof : identifier -> unit

(* [delete_current_proof ()] deletes current focused proof or failed if
    no proof is focused *)

val delete_current_proof : unit -> unit

(* [delete_all_proofs ()] deletes all open proofs if any *)

val delete_all_proofs : unit -> unit

(*s [undo n] undoes the effect of the last [n] tactics applied to the
    current proof; it fails if no proof is focused or if the ``undo''
    stack is exhausted *)

val undo : int -> unit

(* [set_undo n] sets the size of the ``undo'' stack *)

val set_undo : int -> unit

(* [reset_undo n] sets the size of the ``undo'' stack to the default
   value (12) *)

val reset_undo : unit -> unit

(*s [start_proof s str env t] starts a proof of name [s] and conclusion [t] *)

val start_proof : identifier -> strength -> named_context -> constr -> unit

(* [restart_proof ()] restarts the current focused proof from the beginning
   or fails if no proof is focused *)

val restart_proof : unit -> unit

(*s [resume_last_proof ()] focus on the last unfocused proof or fails
   if there is no suspended proofs *)

val resume_last_proof : unit -> unit

(* [resume_proof name] focuses on the proof of name [name] or
   raises [UserError] if no proof has name [name] *)

val resume_proof : identifier -> unit

(* [suspend_proof ()] unfocuses the current focused proof or
   failed with [UserError] if no proof is currently focused *)

val suspend_proof : unit -> unit

(*s [cook_proof ()] turns the current proof (assumed completed)
    into a constant with its name and strength; it fails if there is
    no current proof of if it is not completed *)

val cook_proof : unit -> identifier * (Declarations.constant_entry * strength)

(*s [get_pftreestate ()] returns the current focused pending proof or
   raises [UserError "no focused proof"] *)

val get_pftreestate : unit -> pftreestate

(* [get_goal_context n] returns the context of the [n]th subgoal of
   the current focused proof or raises a [UserError] if there is no
   focused proof or if there is no more subgoals *)

val get_goal_context : int -> enamed_declarations * env

(* [get_current_goal_context ()] works as [get_goal_context 1] *)

val get_current_goal_context : unit -> enamed_declarations * env

(*s [get_current_proof_name ()] return the name of the current focused
    proof or failed if no proof is focused *)

val get_current_proof_name : unit -> identifier

(* [get_all_proof_names ()] returns the list of all pending proof names *)

val get_all_proof_names : unit -> identifier list

(*s [solve_nth n tac] applies tactic [tac] to the [n]th subgoal of the
   current focused proof or raises a UserError if no proof is focused or
   if there is no [n]th subgoal *)

val solve_nth : int -> tactic -> unit

(* [by tac] applies tactic [tac] to the 1st subgoal of the current
   focused proof or raises a UserError if there is no focused proof or
   if there is no more subgoals *)

val by : tactic -> unit

(* [instantiate_nth_evar_com n c] instantiate the [n]th undefined
   existential variable of the current focused proof by [c] or raises a
   UserError if no proof is focused or if there is no such [n]th
   existential variable *)

val instantiate_nth_evar_com : int -> Coqast.t -> unit

(*s To deal with subgoal focus *)

val make_focus : int -> unit
val focus : unit -> int
val focused_goal : unit -> int
val subtree_solved : unit -> bool

val reset_top_of_tree : unit -> unit
val traverse : int -> unit
val traverse_nth_goal : int -> unit
val traverse_next_unproven : unit -> unit
val traverse_prev_unproven : unit -> unit
