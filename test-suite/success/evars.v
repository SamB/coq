(* The "?" of cons and eq should be inferred *)
Variable list:Set -> Set.
Variable cons:(T:Set) T -> (list T) -> (list T).
Check (n:(list nat)) (EX l| (EX x| (n = (cons ? x l)))).

(* Examples provided by Eduardo Gimenez *)

Definition c [A;Q:(nat*A->Prop)->Prop;P] :=
   (Q [p:nat*A]let (i,v) = p in (P i v)).

(* What does this test ? *)
Require PolyList.
Definition list_forall_bool  [A:Set][p:A->bool][l:(list A)] : bool := 
 (fold_right ([a][r]if (p a) then r else false) true l).

(* Checks that solvable ? in the lambda prefix of the definition are harmless*)
Parameter A1,A2,F,B,C : Set.
Parameter f : F -> A1 -> B.
Definition f1 [frm0,a1]: B := (f frm0 a1).

(* Checks that solvable ? in the type part of the definition are harmless *)
Definition f2 : (frm0:?;a1:?)B := [frm0,a1](f frm0 a1).

(* Checks that sorts that are evars are handled correctly (bug 705) *)
Require PolyList.

Fixpoint build [nl : (list nat)] :
 (Cases nl of nil => True | _ => False end) -> unit :=
 <[nl](Cases nl of nil => True | _ => False end) -> unit>Cases nl of
 | nil => [_]tt
 | (cons n rest) =>
   Cases n of
   | O => [_]tt
   | (S m) => [a](build rest (False_ind ? a))
   end
  end.


(* Checks that disjoint contexts are correctly set by restrict_hyp *)
(* Bug de 1999 corrig� en d�c 2004 *)

Check
  let p = [m:nat;f;n:nat]Cases (f m n) of
                         (exist a b) => (exist ? ? a b)
                         end
  in 
  (p:: (x:nat)((y:nat)(n:nat){q:nat | y = (mult q n)}) -> (n:nat){q:nat | x = (mult q n)}).
