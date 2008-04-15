(* -*- coq-prog-args: ("-emacs-U" "-nois") -*- *)
(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* Typeclass-based setoids. Definitions on [Equivalence].
 
   Author: Matthieu Sozeau
   Institution: LRI, CNRS UMR 8623 - Universit�copyright Paris Sud
   91405 Orsay, France *) 

(* $Id$ *)

Require Export Coq.Program.Basics.
Require Import Coq.Program.Tactics.

Require Import Coq.Classes.Init.
Require Import Relation_Definitions.
Require Import Coq.Classes.RelationClasses.
Require Export Coq.Classes.Morphisms.

Set Implicit Arguments.
Unset Strict Implicit.

Open Local Scope signature_scope.

Definition equiv [ Equivalence A R ] : relation A := R.

Typeclasses unfold @equiv.

(** Overloaded notations for setoid equivalence and inequivalence. Not to be confused with [eq] and [=]. *)

Notation " x === y " := (equiv x y) (at level 70, no associativity) : equiv_scope.

Notation " x =/= y " := (complement equiv x y) (at level 70, no associativity) : equiv_scope.
  
Open Local Scope equiv_scope.

(** Overloading for [PER]. *)

Definition pequiv [ PER A R ] : relation A := R.

Typeclasses unfold @pequiv.

(** Overloaded notation for partial equivalence. *)

Infix "=~=" := pequiv (at level 70, no associativity) : equiv_scope.

(** Shortcuts to make proof search easier. *)

Program Instance [ sa : Equivalence A ] => equiv_reflexive : Reflexive equiv.

Program Instance [ sa : Equivalence A ] => equiv_symmetric : Symmetric equiv.

  Next Obligation.
  Proof.
    symmetry ; auto.
  Qed.

Program Instance [ sa : Equivalence A ] => equiv_transitive : Transitive equiv.

  Next Obligation.
  Proof.
    transitivity y ; auto.
  Qed.

(** Use the [substitute] command which substitutes an equivalence in every hypothesis. *)

Ltac setoid_subst H := 
  match type of H with
    ?x === ?y => substitute H ; clear H x
  end.

Ltac setoid_subst_nofail :=
  match goal with
    | [ H : ?x === ?y |- _ ] => setoid_subst H ; setoid_subst_nofail
    | _ => idtac
  end.
  
(** [subst*] will try its best at substituting every equality in the goal. *)

Tactic Notation "subst" "*" := subst_no_fail ; setoid_subst_nofail.

(** Simplify the goal w.r.t. equivalence. *)

Ltac equiv_simplify_one :=
  match goal with
    | [ H : ?x === ?x |- _ ] => clear H
    | [ H : ?x === ?y |- _ ] => setoid_subst H
    | [ |- ?x =/= ?y ] => let name:=fresh "Hneq" in intro name
    | [ |- ~ ?x === ?y ] => let name:=fresh "Hneq" in intro name
  end.

Ltac equiv_simplify := repeat equiv_simplify_one.

(** "reify" relations which are equivalences to applications of the overloaded [equiv] method
   for easy recognition in tactics. *)

Ltac equivify_tac :=
  match goal with
    | [ s : Equivalence ?A ?R, H : ?R ?x ?y |- _ ] => change R with (@equiv A R s) in H
    | [ s : Equivalence ?A ?R |- context C [ ?R ?x ?y ] ] => change (R x y) with (@equiv A R s x y)
  end.

Ltac equivify := repeat equivify_tac.

Section Respecting.

  (** Here we build an equivalence instance for functions which relates respectful ones only, 
     we do not export it. *)

  Definition respecting [ Equivalence A (R : relation A), Equivalence B (R' : relation B) ] : Type := 
    { morph : A -> B | respectful R R' morph morph }.
  
  Program Instance [ Equivalence A R, Equivalence B R' ] => 
    respecting_equiv : Equivalence respecting
    (fun (f g : respecting) => forall (x y : A), R x y -> R' (proj1_sig f x) (proj1_sig g y)).

  Solve Obligations using unfold respecting in * ; simpl_relation ; program_simpl.

  Next Obligation.
  Proof. 
    unfold respecting in *. program_simpl. red in H2,H3,H4. 
    transitivity (y x0) ; auto.
    transitivity (y y0) ; auto.
    symmetry. auto.
  Qed.

End Respecting.

(** The default equivalence on function spaces, with higher-priority than [eq]. *)

Program Instance [ Equivalence A eqA ] => 
  pointwise_equivalence : Equivalence (B -> A) (pointwise_relation eqA) | 9.

  Next Obligation.
  Proof.
    transitivity (y x0) ; auto.
  Qed.

