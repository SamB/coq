(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

let commands = [
  [(* "Abort"; *)
   "Add Abstract Ring A Aplus Amult Aone Azero Ainv Aeq T.";
   "Add Abstract Semi Ring A Aplus Amult Aone Azero Aeq T.";
   "Add Field";
   "Add LoadPath";
   "Add ML Path";
   "Add Morphism";
   "Add Printing If";
   "Add Printing Let";
   "Add Rec LoadPath";
   "Add Rec ML Path";
   "Add Ring A Aplus Amult Aone Azero Ainv Aeq T [ c1 ... cn ]. ";
   "Add Semi Ring A Aplus Amult Aone Azero Aeq T [ c1 ... cn ].";
   "Add Setoid";
   "Axiom";];
  [(* "Back"; *) ];
  ["Canonical Structure";
   (* "Cd"; *)
   "Chapter";
   (* "Check"; *)
   "Coercion";
   "Coercion Local";
   "CoFixpoint";
   "CoInductive";
   (* "Correctness"; *)];
  ["Declare ML Module";
   "Defined.";
   "Definition";
   "Derive Dependent Inversion";
   "Derive Dependent Inversion_clear";
   "Derive Inversion";
   "Derive Inversion_clear";
   (* "Drop"; *)];
  ["End";
   "End Silent.";
   "Eval"; 
   "Extract Constant";
   "Extract Inductive";
   "Extraction";
   "Extraction Inline";
   "Extraction Language";
   "Extraction Module";
   "Extraction NoInline";];
  ["Fact";
   "Fixpoint";
   "Focus";];
  ["Global Variable";
   "Goal";
   "Grammar";];
  ["Hint";
   "Hint Constructors";
   "Hint Unfold";
   "Hint Rewrite";
   "Hints Extern";
   "Hints Immediate";
   "Hints Resolve";
   "Hints Unfold";
   "Hypothesis";];
  ["Identity Coercion";
   "Implicit Arguments Off.";
   "Implicit Arguments On.";
   "Implicits";
   "Inductive";
   "Infix";
   (* "Inspect"; *)];
  ["Lemma";
   "Load";
   "Load Verbose";
   "Local";
   (*
    "Locate";
   "Locate File";
   "Locate Library"; *)];
  ["Module";
   "Module Type";
   "Mutual Inductive";];
  ["Notation";];
  ["Opaque";];
  ["Parameter";
   (*"Print";
   "Print All";
   "Print Classes";
   "Print Coercion Paths";
   "Print Coercions";
   "Print Extraction Inline";
   "Print Graph";
   "Print Hint";
   "Print HintDb";
   "Print LoadPath";
   "Print ML Modules";
   "Print ML Path";
   "Print Module";
   "Print Module Type";
   "Print Modules";
   "Print Proof";
   "Print Section";
   "Print Table Printing If";
   "Print Table Printing Let";*)
   "Proof.";
   (*"Pwd";*)];
  ["Qed.";
   (* "Quit";*)];
  ["Read Module";
   "Record";
   "Recursive Extraction";
   "Recursive Extraction Module";
   "Remark";
   "Remove LoadPath";
   "Remove Printing If";
   "Remove Printing Let";
   "Require";
   "Require Export";
   (* "Reset"; *)
   "Reset Extraction Inline";
   (* "Reset Initial"; *)
   (* "Restart"; *)
   "Restore State"; 
   (* "Resume"; *)];
  [  "Save.";
     "Scheme";
     (*"Search";
     "Search ... inside ...";
     "Search ... outside ...";
     "SearchAbout";
     "SearchPattern";
     "SearchPattern ... inside ...";
     "SearchPattern ... outside ...";
     "SearchRewrite";
     "SearchRewrite ... inside ...";
     "SearchRewrite ... outside ..."; *)
     "Section";
     "Set Extraction AutoInline";
     "Set Extraction Optimize";
     "Set Hyps_limit";
     "Set Implicit Arguments";
     "Set Printing Coercion";
     "Set Printing Coercions";
     "Set Printing Synth";
     "Set Printing Wildcard";
     "Set Silent.";
     "Set Undo";
     (*"Show";
     "Show Conjectures";
     "Show Implicits";
     "Show Intro";
     "Show Intros";
     "Show Programs";
     "Show Proof";
     "Show Script";
     "Show Tree";*)
     "Structure";
     (* "Suspend"; *)
     "Syntactic Definition";
     "Syntax";];
  ["Tactic Definition";
   "Test Printing If";
   "Test Printing Let";
   "Test Printing Synth";
   "Test Printing Wildcard";
   "Theorem";
   "Time";
   "Transparent";];
  [(* "Undo"; *)
   "Unfocus";
   "Unset Extraction AutoInline";
   "Unset Extraction Optimize";
   "Unset Hyps_limit";
   "Unset Implicit Arguments";
   "Unset Printing Coercion";
   "Unset Printing Coercions";
   "Unset Printing Synth";
   "Unset Printing Wildcard";
   "Unset Silent.";
   "Unset Undo";];
  ["Variable";
   "Variables";];
  ["Write State";];
]

let state_preserving = [
  "Check";
  "Eval";
  "Eval compute in";
  "Extraction";
  "Extraction Library";
  "Extraction Module";
  "Inspect";
  "Locate";
  "Print";
  "Print All.";
  "Print Classes";
  "Print Coercion Paths";
  "Print Coercions";
  "Print Extraction Inline";
  "Print Graph";
  "Print Hint";
  "Print HintDb";
  "Print LoadPath";
  "Print ML Modules";
  "Print ML Path";
  "Print Module";
  "Print Module Type";
  "Print Modules";
  "Print Proof";
  "Print Section";
  "Print Table Printing If";
  "Print Table Printing Let";

  "Pwd.";

  "Recursive Extraction";
  "Recursive Extraction Library";

  "Search";
  "SearchAbout";
  "SearchPattern";
  "SearchRewrite";

  "Show";
  "Show Conjectures";
  "Show Implicits";
  "Show Intro";
  "Show Intros";
  "Show Proof";
  "Show Script";
  "Show Tree";

  "Test Printing If";
  "Test Printing Let";
  "Test Printing Synth";
  "Test Printing Wildcard";
]
