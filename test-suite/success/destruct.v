(* Submitted by Robert Schneck *)

Parameter A B C D : Prop.
Axiom X : A -> B -> C /\ D.

Lemma foo : A -> B -> C.
Proof.
intros. 
destruct X. (* Should find axiom X and should handle arguments of X *)
assumption.
assumption.
assumption.
Qed.

(* Simplification of bug 711 *)

Parameter f : true = false.
Goal let p := f in True.
intro p.
set (b := true) in *.
(* Check that it doesn't fail with an anomaly *)
(* Ultimately, adapt destruct to make it succeeding *)
try destruct b.
Abort.

(* Used to fail with error "n is used in conclusion" before revision 9447 *)

Goal forall n, n = S n.
induction S.
Abort.

(* Check that elimination with remaining evars do not raise an bad
   error message *)

Theorem Refl : forall P, P <-> P. tauto. Qed.
Goal True.
case Refl || ecase Refl.
Abort.


(* Submitted by B. Baydemir (bug #1882) *)

Require Import List.

Definition alist R := list (nat * R)%type.

Section Properties.
  Variables A : Type.
  Variables a : A.
  Variables E : alist A.

  Lemma silly : E = E.
  Proof.
    clear. induction E.  (* this fails. *)
  Abort.

End Properties.
