(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

(** * Finite maps library *)

(** This functor derives additional facts from [FMapWeakInterface.S]. These
  facts are mainly the specifications of [FMapWeakInterface.S] written using 
  different styles: equivalence and boolean equalities. 
*)

Require Import Bool.
Require Import OrderedType.
Require Export FMapWeakInterface. 
Set Implicit Arguments.
Unset Strict Implicit.

Module Facts (M: S).
Import M.
Import Logic. (* to unmask [eq] *)  
Import Peano. (* to unmask [lt] *)

Lemma MapsTo_fun : forall (elt:Set) m x (e e':elt), 
  MapsTo x e m -> MapsTo x e' m -> e=e'.
Proof.
intros.
generalize (find_1 H) (find_1 H0); clear H H0.
intros; rewrite H in H0; injection H0; auto.
Qed.

(** * Specifications written using equivalences *)

Section IffSpec. 
Variable elt elt' elt'': Set.
Implicit Type m: t elt.
Implicit Type x y z: key.
Implicit Type e: elt.

Lemma MapsTo_iff : forall m x y e, E.eq x y -> (MapsTo x e m <-> MapsTo y e m).
Proof.
split; apply MapsTo_1; auto.
Qed.

Lemma In_iff : forall m x y, E.eq x y -> (In x m <-> In y m).
Proof.
unfold In.
split; intros (e0,H0); exists e0.
apply (MapsTo_1 H H0); auto.
apply (MapsTo_1 (E.eq_sym H) H0); auto.
Qed.

Lemma find_mapsto_iff : forall m x e, MapsTo x e m <-> find x m = Some e.
Proof.
split; [apply find_1|apply find_2].
Qed.

Lemma not_find_mapsto_iff : forall m x, ~In x m <-> find x m = None.
Proof.
intros.
generalize (find_mapsto_iff m x); destruct (find x m).
split; intros; try discriminate.
destruct H0.
exists e; rewrite H; auto.
split; auto.
intros; intros (e,H1).
rewrite H in H1; discriminate.
Qed.

Lemma mem_in_iff : forall m x, In x m <-> mem x m = true.
Proof.
split; [apply mem_1|apply mem_2].
Qed.

Lemma not_mem_in_iff : forall m x, ~In x m <-> mem x m = false.
Proof.
intros; rewrite mem_in_iff; destruct (mem x m); intuition.
Qed.

Lemma equal_iff : forall m m' cmp, Equal cmp m m' <-> equal cmp m m' = true.
Proof. 
split; [apply equal_1|apply equal_2].
Qed.

Lemma empty_mapsto_iff : forall x e, MapsTo x e (empty elt) <-> False.
Proof.
intuition; apply (empty_1 H).
Qed.

Lemma empty_in_iff : forall x, In x (empty elt) <-> False.
Proof.
unfold In.
split; [intros (e,H); rewrite empty_mapsto_iff in H|]; intuition.
Qed.

Lemma is_empty_iff : forall m, Empty m <-> is_empty m = true. 
Proof. 
split; [apply is_empty_1|apply is_empty_2].
Qed.

Lemma add_mapsto_iff : forall m x y e e', 
  MapsTo y e' (add x e m) <-> 
     (E.eq x y /\ e=e') \/ 
     (~E.eq x y /\ MapsTo y e' m).
Proof. 
intros.
intuition.
destruct (E.eq_dec x y); [left|right].
split; auto.
symmetry; apply (MapsTo_fun (e':=e) H); auto.
split; auto; apply add_3 with x e; auto.
subst; auto.
Qed.

Lemma add_in_iff : forall m x y e, In y (add x e m) <-> E.eq x y \/ In y m.
Proof. 
unfold In; split.
intros (e',H).
destruct (E.eq_dec x y) as [E|E]; auto.
right; exists e'; auto.
apply (add_3 E H).
destruct (E.eq_dec x y) as [E|E]; auto.
intros.
exists e; apply add_1; auto.
intros [H|(e',H)].
destruct E; auto.
exists e'; apply add_2; auto.
Qed.

Lemma add_neq_mapsto_iff : forall m x y e e', 
 ~ E.eq x y -> (MapsTo y e' (add x e m)  <-> MapsTo y e' m).
Proof.
split; [apply add_3|apply add_2]; auto.
Qed.

Lemma add_neq_in_iff : forall m x y e, 
 ~ E.eq x y -> (In y (add x e m)  <-> In y m).
Proof.
split; intros (e',H0); exists e'.
apply (add_3 H H0).
apply add_2; auto.
Qed.

Lemma remove_mapsto_iff : forall m x y e, 
  MapsTo y e (remove x m) <-> ~E.eq x y /\ MapsTo y e m.
Proof. 
intros.
split; intros.
split.
assert (In y (remove x m)) by (exists e; auto).
intro H1; apply (remove_1 H1 H0).
apply remove_3 with x; auto.
apply remove_2; intuition.
Qed.

Lemma remove_in_iff : forall m x y, In y (remove x m) <-> ~E.eq x y /\ In y m.
Proof. 
unfold In; split.
intros (e,H).
split.
assert (In y (remove x m)) by (exists e; auto).
intro H1; apply (remove_1 H1 H0).
exists e; apply remove_3 with x; auto.
intros (H,(e,H0)); exists e; apply remove_2; auto.
Qed.

Lemma remove_neq_mapsto_iff : forall m x y e, 
 ~ E.eq x y -> (MapsTo y e (remove x m)  <-> MapsTo y e m).
Proof.
split; [apply remove_3|apply remove_2]; auto.
Qed.

Lemma remove_neq_in_iff : forall m x y, 
 ~ E.eq x y -> (In y (remove x m)  <-> In y m).
Proof.
split; intros (e',H0); exists e'.
apply (remove_3 H0).
apply remove_2; auto.
Qed.

Lemma elements_mapsto_iff : forall m x e, 
 MapsTo x e m <-> InA (@eq_key_elt _) (x,e) (elements m).
Proof. 
split; [apply elements_1 | apply elements_2].
Qed.

Lemma elements_in_iff : forall m x, 
 In x m <-> exists e, InA (@eq_key_elt _) (x,e) (elements m).
Proof. 
unfold In; split; intros (e,H); exists e; [apply elements_1 | apply elements_2]; auto.
Qed.

Lemma map_mapsto_iff : forall m x b (f : elt -> elt'), 
 MapsTo x b (map f m) <-> exists a, b = f a /\ MapsTo x a m.
Proof.
split.
case_eq (find x m); intros.
exists e.
split.
apply (MapsTo_fun (m:=map f m) (x:=x)); auto.
apply find_2; auto.
assert (In x (map f m)) by (exists b; auto).
destruct (map_2 H1) as (a,H2).
rewrite (find_1 H2) in H; discriminate.
intros (a,(H,H0)).
subst b; auto.
Qed.

Lemma map_in_iff : forall m x (f : elt -> elt'), 
 In x (map f m) <-> In x m.
Proof.
split; intros; eauto.
destruct H as (a,H).
exists (f a); auto.
Qed.

Lemma mapi_in_iff : forall m x (f:key->elt->elt'),
 In x (mapi f m) <-> In x m.
Proof.
split; intros; eauto.
destruct H as (a,H).
destruct (mapi_1 f H) as (y,(H0,H1)).
exists (f y a); auto.
Qed.

(* Unfortunately, we don't have simple equivalences for [mapi] 
  and [MapsTo]. The only correct one needs compatibility of [f]. *) 

Lemma mapi_inv : forall m x b (f : key -> elt -> elt'), 
 MapsTo x b (mapi f m) -> 
 exists a, exists y, E.eq y x /\ b = f y a /\ MapsTo x a m.
Proof.
intros; case_eq (find x m); intros.
exists e.
destruct (@mapi_1 _ _ m x e f) as (y,(H1,H2)).
apply find_2; auto.
exists y; repeat split; auto.
apply (MapsTo_fun (m:=mapi f m) (x:=x)); auto.
assert (In x (mapi f m)) by (exists b; auto).
destruct (mapi_2 H1) as (a,H2).
rewrite (find_1 H2) in H0; discriminate.
Qed.

Lemma mapi_1bis : forall m x e (f:key->elt->elt'), 
 (forall x y e, E.eq x y -> f x e = f y e) -> 
 MapsTo x e m -> MapsTo x (f x e) (mapi f m).
Proof.
intros.
destruct (mapi_1 f H0) as (y,(H1,H2)).
replace (f x e) with (f y e) by auto.
auto.
Qed.

Lemma mapi_mapsto_iff : forall m x b (f:key->elt->elt'),
 (forall x y e, E.eq x y -> f x e = f y e) -> 
 (MapsTo x b (mapi f m) <-> exists a, b = f x a /\ MapsTo x a m).
Proof.
split.
intros.
destruct (mapi_inv H0) as (a,(y,(H1,(H2,H3)))).
exists a; split; auto.
subst b; auto.
intros (a,(H0,H1)).
subst b.
apply mapi_1bis; auto.
Qed.

(** Things are even worse for [map2] : we don't try to state any 
 equivalence, see instead boolean results below. *)

End IffSpec.

(** Useful tactic for simplifying expressions like [In y (add x e (remove z m))] *)
  
Ltac map_iff := 
 repeat (progress (
  rewrite add_mapsto_iff || rewrite add_in_iff ||
  rewrite remove_mapsto_iff || rewrite remove_in_iff ||
  rewrite empty_mapsto_iff || rewrite empty_in_iff ||
  rewrite map_mapsto_iff || rewrite map_in_iff ||
  rewrite mapi_in_iff)).

(**  * Specifications written using boolean predicates *)

Section BoolSpec.

Definition eqb x y := if E.eq_dec x y then true else false.

Lemma mem_find_b : forall (elt:Set)(m:t elt)(x:key), mem x m = if find x m then true else false. 
Proof.
intros.
generalize (find_mapsto_iff m x)(mem_in_iff m x); unfold In.
destruct (find x m); destruct (mem x m); auto.
intros.
rewrite <- H0; exists e; rewrite H; auto.
intuition.
destruct H0 as (e,H0).
destruct (H e); intuition discriminate.
Qed.

Variable elt elt' elt'' : Set.
Implicit Types m : t elt.
Implicit Types x y z : key.
Implicit Types e : elt.

Lemma mem_b : forall m x y, E.eq x y -> mem x m = mem y m.
Proof. 
intros.
generalize (mem_in_iff m x) (mem_in_iff m y)(In_iff m H).
destruct (mem x m); destruct (mem y m); intuition.
Qed.

Lemma find_o : forall m x y, E.eq x y -> find x m = find y m.
Proof.
intros.
generalize (find_mapsto_iff m x) (find_mapsto_iff m y) (fun e => MapsTo_iff m e H).
destruct (find x m); destruct (find y m); intros.
rewrite <- H0; rewrite H2; rewrite H1; auto.
symmetry; rewrite <- H1; rewrite <- H2; rewrite H0; auto.
rewrite <- H0; rewrite H2; rewrite H1; auto.
auto.
Qed.

Lemma empty_o : forall x, find x (empty elt) = None.
Proof.
intros.
case_eq (find x (empty elt)); intros; auto.
generalize (find_2 H).
rewrite empty_mapsto_iff; intuition.
Qed.

Lemma empty_a : forall x, mem x (empty elt) = false.
Proof.
intros.
case_eq (mem x (empty elt)); intros; auto.
generalize (mem_2 H).
rewrite empty_in_iff; intuition.
Qed.

Lemma add_eq_o : forall m x y e, 
 E.eq x y -> find y (add x e m) = Some e.
Proof.
auto.
Qed.

Lemma add_neq_o : forall m x y e, 
 ~ E.eq x y -> find y (add x e m) = find y m. 
Proof.
intros.
case_eq (find y m); intros; auto.
case_eq (find y (add x e m)); intros; auto.
rewrite <- H0; symmetry.
apply find_1; apply add_3 with x e; auto.
Qed.
Hint Resolve add_neq_o.

Lemma add_o : forall m x y e, 
 find y (add x e m) = if E.eq_dec x y then Some e else find y m.
Proof.
intros; destruct (E.eq_dec x y); auto.
Qed.

Lemma add_eq_b : forall m x y e, 
 E.eq x y -> mem y (add x e m) = true.
Proof.
intros; rewrite mem_find_b; rewrite add_eq_o; auto.
Qed.

Lemma add_neq_b : forall m x y e, 
 ~E.eq x y -> mem y (add x e m) = mem y m.
Proof.
intros; do 2 rewrite mem_find_b; rewrite add_neq_o; auto.
Qed.

Lemma add_b : forall m x y e, 
 mem y (add x e m) = eqb x y || mem y m. 
Proof.
intros; do 2 rewrite mem_find_b; rewrite add_o; unfold eqb.
destruct (E.eq_dec x y); simpl; auto.
Qed.

Lemma remove_eq_o : forall m x y, 
 E.eq x y -> find y (remove x m) = None.
Proof.
intros.
generalize (remove_1 (m:=m) H).
generalize (find_mapsto_iff (remove x m) y).
destruct (find y (remove x m)); auto.
destruct 2.
exists e; rewrite H0; auto.
Qed.
Hint Resolve remove_eq_o.

Lemma remove_neq_o : forall m x y, 
 ~ E.eq x y -> find y (remove x m) = find y m. 
Proof.
intros.
case_eq (find y m); intros; auto.
case_eq (find y (remove x m)); intros; auto.
rewrite <- H0; symmetry.
apply find_1; apply remove_3 with x; auto.
Qed.
Hint Resolve remove_neq_o.

Lemma remove_o : forall m x y, 
 find y (remove x m) = if E.eq_dec x y then None else find y m.
Proof.
intros; destruct (E.eq_dec x y); auto.
Qed.

Lemma remove_eq_b : forall m x y, 
 E.eq x y -> mem y (remove x m) = false.
Proof.
intros; rewrite mem_find_b; rewrite remove_eq_o; auto.
Qed.

Lemma remove_neq_b : forall m x y, 
 ~ E.eq x y -> mem y (remove x m) = mem y m.
Proof.
intros; do 2 rewrite mem_find_b; rewrite remove_neq_o; auto.
Qed.

Lemma remove_b : forall m x y, 
 mem y (remove x m) = negb (eqb x y) && mem y m.
Proof.
intros; do 2 rewrite mem_find_b; rewrite remove_o; unfold eqb.
destruct (E.eq_dec x y); auto.
Qed.

Definition option_map (A:Set)(B:Set)(f:A->B)(o:option A) : option B := 
 match o with 
  | Some a => Some (f a)
  | None => None
 end.

Lemma map_o : forall m x (f:elt->elt'), 
 find x (map f m) = option_map f (find x m). 
Proof.
intros.
generalize (find_mapsto_iff (map f m) x) (find_mapsto_iff m x)
  (fun b => map_mapsto_iff m x b f).
destruct (find x (map f m)); destruct (find x m); simpl; auto; intros.
rewrite <- H; rewrite H1; exists e0; rewrite H0; auto.
destruct (H e) as [_ H2].
rewrite H1 in H2.
destruct H2 as (a,(_,H2)); auto.
rewrite H0 in H2; discriminate.
rewrite <- H; rewrite H1; exists e; rewrite H0; auto.
Qed.

Lemma map_b : forall m x (f:elt->elt'), 
 mem x (map f m) = mem x m.
Proof.
intros; do 2 rewrite mem_find_b; rewrite map_o.
destruct (find x m); simpl; auto.
Qed.

Lemma mapi_b : forall m x (f:key->elt->elt'), 
 mem x (mapi f m) = mem x m.
Proof.
intros.
generalize (mem_in_iff (mapi f m) x) (mem_in_iff m x) (mapi_in_iff m x f).
destruct (mem x (mapi f m)); destruct (mem x m); simpl; auto; intros.
symmetry; rewrite <- H0; rewrite <- H1; rewrite H; auto.
rewrite <- H; rewrite H1; rewrite H0; auto.
Qed.

Lemma mapi_o : forall m x (f:key->elt->elt'), 
 (forall x y e, E.eq x y -> f x e = f y e) -> 
 find x (mapi f m) = option_map (f x) (find x m).
Proof.
intros.
generalize (find_mapsto_iff (mapi f m) x) (find_mapsto_iff m x) 
  (fun b => mapi_mapsto_iff m x b H).
destruct (find x (mapi f m)); destruct (find x m); simpl; auto; intros.
rewrite <- H0; rewrite H2; exists e0; rewrite H1; auto.
destruct (H0 e) as [_ H3].
rewrite H2 in H3.
destruct H3 as (a,(_,H3)); auto.
rewrite H1 in H3; discriminate.
rewrite <- H0; rewrite H2; exists e; rewrite H1; auto.
Qed.

Lemma map2_1bis : forall (m: t elt)(m': t elt') x 
 (f:option elt->option elt'->option elt''), 
 f None None = None -> 
 find x (map2 f m m') = f (find x m) (find x m').       
Proof.
intros.
case_eq (find x m); intros.
rewrite <- H0.
apply map2_1; auto.
left; exists e; auto.
case_eq (find x m'); intros.
rewrite <- H0; rewrite <- H1.
apply map2_1; auto.
right; exists e; auto.
rewrite H.
case_eq (find x (map2 f m m')); intros; auto.
assert (In x (map2 f m m')) by (exists e; auto).
destruct (map2_2 H3) as [(e0,H4)|(e0,H4)].
rewrite (find_1 H4) in H0; discriminate.
rewrite (find_1 H4) in H1; discriminate.
Qed.

Lemma elements_o : forall m x, 
 find x m = findA (eqb x) (elements m).
Proof.
intros.
assert (forall e, find x m = Some e <-> InA (eq_key_elt (elt:=elt)) (x,e) (elements m)).
 intros; rewrite <- find_mapsto_iff; apply elements_mapsto_iff.
assert (NoDupA (eq_key (elt:=elt)) (elements m)). 
 exact (elements_3 m).
generalize (fun e => @findA_NoDupA _ _ _ E.eq_sym E.eq_trans E.eq_dec (elements m) x e H0).
unfold eqb.
destruct (find x m); destruct (findA (fun y : E.t => if E.eq_dec x y then true else false) (elements m)); 
 simpl; auto; intros.
symmetry; rewrite <- H1; rewrite <- H; auto.
symmetry; rewrite <- H1; rewrite <- H; auto.
rewrite H; rewrite H1; auto.
Qed.

Lemma elements_b : forall m x, mem x m = existsb (fun p => eqb x (fst p)) (elements m).
Proof.
intros.
generalize (mem_in_iff m x)(elements_in_iff m x)
 (existsb_exists (fun p => eqb x (fst p)) (elements m)).
destruct (mem x m); destruct (existsb (fun p => eqb x (fst p)) (elements m)); auto; intros.
symmetry; rewrite H1.
destruct H0 as (H0,_).
destruct H0 as (e,He); [ intuition |].
rewrite InA_alt in He.
destruct He as ((y,e'),(Ha1,Ha2)).
compute in Ha1; destruct Ha1; subst e'.
exists (y,e); split; simpl; auto.
unfold eqb; destruct (E.eq_dec x y); intuition.
rewrite <- H; rewrite H0.
destruct H1 as (H1,_).
destruct H1 as ((y,e),(Ha1,Ha2)); [intuition|].
simpl in Ha2.
unfold eqb in *; destruct (E.eq_dec x y); auto; try discriminate.
exists e; rewrite InA_alt.
exists (y,e); intuition.
compute; auto.
Qed.

End BoolSpec.

End Facts.
