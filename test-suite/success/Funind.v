
Definition iszero [n:nat] : bool := Cases n of
                                    | O => true
                                    | _ => false
                                    end.

Functional Scheme iszer_ind := Induction for iszero.
 
Lemma toto : (n:nat) n = 0 -> (iszero n) = true.
Intros x eg.
Functional Induction iszero x; Simpl.
Trivial.
Subst x.
Inversion H_eq_.
Qed.

(* We can even reuse the proof as a scheme: *)

Functional Scheme toto_ind := Induction for iszero.




 
Definition ftest [n, m:nat] : nat :=
  Cases n of
  | O => Cases m of
         | O => 0
         | _ => 1
         end
  | (S p) => 0
  end.

Functional Scheme ftest_ind := Induction for ftest. 

Lemma test1 : (n,m:nat) (le (ftest n m) 2).
Intros n m.
Functional Induction ftest n m;Auto.
Save.


Lemma test11 : (m:nat) (le (ftest 0 m) 2).
Intros m.
Functional Induction ftest 0 m.
Auto. 
Auto. 
Qed.


Definition lamfix :=
[m:nat ]
(Fix trivfun {trivfun [n:nat] : nat := Cases n of
                              | O => m
                              | (S p) => (trivfun p)
                              end}).

(* Parameter v1 v2 : nat. *)

Lemma lamfix_lem : (v1,v2:nat) (lamfix v1 v2) = v1.
Intros v1 v2.
Functional Induction lamfix v1 v2.
Trivial.
Assumption.
Defined.



(* polymorphic function *)
Require PolyList.

Functional Scheme app_ind := Induction for app.

