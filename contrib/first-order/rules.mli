(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

open Term
open Tacmach
open Names
open Libnames

type seqtac= (Sequent.t -> tactic) -> Sequent.t -> tactic

type lseqtac= global_reference -> seqtac

val wrap : int -> bool -> seqtac

val clear_global: global_reference -> tactic

val axiom_tac : constr -> Sequent.t -> tactic

val evaluable_tac : evaluable_global_reference -> seqtac

val left_evaluable_tac : evaluable_global_reference -> lseqtac

val and_tac : seqtac

val left_and_tac : inductive -> lseqtac

val or_tac : seqtac

val left_or_tac : inductive -> lseqtac

val forall_tac : seqtac

val left_forall_tac : int -> types -> (bool * constr) list -> bool -> lseqtac

val arrow_tac : seqtac

val exists_tac : int -> types -> (bool * constr) list -> seqtac
	       
val left_exists_tac : lseqtac

val ll_arrow_tac : constr -> constr -> constr -> lseqtac

val ll_atom_tac : constr -> lseqtac

val ll_false_tac : lseqtac

val left_false_tac : global_reference -> tactic

val ll_ind_tac : inductive -> constr list -> lseqtac

val ll_forall_tac : types -> lseqtac
