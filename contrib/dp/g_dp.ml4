(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i camlp4deps: "parsing/grammar.cma" i*)

(* $Id$ *)

open Dp

TACTIC EXTEND Simplify
  [ "simplify" ] -> [ simplify ]
END

TACTIC EXTEND Ergo
  [ "ergo" ] -> [ ergo ]
END

TACTIC EXTEND Yices
  [ "yices" ] -> [ yices ]
END

TACTIC EXTEND CVCLite
  [ "cvcl" ] -> [ cvc_lite ]
END

TACTIC EXTEND Harvey
  [ "harvey" ] -> [ harvey ]
END

TACTIC EXTEND Zenon
  [ "zenon" ] -> [ zenon ]
END

TACTIC EXTEND Gwhy
  [ "gwhy" ] -> [ gwhy ]
END

TACTIC EXTEND Gappa_internal
  [ "gappa_internal" ] -> [ Dp_gappa.gappa_internal ]
END

TACTIC EXTEND Gappa
  [ "gappa" ] -> [ Dp_gappa.gappa ]
END

(* should be part of basic tactics syntax *)
TACTIC EXTEND admit
  [ "admit"    ] -> [ Tactics.admit_as_an_axiom ]
END

VERNAC COMMAND EXTEND Dp_hint 
  [ "Dp_hint" ne_global_list(l) ] -> [ dp_hint l ]
END

VERNAC COMMAND EXTEND Dp_timeout
| [ "Dp_timeout" natural(n) ] -> [ dp_timeout n ]
END

VERNAC COMMAND EXTEND Dp_prelude
| [ "Dp_prelude" string_list(l) ] -> [ dp_prelude l ]
END

VERNAC COMMAND EXTEND Dp_predefined
| [ "Dp_predefined" global(g) "=>" string(s) ] -> [ dp_predefined g s ]
END

VERNAC COMMAND EXTEND Dp_debug
| [ "Dp_debug" ] -> [ dp_debug true; Dp_zenon.set_debug true ]
END

VERNAC COMMAND EXTEND Dp_trace
| [ "Dp_trace" ] -> [ dp_trace true ]
END

