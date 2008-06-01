(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i $Id$ i*)

Require Import QArith Qpower.

Open Scope Q_scope.

(** * QSig *)

(** Interface of a rich structure about rational numbers.
    Specifications are written via translation to Q.
*)

Module Type QType.

 Parameter t : Type.

 Parameter to_Q : t -> Q.
 Notation "[ x ]" := (to_Q x).

 Definition eq x y := [x] == [y].

 Parameter of_Q : Q -> t.
 Parameter spec_of_Q: forall x, to_Q (of_Q x) == x.

 Parameter zero : t.
 Parameter one : t.
 Parameter minus_one : t.

 Parameter spec_0: [zero] == 0.
 Parameter spec_1: [one] == 1.
 Parameter spec_m1: [minus_one] == -(1).

 Parameter compare : t -> t -> comparison.

 Parameter spec_compare: forall x y, compare x y = ([x] ?= [y]).

 Definition lt n m := compare n m = Lt.
 Definition le n m := compare n m <> Gt.
 Definition min n m := match compare n m with Gt => m | _ => n end.
 Definition max n m := match compare n m with Lt => m | _ => n end.

 Parameter add  : t -> t -> t.

 Parameter spec_add: forall x y, [add x y] == [x] + [y].

 Parameter sub : t -> t -> t.

 Parameter spec_sub: forall x y, [sub x y] == [x] - [y].

 Parameter opp : t -> t.

 Parameter spec_opp: forall x, [opp x] == - [x].

 Parameter mul : t -> t -> t.

 Parameter spec_mul: forall x y, [mul x y] == [x] * [y].

 Parameter square : t -> t.

 Parameter spec_square: forall x, [square x] == [x] ^ 2.

 Parameter inv : t -> t.

 Parameter spec_inv : forall x, [inv x] == / [x].

 Parameter div : t -> t -> t.

 Parameter spec_div: forall x y, [div x y] == [x] / [y].

 Parameter power_pos : t -> positive -> t.

 Parameter spec_power_pos: forall x n, [power_pos x n] == [x] ^ Zpos n.

End QType.

(* TODO: add norm function and variants, add eq_bool, what about Qc ? *)