(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ *)

(*i*)
open Pp
open Names
(*i*)

(*s Pretty-print. *)

(* Dealing with precedences *)

type precedence = int

type parenRelation = L | E | Any | Prec of precedence

type tolerability = precedence * parenRelation

type ppbox =
  | PpHB of int
  | PpHOVB of int
  | PpHVB of int
  | PpVB of int
  | PpTB

type ppcut =
  | PpBrk of int * int
  | PpTbrk of int * int
  | PpTab
  | PpFnl

val ppcmd_of_box : ppbox -> std_ppcmds -> std_ppcmds

val ppcmd_of_cut : ppcut -> std_ppcmds

type unparsing = 
  | UnpMetaVar of identifier * tolerability
  | UnpTerminal of string
  | UnpBox of ppbox * unparsing list
  | UnpCut of ppcut
