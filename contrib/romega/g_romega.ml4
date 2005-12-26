(*************************************************************************

   PROJET RNRT Calife - 2001
   Author: Pierre Cr�gut - France T�l�com R&D
   Licence : LGPL version 2.1

 *************************************************************************)

(*i camlp4deps: "parsing/grammar.cma" i*)

open Refl_omega

TACTIC EXTEND romelga
  [ "romega" ] -> [ total_reflexive_omega_tactic ]
END