Lemma appnil : (A:Set)(l,l':(list A)) l'=(nil A) ->  l = (app l l').
Intros A l l'.
Functional Induction app A l l';Intuition.
Rewrite <- H1;Trivial.
Save.





Require Export Arith.


Fixpoint trivfun [n:nat] : nat :=
  Cases n of
  | O => 0
  | (S m) => (trivfun m)
  end.


(* essaie de parametre variables non locaux:*) 

Parameter varessai : nat.

Lemma first_try : (trivfun varessai) = 0.
Functional Induction trivfun varessai.
Trivial.
Simpl.
Assumption.
Defined.
 

Functional Scheme triv_ind := Induction for trivfun.

Lemma bisrepetita : (n':nat) (trivfun n') = 0.
Intros n'.
Functional Induction trivfun n'.
Trivial.
Simpl .
Assumption.
Qed.







Fixpoint iseven [n:nat] : bool :=
  Cases n of
  | O => true
  | (S (S m)) => (iseven m)
  | _ => false
  end.
 
Fixpoint funex [n:nat] : nat :=
  Cases (iseven n) of
  | true => n
  | false => Cases n of
             | O => 0
             | (S r) => (funex r)
             end
  end.
 
Fixpoint nat_equal_bool [n:nat]  : nat -> bool :=
[m:nat]
  Cases n of
  | O => Cases m of
         | O => true
         | _ => false
         end
  | (S p) => Cases m of
           | O => false
           | (S q) => (nat_equal_bool p q)
           end
  end.


Require Export Div2.
 
Lemma div2_inf : (n:nat) (le (div2 n) n).
Intros n.
Functional Induction div2 n.
Auto.
Auto.

Apply le_S.
Apply le_n_S.
Exact H.
Qed.

(* reuse this lemma as a scheme:*)

Functional Scheme div2_ind := Induction for div2_inf.

Fixpoint nested_lam [n:nat] : nat -> nat :=
  Cases n of
  | O => [m:nat ] 0
  | (S n') => [m:nat ] (plus m (nested_lam n' m))
  end.

Functional Scheme nested_lam_ind := Induction for nested_lam.

Lemma nest : (n, m:nat) (nested_lam n m) = (mult n m).
Intros n m.
Functional Induction nested_lam n m; Auto.
Qed.

Lemma nest2 : (n, m:nat) (nested_lam n m) = (mult n m).
Intros n m. Pattern n m . 
Apply nested_lam_ind; Simpl ; Intros; Auto.
Qed.

 
Fixpoint essai [x : nat] : nat * nat ->  nat :=
 [p : nat * nat]  ( Case p of [n, m : ?]  Cases n of
                                            O => O
                                           | (S q) =>
                                               Cases x of
                                                 O => (S O)
                                                | (S r) => (S (essai r (q, m)))
                                               end
                                          end end ).
 
Lemma essai_essai:
 (x : nat)
 (p : nat * nat)  ( Case p of [n, m : ?] (lt O n) ->  (lt O (essai x p)) end ).
Intros x p.
(Functional Induction essai x p); Intros.
Inversion H.
Simpl; Try Abstract ( Auto with arith ).
Simpl; Try Abstract ( Auto with arith ).
Qed.

 
Fixpoint plus_x_not_five'' [n : nat] : nat ->  nat :=
 [m : nat]  let x = (nat_equal_bool m (S (S (S (S (S O)))))) in
              let y = O in
                Cases n of
                  O => y
                 | (S q) =>
                     let recapp = (plus_x_not_five'' q m) in
                       Cases x of true => (S recapp) | false => (S recapp) end
                end.
 
Lemma notplusfive'':
 (x, y : nat) y = (S (S (S (S (S O))))) ->  (plus_x_not_five'' x y) = x.
Intros a b.
Unfold plus_x_not_five''.
(Functional Induction plus_x_not_five'' a b); Intros hyp; Simpl; Auto.
Qed.
 
Lemma iseq_eq: (n, m : nat) n = m ->  (nat_equal_bool n m) = true.
Intros n m.
Unfold nat_equal_bool.
(Functional Induction nat_equal_bool n m); Simpl; Intros hyp; Auto.
Inversion hyp.
Inversion hyp.
Qed.
 
Lemma iseq_eq': (n, m : nat) (nat_equal_bool n m) = true ->  n = m.
Intros n m.
Unfold nat_equal_bool.
(Functional Induction nat_equal_bool n m); Simpl; Intros eg; Auto.
Inversion eg.
Inversion eg.
Qed.
 
 
Inductive istrue : bool ->  Prop :=
  istrue0: (istrue true) .
 
Lemma inf_x_plusxy': (x, y : nat)  (le x (plus x y)).
Intros n m.
(Functional Induction plus n m); Intros.
Auto with arith.
Auto with arith.
Qed.

 
Lemma inf_x_plusxy'': (x : nat)  (le x (plus x O)).
Intros n.
Unfold plus.
(Functional Induction plus n O); Intros.
Auto with arith.
Apply le_n_S.
Assumption.
Qed.
 
Lemma inf_x_plusxy''': (x : nat)  (le x (plus O x)).
Intros n.
(Functional Induction plus O n); Intros;Auto with arith.
Qed.

Fixpoint mod2 [n : nat] : nat :=
 Cases n of   O => O
             | (S (S m)) => (S (mod2 m))
             | _ => O end.
 
Lemma princ_mod2: (n : nat)  (le (mod2 n) n).
Intros n.
(Functional Induction mod2 n); Simpl; Auto with arith.
Qed.
 
Definition isfour : nat ->  bool :=
   [n : nat]  Cases n of (S (S (S (S O)))) => true | _ => false end.
 
Definition isononeorfour : nat ->  bool :=
   [n : nat]  Cases n of   (S O) => true
                          | (S (S (S (S O)))) => true
                          | _ => false end.
 
Lemma toto'': (n : nat) (istrue (isfour n)) ->  (istrue (isononeorfour n)).
Intros n.
(Functional Induction isononeorfour n); Intros istr; Simpl; Inversion istr.
Apply istrue0.
Qed.
 
Lemma toto': (n, m : nat) n = (S (S (S (S O)))) ->  (istrue (isononeorfour n)).
Intros n.
(Functional Induction isononeorfour n); Intros m istr; Inversion istr.
Apply istrue0.
Qed.
 
Definition ftest4 : nat -> nat ->  nat :=
   [n, m : nat]  Cases n of
                   O =>
                     Cases m of O => O | (S q) => (S O) end
                  | (S p) =>
                      Cases m of O => O | (S r) => (S O) end
                 end.
 
Lemma test4: (n, m : nat)  (le (ftest n m) (S (S O))).
Intros n m.
(Functional Induction ftest n m); Auto with arith.
Qed.
 
Lemma test4': (n, m : nat)  (le (ftest4 (S n) m) (S (S O))).
Intros n m.
(Functional Induction ftest4 (S n) m).
Auto with arith.
Auto with arith.
Qed.
 
Definition ftest44 : nat * nat -> nat -> nat ->  nat :=
   [x : nat * nat]
   [n, m : nat]
    ( Case x of [p, q : ?]  Cases n of
                              O =>
                                Cases m of O => O | (S q) => (S O) end
                             | (S p) =>
                                 Cases m of O => O | (S r) => (S O) end
                            end end ).
 
Lemma test44:
 (pq : nat * nat) (n, m, o, r, s : nat)  (le (ftest44 pq n (S m)) (S (S O))).
Intros pq n m o r s.
(Functional Induction ftest44 pq n (S m)).
Auto with arith.
Auto with arith.
Auto with arith.
Auto with arith.
Qed.
 
Fixpoint ftest2 [n : nat] : nat ->  nat :=
 [m : nat]  Cases n of
              O =>
                Cases m of O => O | (S q) => O end
             | (S p) => (ftest2 p m)
            end.
 
Lemma test2: (n, m : nat)  (le (ftest2 n m) (S (S O))).
Intros n m.
(Functional Induction ftest2 n m) ; Simpl; Intros; Auto.
Qed.
 
Fixpoint ftest3 [n : nat] : nat ->  nat :=
 [m : nat]  Cases n of
              O => O
             | (S p) =>
                 Cases m of O => (ftest3 p O) | (S r) => O end
            end.
 
Lemma test3: (n, m : nat)  (le (ftest3 n m) (S (S O))).
Intros n m.
(Functional Induction ftest3 n m).
Intros.
Auto.
Intros.
Auto.
Intros.
Simpl.
Auto.
Qed.
 
Fixpoint ftest5 [n : nat] : nat ->  nat :=
 [m : nat]  Cases n of
              O => O
             | (S p) =>
                 Cases m of O => (ftest5 p O) | (S r) => (ftest5 p r) end
            end.
 
Lemma test5: (n, m : nat)  (le (ftest5 n m) (S (S O))).
Intros n m.
(Functional Induction ftest5 n m).
Intros.
Auto.
Intros.
Auto.
Intros.
Simpl.
Auto.
Qed.
 
Definition ftest7 : (n : nat)  nat :=
   [n : nat]  Cases (ftest5 n O) of O => O | (S r) => O end.
 
Lemma essai7:
 (Hrec : (n : nat) (ftest5 n O) = O ->  (le (ftest7 n) (S (S O))))
 (Hrec0 : (n, r : nat) (ftest5 n O) = (S r) ->  (le (ftest7 n) (S (S O))))
 (n : nat)  (le (ftest7 n) (S (S O))).
Intros hyp1 hyp2 n.
Unfold ftest7.
(Functional Induction ftest7 n); Auto.
Qed.
 
Fixpoint ftest6 [n : nat] : nat ->  nat :=
 [m : nat]
  Cases n of
    O => O
   | (S p) =>
       Cases (ftest5 p O) of O => (ftest6 p O) | (S r) => (ftest6 p r) end
  end.

 
Lemma princ6:
 ((n, m : nat) n = O ->  (le (ftest6 O m) (S (S O)))) ->
 ((n, m, p : nat)
  (le (ftest6 p O) (S (S O))) ->
  (ftest5 p O) = O -> n = (S p) ->  (le (ftest6 (S p) m) (S (S O)))) ->
 ((n, m, p, r : nat)
  (le (ftest6 p r) (S (S O))) ->
  (ftest5 p O) = (S r) -> n = (S p) ->  (le (ftest6 (S p) m) (S (S O)))) ->
 (x, y : nat)  (le (ftest6 x y) (S (S O))).
Intros hyp1 hyp2 hyp3 n m.
Generalize hyp1 hyp2 hyp3.
Clear hyp1 hyp2 hyp3.
(Functional Induction ftest6 n m);Auto.
Qed.
 
Lemma essai6: (n, m : nat)  (le (ftest6 n m) (S (S O))).
Intros n m.
Unfold ftest6.
(Functional Induction ftest6 n m); Simpl; Auto.
Qed.













