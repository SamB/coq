(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)
(******************************************************************************)
(*                                                                            *)
(*                               PROJECT HELM                                 *)
(*                                                                            *)
(*                     A module to print Coq objects in XML                   *)
(*                                                                            *)
(*                Claudio Sacerdoti Coen <sacerdot@cs.unibo.it>               *)
(*                                 06/12/2000                                 *)
(*                                                                            *)
(* This module adds to the vernacular interpreter the functions that fullfill *)
(* the new commands defined in Xml.v                                          *)
(*                                                                            *)
(******************************************************************************)
(*i camlp4deps: "parsing/grammar.cma" i*)

(* $Id$ *)

open Util;;
open Vernacinterp;;

open Extend;;
open Genarg;;
open Pp;;
open Pcoq;;

(* File name *)

VERNAC ARGUMENT EXTEND filename
| [ "File" string(fn) ] -> [ Some fn ]
| [ ] -> [ None ]
END

(* Disk name *)

VERNAC ARGUMENT EXTEND diskname
| [ "Disk" string(fn) ] -> [ Some fn ]
| [ ] -> [ None ]
END

VERNAC COMMAND EXTEND Xml
| [ "Print" "XML" filename(fn) global(id) ] -> [ Xmlcommand.print id fn ]

| [ "Show" "XML" filename(fn) "Proof" ] -> [ Xmlcommand.show fn ]

(*
| [ "Print" "XML" "All" ] -> [ Xmlcommand.printAll () ]

| [ "Print" "XML" "Module" diskname(dn) global(id) ] ->
    [ Xmlcommand.printLibrary id dn ]

| [ "Print" "XML" "Section" diskname(dn) ident(id) ] ->
    [ Xmlcommand.printSection id dn ]
*)
END
