(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

(** Bit vectors. Contribution by Jean Duprat (ENS Lyon). *)

Require Export Bool.
Require Export Sumbool.
Require Arith.

V7only [Import nat_scope.].
Open Local Scope nat_scope.

(*  
On s'inspire de PolyList pour fabriquer les vecteurs de bits.
La dimension du vecteur est un param�tre trop important pour
se contenter de la fonction "length".
La premi�re id�e est de faire un record avec la liste et la longueur.
Malheureusement, cette verification a posteriori amene a faire
de nombreux lemmes pour gerer les longueurs.
La seconde id�e est de faire un type d�pendant dans lequel la
longueur est un param�tre de construction. Cela complique un
peu les inductions structurelles, la solution qui a ma pr�f�rence
est alors d'utiliser un terme de preuve comme d�finition.

(En effet une d�finition comme :
Fixpoint Vunaire [n:nat; v:(vector n)]: (vector n) :=
Cases v of
	| Vnil => Vnil
	| (Vcons a p v') => (Vcons (f a) p (Vunaire p v'))
end.
provoque ce message d'erreur :
Coq < Error: Inference of annotation not yet implemented in this case).


	Inductive list [A : Set]  : Set :=
		nil : (list A) | cons : A->(list A)->(list A).
	head = [A:Set; l:(list A)] Cases l of
			| nil => Error
 			| (cons x _) => (Value x)
 			end
     		: (A:Set)(list A)->(option A).
	tail = [A:Set; l:(list A)]Cases l of
                   			| nil => (nil A)
                   			| (cons _ m) => m
                   			end
     		: (A:Set)(list A)->(list A).
	length = [A:Set] Fix length {length [l:(list A)] : nat :=
      		Cases l of
       			| nil => O
      			| (cons _ m) => (S (length m))
      		end}
     		: (A:Set)(list A)->nat.
	map = [A,B:Set; f:(A->B)] Fix map {map [l:(list A)] : (list B) :=
		Cases l of
			| nil => (nil B)
			| (cons a t) => (cons (f a) (map t))
		end}
		: (A,B:Set)(A->B)->(list A)->(list B)
*)

Section VECTORS.

(* 
Un vecteur est une liste de taille n d'�l�ments d'un ensemble A.
Si la taille est non nulle, on peut extraire la premi�re composante et 
le reste du vecteur, la derni�re composante ou rajouter ou enlever 
une composante (carry) ou repeter la derni�re composante en fin de vecteur.
On peut aussi tronquer le vecteur de ses p derni�res composantes ou
au contraire l'�tendre (concat�ner) d'un vecteur de longueur p.
Une fonction unaire sur A g�n�re une fonction des vecteurs de taille n
dans les vecteurs de taille n en appliquant f terme � terme.
Une fonction binaire sur A g�n�re une fonction des couple de vecteurs 
de taille n dans les vecteurs de taille n en appliquant f terme � terme.
*)

Variable A : Set.

Inductive vector: nat -> Set :=
	| Vnil : (vector O)
	| Vcons  : (a:A) (n:nat) (vector n) -> (vector (S n)).

Definition Vhead : (n:nat) (vector (S n)) -> A.
Proof.
	Intros; Inversion H; Exact a.
Defined.

Definition Vtail : (n:nat) (vector (S n)) -> (vector n).
Proof.
	Intros; Inversion H; Exact H1.
Defined.

Definition Vlast : (n:nat) (vector (S n)) -> A.
Proof.
	Induction n; Intros.
	Inversion H.
	Exact a.

	Inversion H0.
	Exact (H H2).
Defined.

Definition Vconst : (a:A) (n:nat) (vector n).
Proof.
	Induction n; Intros.
	Exact Vnil.

	Exact (Vcons a n0 H).
Defined.

Lemma Vshiftout : (n:nat) (vector (S n)) -> (vector n).
Proof.
	Induction n; Intros.
	Exact Vnil.

	Inversion H0.
	Exact (Vcons a n0 (H H2)).
Defined.

Lemma Vshiftin : (n:nat) A -> (vector n) -> (vector (S n)).
Proof.
	Induction n; Intros.
	Exact (Vcons H O H0).

	Inversion H1.
	Exact (Vcons a (S n0) (H H0 H3)).
Defined.

