
(* $Id$ *)

(* Some programs and results about lists following CAML Manual *)

Require Export PolyList.
Implicit Arguments On.
Chapter Lists.

Variable  A : Set.

(*********************)
(* The null function *)
(*********************)

Definition Isnil : (list A) -> Prop := [l:(list A)](nil A)=l.

Lemma Isnil_nil : (Isnil (nil A)).
Red; Auto.
Qed.
Hints Resolve Isnil_nil.

Lemma not_Isnil_cons : (a:A)(l:(list A))~(Isnil (cons a l)).
Unfold Isnil.
Intros; Discriminate.
Qed.

Hints Resolve Isnil_nil not_Isnil_cons.

Lemma Isnil_dec : (l:(list A)){(Isnil l)}+{~(Isnil l)}.
Induction l;Auto.
(*
Realizer [l:(list A)]Cases l of
  | nil => true
  | _ => false
  end.
Program_all.
*)
Qed.

(***********************)
(* The Uncons function *)
(***********************)

Lemma Uncons : (l:(list A)){a : A & { m: (list A) | (cons a m)=l}}+{Isnil l}.
Induction l.
Auto.
Intros a m; Intros; Left; Exists a; Exists m; Reflexivity.
(*
Realizer [l:(list A)]<(Exc A*(list A))>Cases l of 
  | nil => Error
  | (cons a m) => (Value (a,m))
  end.
Program_all.
*)
Qed.

(********************************)
(* The head function            *)
(********************************)

Lemma Hd : (l:(list A)){a : A | (EX m:(list A) |(cons a m)=l)}+{Isnil l}.
Induction l.
Auto.
Intros a m; Intros; Left; Exists a; Exists m; Reflexivity.
(*
Realizer [l:(list A)]<(Exc A)>Cases l of 
  | nil => Error
  | (cons a m) => (Value a)
  end.
Program_all.
Exists m; Reflexivity.
*)
Qed.

Lemma Tl : (l:(list A)){m:(list A)| (EX a:A |(cons a m)=l)
                         \/ ((Isnil l) /\ (Isnil m)) }.
Induction l.
Exists (nil A); Auto.
Intros a m; Intros; Exists m; Left; Exists a; Reflexivity.
(*
Realizer [l:(list A)]Cases l of 
  | nil => (nil A)
  | (cons a m) => m
  end.
Program_all.
  Left; Exists a; Auto.
*)
Qed.

(****************************************)
(* Length of lists                      *)
(****************************************)

(* length is defined in PolyList *)
Fixpoint Length_l [l:(list A)] : nat -> nat 
  :=  [n:nat] Cases l of
                  nil => n
              | (cons _ m) => (Length_l m (S n))
	     end.

(* A tail recursive version *)
Lemma Length_l_pf : (l:(list A))(n:nat){m:nat|(plus n (length l))=m}.
Intros l n; Exists (Length_l l n).
Generalize n.
Induction l.
Auto.
Intro n0. Simpl. Rewrite <- (Hrecl (S n0)).
Simpl. Auto.
(*
Realizer Length_l.
Program_all.
Simpl; Auto.
Elim e; Simpl; Auto.
*)
Qed.

Lemma Length : (l:(list A)){m:nat|(length l)=m}.
Intro l. Apply (Length_l_pf l O).
(*
Realizer [l:(list A)](Length_l_pf l O).
Program_all.
*)
Qed.

(*******************************)
(* Members of lists            *)
(*******************************)
Inductive In_spec [a:A] : (list A) -> Prop := 
   | in_hd : (l:(list A))(In_spec a (cons a l))
   | in_tl : (l:(list A))(b:A)(In a l)->(In_spec a (cons b l)).
Hints Resolve in_hd in_tl.
Hints Unfold  In.
Hints Resolve in_cons.

Theorem In_In_spec : (a:A)(l:(list A))(In a l) <-> (In_spec a l).
Split.
Elim l; [ Intros; Contradiction 
      	| Intros; Elim H0; 
	  [ Intros; Rewrite H1; Auto
	  | Auto ]].
Intros; Elim H; Auto.
Qed.

