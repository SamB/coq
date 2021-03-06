(* -*- coq-prog-name: "coqtop.byte"; coq-prog-args: ("-emacs-U" "-top" "Coq.Classes.RelationClasses") -*- *)
(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* Typeclass-based relations, tactics and standard instances.
   This is the basic theory needed to formalize morphisms and setoids.
 
   Author: Matthieu Sozeau
   Institution: LRI, CNRS UMR 8623 - UniversitÃcopyright Paris Sud
   91405 Orsay, France *)

(* $Id$ *)

Require Export Coq.Classes.Init.
Require Import Coq.Program.Basics.
Require Import Coq.Program.Tactics.
Require Export Coq.Relations.Relation_Definitions.

Notation inverse R := (flip (R:relation _) : relation _).

Definition complement {A} (R : relation A) : relation A := fun x y => R x y -> False.

Definition pointwise_relation {A B : Type} (R : relation B) : relation (A -> B) := 
  fun f g => forall x : A, R (f x) (g x).

(** These are convertible. *)

Lemma complement_inverse : forall A (R : relation A), complement (inverse R) = inverse (complement R).
Proof. reflexivity. Qed.

(** We rebind relations in separate classes to be able to overload each proof. *)

Set Implicit Arguments.
Unset Strict Implicit.

Class Reflexive A (R : relation A) :=
  reflexivity : forall x, R x x.

Class Irreflexive A (R : relation A) := 
  irreflexivity :> Reflexive A (complement R).

Class Symmetric A (R : relation A) := 
  symmetry : forall x y, R x y -> R y x.

Class Asymmetric A (R : relation A) := 
  asymmetry : forall x y, R x y -> R y x -> False.

Class Transitive A (R : relation A) := 
  transitivity : forall x y z, R x y -> R y z -> R x z.

Implicit Arguments Reflexive [A].
Implicit Arguments Irreflexive [A].
Implicit Arguments Symmetric [A].
Implicit Arguments Asymmetric [A].
Implicit Arguments Transitive [A].

Hint Resolve @irreflexivity : ord.

Unset Implicit Arguments.

(** We can already dualize all these properties. *)

Program Instance flip_Reflexive [ Reflexive A R ] : Reflexive (flip R) :=
  reflexivity := reflexivity (R:=R).

Program Instance flip_Irreflexive [ Irreflexive A R ] : Irreflexive (flip R) :=
  irreflexivity := irreflexivity (R:=R).

Program Instance flip_Symmetric [ Symmetric A R ] : Symmetric (flip R).

  Solve Obligations using unfold flip ; program_simpl ; clapply Symmetric.

Program Instance flip_Asymmetric [ Asymmetric A R ] : Asymmetric (flip R).
  
  Solve Obligations using program_simpl ; unfold flip in * ; intros ; clapply asymmetry.

Program Instance flip_Transitive [ Transitive A R ] : Transitive (flip R).

  Solve Obligations using unfold flip ; program_simpl ; clapply transitivity.

Program Instance Reflexive_complement_Irreflexive [ Reflexive A (R : relation A) ]
   : Irreflexive (complement R).

  Next Obligation. 
  Proof. 
    unfold complement.
    red. intros H.
    intros H' ; apply H'.
    apply reflexivity.
  Qed.