Lemma Vshiftrepeat : (n:nat) (vector (S n)) -> (vector (S (S n))).
Proof.
	Induction n; Intros.
	Inversion H.
	Exact (Vcons a (1) H).

	Inversion H0.
	Exact (Vcons a (S (S n0)) (H H2)).
Defined.

(*
Lemma S_minus_S : (n,p:nat) (gt n (S p)) -> (S (minus n (S p)))=(minus n p).
Proof.
  Intros.
Save.
*)

Lemma Vtrunc : (n,p:nat) (gt n p) ->  (vector n) -> (vector (minus n p)).
Proof.
	Induction p; Intros.
	Rewrite <- minus_n_O.
	Exact H0.

	Apply (Vshiftout (minus n (S n0))).

Rewrite minus_Sn_m.
Apply H.
Auto with *.
Exact H1.
Auto with *.
Defined.

Lemma Vextend : (n,p:nat) (vector n) ->  (vector p) -> (vector (plus n p)).
Proof.
	Induction n; Intros.
	Simpl; Exact H0.

	Inversion H0.
	Simpl; Exact (Vcons a (plus n0 p) (H p H3 H1)).
Defined.

Variable f : A -> A.

Lemma Vunary : (n:nat)(vector n)->(vector n).
Proof.
	Induction n; Intros.
	Exact Vnil.

	Inversion H0.
	Exact (Vcons (f a) n0 (H H2)).
Defined.

Variable g : A -> A -> A.

Lemma Vbinary : (n:nat)(vector n)->(vector n)->(vector n).
Proof.
	Induction n; Intros.
	Exact Vnil.

	Inversion H0; Inversion H1.
	Exact (Vcons (g a a0) n0 (H H3 H5)).
Defined.

End VECTORS.

Section BOOLEAN_VECTORS.

(* 
Un vecteur de bits est un vecteur sur l'ensemble des bool�ens de longueur fixe. 
ATTENTION : le stockage s'effectue poids FAIBLE en t�te.
On en extrait le bit  de poids faible (head) et la fin du vecteur (tail).
On calcule la n�gation d'un vecteur, le et, le ou et le xor bit � bit de 2 vecteurs.
On calcule les d�calages d'une position vers la gauche (vers les poids forts, on
utilise donc Vshiftout, vers la droite (vers les poids faibles, on utilise Vshiftin) en 
ins�rant un bit 'carry' (logique) ou en r�p�tant le bit de poids fort (arithm�tique).
ATTENTION : Tous les d�calages prennent la taille moins un comme param�tre
(ils ne travaillent que sur des vecteurs au moins de longueur un).
*)

Definition Bvector := (vector bool).

Definition Bnil := (Vnil bool).

Definition Bcons := (Vcons bool).

Definition Bvect_true := (Vconst bool true).

Definition Bvect_false := (Vconst bool false).

Definition Blow := (Vhead bool).

Definition Bhigh := (Vtail bool).

Definition Bsign := (Vlast bool).

Definition Bneg := (Vunary bool negb).

Definition BVand := (Vbinary bool andb).

Definition BVor := (Vbinary bool orb).

Definition BVxor := (Vbinary bool xorb).

Definition BshiftL := [n:nat; bv : (Bvector (S n)); carry:bool] 
	(Bcons carry n (Vshiftout bool n bv)).

Definition BshiftRl := [n:nat; bv : (Bvector (S n)); carry:bool] 
	(Bhigh (S n) (Vshiftin bool (S n) carry bv)).

Definition BshiftRa := [n:nat; bv : (Bvector (S n))] 
	(Bhigh (S n) (Vshiftrepeat bool n bv)).

Fixpoint BshiftL_iter [n:nat; bv:(Bvector (S n)); p:nat]:(Bvector (S n)) :=
Cases p of
	| O => bv
	| (S p') => (BshiftL n (BshiftL_iter n bv p') false)
end.

Fixpoint BshiftRl_iter [n:nat; bv:(Bvector (S n)); p:nat]:(Bvector (S n)) :=
Cases p of
	| O => bv
	| (S p') => (BshiftRl n (BshiftRl_iter n bv p') false)
end.

Fixpoint BshiftRa_iter [n:nat; bv:(Bvector (S n)); p:nat]:(Bvector (S n)) :=
Cases p of
	| O => bv
	| (S p') => (BshiftRa n (BshiftRa_iter n bv p'))
end.

End BOOLEAN_VECTORS.