Inductive AllS [P:A->Prop] : (list A) -> Prop 
   := allS_nil : (AllS P (nil A))
   | allS_cons : (a:A)(l:(list A))(P a)->(AllS P l)->(AllS P (cons a l)).
Hints Resolve allS_nil allS_cons.

Hypothesis eqA_dec : (a,b:A){a=b}+{~a=b}.

Fixpoint mem [a:A; l:(list A)] : bool :=
  Cases l of
    nil => false
  | (cons b m) => if (eqA_dec a b) then [H]true else [H](mem a m)
  end.

Hints Unfold  In.
Lemma Mem : (a:A)(l:(list A)){(In a l)}+{(AllS [b:A]~b=a l)}.
Intros a l.
Induction l.
Auto.
Elim (eqA_dec a a0).
Auto.
Simpl. Elim Hrecl; Auto.
(*
Realizer mem.
Program_all.
*)
Qed.

(**********************************)
(* Index of elements              *)
(**********************************)

Require Le.
Require Lt.

Inductive nth_spec : (list A)->nat->A->Prop :=
  nth_spec_O : (a:A)(l:(list A))(nth_spec (cons a l) (S O) a)
| nth_spec_S : (n:nat)(a,b:A)(l:(list A))
           (nth_spec l n a)->(nth_spec (cons b l) (S n) a).
Hints Resolve nth_spec_O nth_spec_S.

Inductive fst_nth_spec : (list A)->nat->A->Prop :=
  fst_nth_O : (a:A)(l:(list A))(fst_nth_spec (cons a l) (S O) a)
| fst_nth_S : (n:nat)(a,b:A)(l:(list A))(~a=b)->
           (fst_nth_spec l n a)->(fst_nth_spec (cons b l) (S n) a).
Hints Resolve fst_nth_O fst_nth_S.

Lemma fst_nth_nth : (l:(list A))(n:nat)(a:A)(fst_nth_spec l n a)->(nth_spec l n a).
Induction 1; Auto.
Qed.
Hints Immediate fst_nth_nth.

Lemma nth_lt_O : (l:(list A))(n:nat)(a:A)(nth_spec l n a)->(lt O n).
Induction 1; Auto.
Qed.

Lemma nth_le_length : (l:(list A))(n:nat)(a:A)(nth_spec l n a)->(le n (length l)).
  Induction 1; Simpl; Auto with arith.
Qed.

Fixpoint Nth_func [l:(list A)] : nat -> (Exc A) 
  := [n:nat] Cases  l  n  of 
               (cons a _)  (S O)       => (value A a) 
             | (cons _ l') (S (S p)) => (Nth_func l' (S p))
             |  _ _      => Error
            end.

Lemma Nth : (l:(list A))(n:nat)
            {a:A|(nth_spec l n a)}+{(n=O)\/(lt (length l) n)}.
Intros l n. Induction l; Induction n.
Auto.
Auto with arith.
Auto with arith.
Elim Hrecl.
...
(*
Realizer Nth_func.
Program_all.
Simpl; Elim n; Auto with arith.
(Elim o; Intro); [Absurd ((S p)=O); Auto with arith | Auto with arith].
*)
Save.

Lemma Item : (l:(list A))(n:nat){a:A|(nth_spec l (S n) a)}+{(le (length l) n)}.
Realizer [l:(list A)][n:nat](Nth l (S n)).
Program_all.
Elim o; Intro; [Absurd ((S n)=O); Auto with arith | Auto with arith].
Save.

Require Minus.
Require DecBool.

Fixpoint index_p [a:A;l:(list A)] : nat -> (Exc nat) := 
   Cases l of nil => [p]Error
     | (cons b m) => [p](ifdec (eqA_dec a b) (Value p) (index_p a m (S p)))
   end.

Lemma Index_p : (a:A)(l:(list A))(p:nat)
     {n:nat|(fst_nth_spec l (minus (S n) p) a)}+{(AllS [b:A]~a=b l)}.