Program Instance complement_Symmetric [ Symmetric A (R : relation A) ] : Symmetric (complement R).

  Next Obligation.
  Proof.
    red ; intros H'.
    apply (H (symmetry H')).
  Qed.

(** * Standard instances. *)

Ltac reduce_hyp H :=
  match type of H with
    | context [ _ <-> _ ] => fail 1
    | _ => red in H ; try reduce_hyp H
  end.

Ltac reduce_goal :=
  match goal with
    | [ |- _ <-> _ ] => fail 1
    | _ => red ; intros ; try reduce_goal
  end.

Tactic Notation "reduce" "in" hyp(Hid) := reduce_hyp Hid.

Ltac reduce := reduce_goal.

Tactic Notation "apply" "*" constr(t) := 
  first [ refine t | refine (t _) | refine (t _ _) | refine (t _ _ _) | refine (t _ _ _ _) |
    refine (t _ _ _ _ _) | refine (t _ _ _ _ _ _) | refine (t _ _ _ _ _ _ _) ].

Ltac simpl_relation :=
  unfold flip, impl, arrow ; try reduce ; program_simpl ;
    try ( solve [ intuition ]).

Ltac obligation_tactic ::= simpl_relation.

(** Logical implication. *)

Program Instance impl_Reflexive : Reflexive impl.
Program Instance impl_Transitive : Transitive impl.

(** Logical equivalence. *)

Program Instance iff_Reflexive : Reflexive iff.
Program Instance iff_Symmetric : Symmetric iff.
Program Instance iff_Transitive : Transitive iff.

(** Leibniz equality. *)

Program Instance eq_Reflexive : Reflexive (@eq A).
Program Instance eq_Symmetric : Symmetric (@eq A).
Program Instance eq_Transitive : Transitive (@eq A).

(** Various combinations of reflexivity, symmetry and transitivity. *)

(** A [PreOrder] is both Reflexive and Transitive. *)

Class PreOrder A (R : relation A) : Prop :=
  PreOrder_Reflexive :> Reflexive R ;
  PreOrder_Transitive :> Transitive R.

(** A partial equivalence relation is Symmetric and Transitive. *)

Class PER (carrier : Type) (pequiv : relation carrier) : Prop :=
  PER_Symmetric :> Symmetric pequiv ;
  PER_Transitive :> Transitive pequiv.

(** Equivalence relations. *)

Class Equivalence (carrier : Type) (equiv : relation carrier) : Prop :=
  Equivalence_Reflexive :> Reflexive equiv ;
  Equivalence_Symmetric :> Symmetric equiv ;
  Equivalence_Transitive :> Transitive equiv.

(** An Equivalence is a PER plus reflexivity. *)

Instance Equivalence_PER [ Equivalence A R ] : PER A R | 10 :=
  PER_Symmetric := Equivalence_Symmetric ;
  PER_Transitive := Equivalence_Transitive.

(** We can now define antisymmetry w.r.t. an equivalence relation on the carrier. *)

Class [ Equivalence A eqA ] => Antisymmetric (R : relation A) := 
  antisymmetry : forall x y, R x y -> R y x -> eqA x y.

Program Instance flip_antiSymmetric [ eq : Equivalence A eqA, ! Antisymmetric eq R ] :
  Antisymmetric eq (flip R).

(** Leibinz equality [eq] is an equivalence relation.
   The instance has low priority as it is always applicable 
   if only the type is constrained. *)

Program Instance eq_equivalence : Equivalence A (@eq A) | 10.

(** Logical equivalence [iff] is an equivalence relation. *)

Program Instance iff_equivalence : Equivalence Prop iff.

(** We now develop a generalization of results on relations for arbitrary predicates.
   The resulting theory can be applied to homogeneous binary relations but also to
   arbitrary n-ary predicates. *)

Require Import List.

(* Notation " [ ] " := nil : list_scope. *)
(* Notation " [ x ; .. ; y ] " := (cons x .. (cons y nil) ..) (at level 1) : list_scope. *)

(* Open Local Scope list_scope. *)

(** A compact representation of non-dependent arities, with the codomain singled-out. *)

Fixpoint arrows (l : list Type) (r : Type) : Type := 
  match l with 
    | nil => r
    | A :: l' => A -> arrows l' r
  end.

(** We can define abbreviations for operation and relation types based on [arrows]. *)

Definition unary_operation A := arrows (cons A nil) A.
Definition binary_operation A := arrows (cons A (cons A nil)) A.
Definition ternary_operation A := arrows (cons A (cons A (cons A nil))) A.

(** We define n-ary [predicate]s as functions into [Prop]. *)

Notation predicate l := (arrows l Prop).

(** Unary predicates, or sets. *)

Definition unary_predicate A := predicate (cons A nil).

(** Homogeneous binary relations, equivalent to [relation A]. *)

Definition binary_relation A := predicate (cons A (cons A nil)).

(** We can close a predicate by universal or existential quantification. *) 

Fixpoint predicate_all (l : list Type) : predicate l -> Prop :=
  match l with
    | nil => fun f => f
    | A :: tl => fun f => forall x : A, predicate_all tl (f x)
  end.

Fixpoint predicate_exists (l : list Type) : predicate l -> Prop :=
  match l with
    | nil => fun f => f
    | A :: tl => fun f => exists x : A, predicate_exists tl (f x)
  end.

(** Pointwise extension of a binary operation on [T] to a binary operation 
   on functions whose codomain is [T].
   For an operator on [Prop] this lifts the operator to a binary operation. *)

Fixpoint pointwise_extension {T : Type} (op : binary_operation T)
  (l : list Type) : binary_operation (arrows l T) :=
  match l with
    | nil => fun R R' => op R R'
    | A :: tl => fun R R' => 
      fun x => pointwise_extension op tl (R x) (R' x)
  end.

(** Pointwise lifting, equivalent to doing [pointwise_extension] and closing using [predicate_all]. *)

Fixpoint pointwise_lifting (op : binary_relation Prop)  (l : list Type) : binary_relation (predicate l) :=
  match l with
    | nil => fun R R' => op R R'
    | A :: tl => fun R R' => 
      forall x, pointwise_lifting op tl (R x) (R' x)
  end.

(** The n-ary equivalence relation, defined by lifting the 0-ary [iff] relation. *)

Definition predicate_equivalence {l : list Type} : binary_relation (predicate l) :=
  pointwise_lifting iff l.

(** The n-ary implication relation, defined by lifting the 0-ary [impl] relation. *)

Definition predicate_implication {l : list Type} :=
  pointwise_lifting impl l.

(** Notations for pointwise equivalence and implication of predicates. *)

Infix "<∙>" := predicate_equivalence (at level 95, no associativity) : predicate_scope.
Infix "-∙>" := predicate_implication (at level 70) : predicate_scope.

Open Local Scope predicate_scope.

(** The pointwise liftings of conjunction and disjunctions.
   Note that these are [binary_operation]s, building new relations out of old ones. *)

Definition predicate_intersection := pointwise_extension and.
Definition predicate_union := pointwise_extension or.

Infix "/∙\" := predicate_intersection (at level 80, right associativity) : predicate_scope.
Infix "\∙/" := predicate_union (at level 85, right associativity) : predicate_scope.

(** The always [True] and always [False] predicates. *)

Fixpoint true_predicate {l : list Type} : predicate l := 
  match l with
    | nil => True
    | A :: tl => fun _ => @true_predicate tl
  end.

Fixpoint false_predicate {l : list Type} : predicate l :=
  match l with
    | nil => False
    | A :: tl => fun _ => @false_predicate tl
  end.

Notation "∙⊤∙" := true_predicate : predicate_scope.
Notation "∙⊥∙" := false_predicate : predicate_scope.

(** Predicate equivalence is an equivalence, and predicate implication defines a preorder. *)

Program Instance predicate_equivalence_equivalence :
  Equivalence (predicate l) predicate_equivalence.

  Next Obligation.
    induction l ; firstorder.
  Qed.

  Next Obligation.
    induction l ; firstorder.
  Qed.
  
  Next Obligation.
    fold pointwise_lifting.
    induction l. firstorder.
    intros. simpl in *. pose (IHl (x x0) (y x0) (z x0)).
    firstorder.
  Qed.

Program Instance predicate_implication_preorder :
  PreOrder (predicate l) predicate_implication.

  Next Obligation.
    induction l ; firstorder.
  Qed.

  Next Obligation.
    induction l. firstorder.
    unfold predicate_implication in *. simpl in *. 
    intro. pose (IHl (x x0) (y x0) (z x0)). firstorder.
  Qed.

(** We define the various operations which define the algebra on binary relations, 
   from the general ones. *)

Definition relation_equivalence {A : Type} : relation (relation A) :=
  @predicate_equivalence (cons _ (cons _ nil)).

Class subrelation {A:Type} (R R' : relation A) : Prop :=
  is_subrelation : @predicate_implication (cons A (cons A nil)) R R'.

Implicit Arguments subrelation [[A]].

Definition relation_conjunction {A} (R : relation A) (R' : relation A) : relation A :=
  @predicate_intersection (cons A (cons A nil)) R R'.

Definition relation_disjunction {A} (R : relation A) (R' : relation A) : relation A :=
  @predicate_union (cons A (cons A nil)) R R'.

(** Relation equivalence is an equivalence, and subrelation defines a partial order. *)

Instance relation_equivalence_equivalence (A : Type) :
  Equivalence (relation A) relation_equivalence.
Proof. intro A. exact (@predicate_equivalence_equivalence (cons A (cons A nil))). Qed.

Instance relation_implication_preorder : PreOrder (relation A) subrelation.
Proof. intro A. exact (@predicate_implication_preorder (cons A (cons A nil))). Qed.

(** *** Partial Order.
   A partial order is a preorder which is additionally antisymmetric.
   We give an equivalent definition, up-to an equivalence relation 
   on the carrier. *)

Class [ equ : Equivalence A eqA, PreOrder A R ] => PartialOrder :=
  partial_order_equivalence : relation_equivalence eqA (relation_conjunction R (inverse R)).

(** The equivalence proof is sufficient for proving that [R] must be a morphism 
   for equivalence (see Morphisms).
   It is also sufficient to show that [R] is antisymmetric w.r.t. [eqA] *)

Instance partial_order_antisym [ PartialOrder A eqA R ] : ! Antisymmetric A eqA R.
Proof with auto.
  reduce_goal. pose proof partial_order_equivalence as poe. do 3 red in poe. 
  apply <- poe. firstorder.
Qed.

(** The partial order defined by subrelation and relation equivalence. *)

Program Instance subrelation_partial_order :
  ! PartialOrder (relation A) relation_equivalence subrelation.

  Next Obligation.
  Proof.
    unfold relation_equivalence in *. firstorder.
  Qed.

Lemma inverse_pointwise_relation A (R : relation A) : 
  relation_equivalence (pointwise_relation (inverse R)) (inverse (pointwise_relation (A:=A) R)).
Proof. reflexivity. Qed.
