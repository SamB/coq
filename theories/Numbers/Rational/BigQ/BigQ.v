(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)
(*            Benjamin Gregoire, Laurent Thery, INRIA, 2007             *)
(************************************************************************)

(*i $Id$ i*)

Require Import Field Qfield BigN BigZ QSig QMake.

(** We choose for BigQ an implemention with
    multiple representation of 0: 0, 1/0, 2/0 etc.
    See [QMake.v] *)

(** First, we provide translations functions between [BigN] and [BigZ] *)

Module BigN_BigZ <: NType_ZType BigN.BigN BigZ.
 Definition Z_of_N := BigZ.Pos.
 Lemma spec_Z_of_N : forall n, BigZ.to_Z (Z_of_N n) = BigN.to_Z n.
 Proof.
 reflexivity.
 Qed.
 Definition Zabs_N := BigZ.to_N.
 Lemma spec_Zabs_N : forall z, BigN.to_Z (Zabs_N z) = Zabs (BigZ.to_Z z).
 Proof.
 unfold Zabs_N; intros.
 rewrite BigZ.spec_to_Z, Zmult_comm; apply Zsgn_Zabs.
 Qed.
End BigN_BigZ.

(** This allows to build [BigQ] out of [BigN] and [BigQ] via [QMake] *)

Module BigQ <: QSig.QType := QMake.Make BigN BigZ BigN_BigZ.

(** Notations about [BigQ] *)

Notation bigQ := BigQ.t.

Delimit Scope bigQ_scope with bigQ.
Bind Scope bigQ_scope with bigQ.
Bind Scope bigQ_scope with BigQ.t.

Infix "+" := BigQ.add : bigQ_scope.
Infix "-" := BigQ.sub : bigQ_scope.
Notation "- x" := (BigQ.opp x) : bigQ_scope.
Infix "*" := BigQ.mul : bigQ_scope.
Infix "/" := BigQ.div : bigQ_scope.
Infix "^" := BigQ.power : bigQ_scope.
Infix "?=" := BigQ.compare : bigQ_scope.
Infix "==" := BigQ.eq : bigQ_scope.
Infix "<" := BigQ.lt : bigQ_scope.
Infix "<=" := BigQ.le : bigQ_scope.
Notation "[ q ]" := (BigQ.to_Q q) : bigQ_scope. 

Open Scope bigQ_scope.

(** [BigQ] is a setoid *)

Add Relation BigQ.t BigQ.eq
 reflexivity proved by (fun x => Qeq_refl [x])
 symmetry proved by (fun x y => Qeq_sym [x] [y])
 transitivity proved by (fun x y z => Qeq_trans [x] [y] [z])
as BigQeq_rel.

Add Morphism BigQ.add with signature BigQ.eq ==> BigQ.eq ==> BigQ.eq as BigQadd_wd.
Proof.
 unfold BigQ.eq; intros; rewrite !BigQ.spec_add; rewrite H, H0; apply Qeq_refl.
Qed.

Add Morphism BigQ.opp with signature BigQ.eq ==> BigQ.eq as BigQopp_wd.
Proof.
 unfold BigQ.eq; intros; rewrite !BigQ.spec_opp; rewrite H; apply Qeq_refl.
Qed.

Add Morphism BigQ.sub with signature BigQ.eq ==> BigQ.eq ==> BigQ.eq as BigQsub_wd.
Proof.
 unfold BigQ.eq; intros; rewrite !BigQ.spec_sub; rewrite H, H0; apply Qeq_refl.
Qed.

Add Morphism BigQ.mul with signature BigQ.eq ==> BigQ.eq ==> BigQ.eq as BigQmul_wd.
Proof.
 unfold BigQ.eq; intros; rewrite !BigQ.spec_mul; rewrite H, H0; apply Qeq_refl.
Qed.

Add Morphism BigQ.inv with signature BigQ.eq ==> BigQ.eq as BigQinv_wd.
Proof.
 unfold BigQ.eq; intros; rewrite !BigQ.spec_inv; rewrite H; apply Qeq_refl.
