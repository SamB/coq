(* The tactic language *)

(* Submitted by Pierre Cr�gut *)
(* Checks substitution of x *)
Tactic Definition f x := Unfold x; Idtac.
 
Goal (plus O O) = O.
f plus.
