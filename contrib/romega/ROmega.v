(*************************************************************************

   PROJET RNRT Calife - 2001
   Author: Pierre Cr�gut - France T�l�com R&D
   Licence : LGPL version 2.1

 *************************************************************************)

Require Omega.
Require ReflOmegaCore.

Declare ML Module "const_omega".
Declare ML Module "refl_omega".

Grammar tactic simple_tactic : ast :=
  romega [ "ROmega" ] -> [(ReflOmega)].

Syntax tactic level 0:
  romega [ << (ReflOmega) >> ] -> ["ROmega"].        
