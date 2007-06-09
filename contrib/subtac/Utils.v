Require Export Coq.subtac.SubtacTactics.

Set Implicit Arguments.

Notation " {{ x }} " := (tt : { y : unit | x }).

Notation "{ ( x , y )  :  A  |  P }" := 
  (sig (fun anonymous : A => let (x,y) := anonymous in P))
  (x ident, y ident) : type_scope.

Notation " ! " := (False_rect _ _).

Notation " ` t " := (proj1_sig t) (at level 10) : core_scope.
Notation "( x & ? )" := (@exist _ _ x _) : core_scope.

(** Coerces objects before comparing them *)
Notation " x '`=' y " := ((x :>) = (y :>)) (at level 70).

(** Quantifying over subsets *)
Notation "'fun' { x : A | P } => Q" :=
  (fun x:{x:A|P} => Q)
  (at level 200, x ident, right associativity).

Notation "'forall' { x : A | P } , Q" :=
  (forall x:{x:A|P}, Q)
  (at level 200, x ident, right associativity).

Require Import Coq.Bool.Sumbool.	
Notation "'dec'" := (sumbool_of_bool) (at level 0). 

(** Default simplification tactic. *)
Ltac subtac_simpl := simpl ; intros ; destruct_conjs ; simpl in * ; try subst ; 
  try (solve [ red ; intros ; discriminate ]) ; auto with *.  

(** Extraction directives *)
Extraction Inline proj1_sig.
Extract Inductive unit => "unit" [ "()" ].
Extract Inductive bool => "bool" [ "true" "false" ].
Extract Inductive sumbool => "bool" [ "true" "false" ].
Axiom pair : Type -> Type -> Type.
Extract Constant pair "'a" "'b" => " 'a * 'b ".
Extract Inductive prod => "pair" [ "" ].
Extract Inductive sigT => "pair" [ "" ].

Require Export ProofIrrelevance.
Require Export Coq.subtac.Heq.

Delimit Scope program_scope with program.
