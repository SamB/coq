(* Cases with let-in in constructors types *)

Inductive t : Set :=
    k : let x := t in x -> x.

Print t_rect.

(* Do not contract nested patterns with dependent return type *)
(* see bug #1699 *)

Require Import Arith.

Definition proj (x y:nat) (P:nat -> Type) (def:P x) (prf:P y) : P y :=
  match eq_nat_dec x y return P y with
  | left eqprf => 
    match eqprf in (_ = z) return (P z) with
    | refl_equal => def
    end
  | _ => prf
 end.

Print proj.
