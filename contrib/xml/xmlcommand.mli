(******************************************************************************)
(*                                                                            *)
(*                               PROJECT HELM                                 *)
(*                                                                            *)
(*                     A tactic to print Coq objects in XML                   *)
(*                                                                            *)
(*                Claudio Sacerdoti Coen <sacerdot@cs.unibo.it>               *)
(*                                 17/11/1999                                 *)
(*                                                                            *)
(* This module defines a pretty-printer and the stream of commands to the pp  *)
(*                                                                            *)
(******************************************************************************)

(* print id dest                                                          *)
(*  where id   is the identifier (name) of a definition/theorem or of an  *)
(*             inductive definition                                       *)
(*  and   dest is either None (for stdout) or (Some filename)             *)
(* pretty prints via Xml.pp the object whose identifier is id on dest     *)
(* Note: it is printed only (and directly) the most cooked available      *)
(*       form of the definition (all the parameters are                   *)
(*       lambda-abstracted, but the object can still refer to variables)  *)
val print : Names.identifier -> string option -> unit

(* show dest                                                  *)
(*  where dest is either None (for stdout) or (Some filename) *)
(* pretty prints via Xml.pp the proof in progress on dest     *)
val show : string option -> unit

(* print All () prints what is the structure of the current environment of *)
(* Coq. No terms are printed. Useful only for debugging                    *)
val printAll : unit -> unit

(* printModule identifier directory_name *)
(*  where identifier     is the name of a module d                           *)
(*  and   directory_name is the directory in which to root all the xml files *)
(* prints all the xml files and directories corresponding to the subsections *)
(* and terms of the module d                                                 *)
(* Note: the terms are printed in their uncooked form plus the informations  *)
(* on the parameters of their most cooked form                               *)
val printModule : Names.identifier -> string option -> unit