Realizer index_p.
Program_all.
Elim e; Elim minus_Sn_m; Trivial; Elim minus_n_n; Auto with arith.
Elim minus_Sn_m; Auto with arith.
Apply lt_le_weak; Apply lt_O_minus_lt; Apply nth_lt_O with m a; Auto with arith.
Save.

Lemma Index : (a:A)(l:(list A))
     {n:nat|(fst_nth_spec l n a)}+{(AllS [b:A]~a=b l)}.
Realizer [a:A][l:(list A)](Index_p a l (S O)).
Program_all.
Rewrite (minus_n_O n0); Auto with arith.
Save.

Section Find_sec.
Variable R,P : A -> Prop.

Inductive InR : (list A) -> Prop 
   := inR_hd : (a:A)(l:(list A))(R a)->(InR (cons a l))
   | inR_tl : (a:A)(l:(list A))(InR l)->(InR (cons a l)).
Hints Resolve inR_hd inR_tl.

Definition InR_inv := 
       [l:(list A)]Cases l of 
                   nil => False 
                | (cons b m) => (R b)\/(InR m) 
               end.

Lemma InR_INV : (l:(list A))(InR l)->(InR_inv l).
Induction 1; Simpl; Auto.
Save.

Lemma InR_cons_inv : (a:A)(l:(list A))(InR (cons a l))->((R a)\/(InR l)).
Intros a l H; Exact (InR_INV H).
Save.

Lemma InR_or_app : (l,m:(list A))((InR l)\/(InR m))->(InR (app l m)).
Induction 1.
Induction 1; Simpl; Auto.
Intro; Elim l; Simpl; Auto.
Save.

Lemma InR_app_or : (l,m:(list A))(InR (app l m))->((InR l)\/(InR m)).
Intros l m; Elim l; Simpl; Auto.
Intros b l' Hrec IAc; Elim (InR_cons_inv IAc);Auto.
Intros; Elim Hrec; Auto.
Save.

Hypothesis RS_dec : (a:A){(R a)}+{(P a)}.

Fixpoint find [l:(list A)] : (Exc A) := 
	Cases l of nil => Error
                | (cons a m) => (ifdec (RS_dec a) (Value a) (find m))
        end.

Lemma Find : (l:(list A)){a:A | (In a l) & (R a)}+{(AllS P l)}.
Realizer find.
Program_all.
Save.

Variable B : Set.
Variable T : A -> B -> Prop.

Variable TS_dec : (a:A){c:B| (T a c)}+{(P a)}.

Fixpoint try_find [l:(list A)] : (Exc B) :=
   Cases l of
     nil => Error
   | (cons a l1) =>
	   Cases (TS_dec a) of
	     (inleft (exist c _)) => (Value c)
	   | (inright _) => (try_find l1)
	   end
   end.

Lemma Try_find : (l:(list A)){c:B|(EX a:A |(In a l) & (T a c))}+{(AllS P l)}.
Realizer try_find.
Program_all.
Exists a; Auto.
Elim e; Intros a1 H1 H2.
Exists a1; Auto.
Save.

End Find_sec.

Section Assoc_sec.

Variable B : Set.
Fixpoint assoc [a:A;l:(list A*B)] : (Exc B) :=
    Cases l of        nil => Error
        | (cons (a',b) m) => (ifdec (eqA_dec a a') (Value b) (assoc a m))
    end.

Inductive AllS_assoc [P:A -> Prop]: (list A*B) -> Prop := 
      allS_assoc_nil : (AllS_assoc P (nil A*B))
    | allS_assoc_cons : (a:A)(b:B)(l:(list A*B))
        (P a)->(AllS_assoc P l)->(AllS_assoc P (cons (a,b) l)).

Hints Resolve allS_assoc_nil allS_assoc_cons.

Lemma Assoc : (a:A)(l:(list A*B))(B+{(AllS_assoc [a':A]~(a=a') l)}).
Realizer assoc.
Program_all.
Save.

End Assoc_sec.

End Lists.

Hints Resolve Isnil_nil not_Isnil_cons in_hd in_tl in_cons allS_nil allS_cons 
 : datatypes.
Hints Immediate fst_nth_nth : datatypes.
