(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

(** Classical Predicate Logic on Set*)

Require Import Classical_Prop.

Section Generic.
Variable U : Set.

(** de Morgan laws for quantifiers *)

Lemma not_all_ex_not :
 forall P:U -> Prop, ~ (forall n:U, P n) ->  exists n : U, ~ P n.
Proof.
unfold not in |- *; intros P notall.
apply NNPP; unfold not in |- *.
intro abs.
cut (forall n:U, P n); auto.
intro n; apply NNPP.
unfold not in |- *; intros.
apply abs; exists n; trivial.
Qed.

Lemma not_all_not_ex :
 forall P:U -> Prop, ~ (forall n:U, ~ P n) ->  exists n : U, P n.
Proof.
intros P H.
elim (not_all_ex_not (fun n:U => ~ P n) H); intros n Pn; exists n.
apply NNPP; trivial.
Qed.

Lemma not_ex_all_not :
 forall P:U -> Prop, ~ (exists n : U, P n) -> forall n:U, ~ P n.
Proof.
unfold not in |- *; intros P notex n abs.
apply notex.
exists n; trivial.
Qed. 

Lemma not_ex_not_all :
 forall P:U -> Prop, ~ (exists n : U, ~ P n) -> forall n:U, P n.
Proof.
intros P H n.
apply NNPP.
red in |- *; intro K; apply H; exists n; trivial.
Qed.

Lemma ex_not_not_all :
 forall P:U -> Prop, (exists n : U, ~ P n) -> ~ (forall n:U, P n).
Proof.
unfold not in |- *; intros P exnot allP.
elim exnot; auto.
Qed.

Lemma all_not_not_ex :
 forall P:U -> Prop, (forall n:U, ~ P n) -> ~ (exists n : U, P n).
Proof.
unfold not in |- *; intros P allnot exP; elim exP; intros n p.
apply allnot with n; auto.
Qed.

End Generic.