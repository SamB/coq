Require Export NTimesOrder.

Module NMinusPropFunct (Import NAxiomsMod : NAxiomsSig).
Module Export NTimesOrderPropMod := NTimesOrderPropFunct NAxiomsMod.
Open Local Scope NatScope.

Theorem minus_0_r : forall n : N, n - 0 == n.
Proof minus_0_r.

Theorem minus_succ_r : forall n m : N, n - (S m) == P (n - m).
Proof minus_succ_r.

Theorem minus_1_r : forall n : N, n - 1 == P n.
Proof.
intro n; rewrite minus_succ_r; now rewrite minus_0_r.
Qed.

Theorem minus_0_l : forall n : N, 0 - n == 0.
Proof.
induct n.
apply minus_0_r.
intros n IH; rewrite minus_succ_r; rewrite IH. now apply pred_0.
Qed.

Theorem minus_succ : forall n m : N, S n - S m == n - m.
Proof.
intro n; induct m.
rewrite minus_succ_r. do 2 rewrite minus_0_r. now rewrite pred_succ.
intros m IH. rewrite minus_succ_r. rewrite IH. now rewrite minus_succ_r.
Qed.

Theorem minus_diag : forall n : N, n - n == 0.
Proof.
induct n. apply minus_0_r. intros n IH; rewrite minus_succ; now rewrite IH.
Qed.

Theorem minus_gt : forall n m : N, n > m -> n - m ~= 0.
Proof.
intros n m H; elim H using lt_ind_rel; clear n m H.
solve_rel_wd.
intro; rewrite minus_0_r; apply neq_succ_0.
intros; now rewrite minus_succ.
Qed.

Theorem plus_minus_assoc : forall n m p : N, p <= m -> n + (m - p) == (n + m) - p.
Proof.
intros n m p; induct p.
intro; now do 2 rewrite minus_0_r.
intros p IH H. do 2 rewrite minus_succ_r.
rewrite <- IH; [now apply le_succ_le |].
rewrite plus_pred_r. apply minus_gt. now apply <- lt_le_succ.
reflexivity.
Qed.

Theorem minus_succ_l : forall n m : N, n <= m -> S m - n == S (m - n).
Proof.
intros n m H. rewrite <- (plus_1_l m). rewrite <- (plus_1_l (m - n)).
symmetry; now apply plus_minus_assoc.
Qed.

Theorem plus_minus : forall n m : N, (n + m) - m == n.
Proof.
intros n m. rewrite <- plus_minus_assoc. apply le_refl.
rewrite minus_diag; now rewrite plus_0_r.
Qed.

Theorem minus_plus : forall n m : N, n <= m -> (m - n) + n == m.
Proof.
intros n m H. rewrite plus_comm. rewrite plus_minus_assoc; [assumption |].
rewrite plus_comm. apply plus_minus.
Qed.

Theorem plus_minus_eq : forall n m p : N, m + p == n -> n - m == p.
Proof.
intros n m p H. symmetry.
assert (H1 : m + p - m == n - m). now rewrite H.
rewrite plus_comm in H1. now rewrite plus_minus in H1.
Qed.

(* This could be proved by adding m to both sides. Then the proof would
use plus_minus_assoc and le_minus_0, which is proven below. *)
Theorem plus_minus_eq_nz : forall n m p : N, p ~= 0 -> n - m == p -> m + p == n.
Proof.
intros n m p H; double_induct n m.
intros m H1; rewrite minus_0_l in H1. symmetry in H1; false_hyp H1 H.
intro n; rewrite minus_0_r; now rewrite plus_0_l.
intros n m IH H1. rewrite minus_succ in H1. apply IH in H1.
rewrite plus_succ_l; now apply succ_wd.
Qed.

Theorem minus_plus_distr : forall n m p : N, n - (m + p) == (n - m) - p.
Proof.
intros n m; induct p.
rewrite plus_0_r; now rewrite minus_0_r.
intros p IH. rewrite plus_succ_r; do 2 rewrite minus_succ_r. now rewrite IH.
Qed.

Theorem plus_minus_swap : forall n m p : N, p <= n -> n + m - p == n - p + m.
Proof.
intros n m p H.
rewrite (plus_comm n m).
rewrite <- plus_minus_assoc; [assumption |].
now rewrite (plus_comm m (n - p)).
Qed.

(** Minus and order *)

Theorem le_minus_l : forall n m : N, n - m <= n.
Proof.
intro n; induct m.
rewrite minus_0_r; le_equal.
intros m IH. rewrite minus_succ_r.
apply le_trans with (n - m); [apply le_pred_l | assumption].
Qed.

Theorem le_minus_0 : forall n m : N, n <= m <-> n - m == 0.
Proof.
double_induct n m.
intro m; split; intro; [apply minus_0_l | apply le_0_l].
intro m; rewrite minus_0_r; split; intro H;
[false_hyp H nle_succ_0 | false_hyp H neq_succ_0].
intros n m H. rewrite <- succ_le_mono. now rewrite minus_succ.
Qed.

(** Minus and times *)

Theorem times_pred_r : forall n m : N, n * (P m) == n * m - n.
Proof.
intro n; nondep_induct m.
now rewrite pred_0, times_0_r, minus_0_l.
intro m; rewrite pred_succ, times_succ_r, <- plus_minus_assoc.
le_equal.
now rewrite minus_diag, plus_0_r.
Qed.

Theorem times_minus_distr_r : forall n m p : N, (n - m) * p == n * p - m * p.
Proof.
intros n m p; induct n.
now rewrite minus_0_l, times_0_l, minus_0_l.
intros n IH. destruct (le_lt_dec m n) as [H | H].
rewrite minus_succ_l; [assumption |]. do 2 rewrite times_succ_l.
rewrite (plus_comm ((n - m) * p) p), (plus_comm (n * p) p).
rewrite <- (plus_minus_assoc p (n * p) (m * p)); [now apply times_le_mono_r |].
now apply <- plus_cancel_l.
assert (H1 : S n <= m); [now apply -> lt_le_succ |].
setoid_replace (S n - m) with 0 by now apply -> le_minus_0.
setoid_replace ((S n * p) - m * p) with 0 by (apply -> le_minus_0; now apply times_le_mono_r).
apply times_0_l.
Qed.

Theorem times_minus_distr_l : forall n m p : N, p * (n - m) == p * n - p * m.
Proof.
intros n m p; rewrite (times_comm p (n - m)), (times_comm p n), (times_comm p m).
apply times_minus_distr_r.
Qed.

End NMinusPropFunct.


(*
 Local Variables:
 tags-file-name: "~/coq/trunk/theories/Numbers/TAGS"
 End:
*)