Qed.

Add Morphism BigQ.div with signature BigQ.eq ==> BigQ.eq ==> BigQ.eq as BigQdiv_wd.
Proof.
 unfold BigQ.eq; intros; rewrite !BigQ.spec_div; rewrite H, H0; apply Qeq_refl.
Qed.

(* TODO : fix this. For the moment it's useless (horribly slow)
Hint Rewrite 
 BigQ.spec_0 BigQ.spec_1 BigQ.spec_m1 BigQ.spec_compare
 BigQ.spec_red BigQ.spec_add BigQ.spec_sub BigQ.spec_opp 
 BigQ.spec_mul BigQ.spec_inv BigQ.spec_div BigQ.spec_power_pos
 BigQ.spec_square : bigq. *)


(** [BigQ] is a field *)

Lemma BigQfieldth : 
 field_theory BigQ.zero BigQ.one BigQ.add BigQ.mul BigQ.sub BigQ.opp BigQ.div BigQ.inv BigQ.eq.
Proof.
constructor.
constructor; intros; red.
rewrite BigQ.spec_add, BigQ.spec_0; ring.
rewrite ! BigQ.spec_add; ring.
rewrite ! BigQ.spec_add; ring.
rewrite BigQ.spec_mul, BigQ.spec_1; ring.
rewrite ! BigQ.spec_mul; ring.
rewrite ! BigQ.spec_mul; ring.
rewrite BigQ.spec_add, ! BigQ.spec_mul, BigQ.spec_add; ring.
unfold BigQ.sub; apply Qeq_refl.
rewrite BigQ.spec_add, BigQ.spec_0, BigQ.spec_opp; ring.
compute; discriminate.
intros; red.
unfold BigQ.div; apply Qeq_refl.
intros; red.
rewrite BigQ.spec_mul, BigQ.spec_inv, BigQ.spec_1; field.
rewrite <- BigQ.spec_0; auto.
Qed.

Lemma BigQpowerth : 
 power_theory BigQ.one BigQ.mul BigQ.eq Z_of_N BigQ.power.
Proof.
constructor.
intros; red.
rewrite BigQ.spec_power.
replace ([r] ^ Z_of_N n)%Q with (pow_N 1 Qmult [r] n)%Q.
destruct n.
simpl; compute; auto.
induction p; simpl; auto; try rewrite !BigQ.spec_mul, !IHp; apply Qeq_refl.
destruct n; reflexivity.
Qed.

Lemma BigQ_eq_bool_correct : 
 forall x y, BigQ.eq_bool x y = true -> x==y.
Proof.
intros; generalize (BigQ.spec_eq_bool x y); rewrite H; auto.
Qed.

Lemma BigQ_eq_bool_complete : 
 forall x y, x==y -> BigQ.eq_bool x y = true.
Proof.
intros; generalize (BigQ.spec_eq_bool x y).
destruct BigQ.eq_bool; auto.
Qed.

(* TODO : improve later the detection of constants ... *)

Ltac BigQcst t := 
 match t with 
   | BigQ.zero => BigQ.zero
   | BigQ.one => BigQ.one
   | BigQ.minus_one => BigQ.minus_one
   | _ => NotConstant 
 end.

Add Field BigQfield : BigQfieldth 
 (decidable BigQ_eq_bool_correct, 
  completeness BigQ_eq_bool_complete,
  constants [BigQcst],
  power_tac BigQpowerth [Qpow_tac]).

Section Examples.

Let ex1 : forall x y z, (x+y)*z ==  (x*z)+(y*z).
  intros.
  ring.
Qed.

Let ex8 : forall x, x ^ 1 == x.
  intro.
  ring.
Qed.

Let ex10 : forall x y, ~(y==BigQ.zero) -> (x/y)*y == x.
intros.
field.
auto.
Qed.

End Examples.