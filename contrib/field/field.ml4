(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i camlp4deps: "parsing/grammar.cma" i*)

(* $Id$ *)

open Names
open Pp
open Proof_type
open Tacinterp
open Tacmach
open Term
open Typing
open Util
open Vernacinterp
open Vernacexpr
open Tacexpr

(* Interpretation of constr's *)
let constr_of c = Constrintern.interp_constr Evd.empty (Global.env()) c

(* Construction of constants *)
let constant dir s = Coqlib.gen_constant "Field" ("field"::dir) s

(* To deal with the optional arguments *)
let constr_of_opt a opt =
  let ac = constr_of a in
  match opt with
  | None -> mkApp ((constant ["Field_Compl"] "None"),[|ac|])
  | Some f -> mkApp ((constant ["Field_Compl"] "Some"),[|ac;constr_of f|])

(* Table of theories *)
let th_tab = ref (Gmap.empty : (constr,constr) Gmap.t)

let lookup typ = Gmap.find typ !th_tab

let _ = 
  let init () = th_tab := Gmap.empty in
  let freeze () = !th_tab in
  let unfreeze fs = th_tab := fs in
  Summary.declare_summary "field"
    { Summary.freeze_function   = freeze;
      Summary.unfreeze_function = unfreeze;
      Summary.init_function     = init;
      Summary.survive_section   = false }

let load_addfield _ = ()
let cache_addfield (_,(typ,th)) = th_tab := Gmap.add typ th !th_tab
let subst_addfield (_,subst,(typ,th as obj)) =
  let typ' = subst_mps subst typ in
  let th' = subst_mps subst th in
    if typ' == typ && th' == th then obj else
      (typ',th')
let export_addfield x = Some x

(* Declaration of the Add Field library object *)
let (in_addfield,out_addfield)=
  Libobject.declare_object {(Libobject.default_object "ADD_FIELD") with
       Libobject.open_function = (fun i o -> if i=1 then cache_addfield o);
       Libobject.cache_function = cache_addfield;
       Libobject.subst_function = subst_addfield;
       Libobject.classify_function = (fun (_,a) -> Libobject.Substitute a);
       Libobject.export_function = export_addfield }

(* Adds a theory to the table *)
let add_field a aplus amult aone azero aopp aeq ainv aminus_o adiv_o rth
  ainv_l =
  begin
    (try
      Ring.add_theory true true false a None None None aplus amult aone azero
        (Some aopp) aeq rth Quote.ConstrSet.empty
     with | UserError("Add Semi Ring",_) -> ());
    let th = mkApp ((constant ["Field_Theory"] "Build_Field_Theory"),
      [|a;aplus;amult;aone;azero;aopp;aeq;ainv;aminus_o;adiv_o;rth;ainv_l|]) in
    begin
      let _ = type_of (Global.env ()) Evd.empty th in ();
      Lib.add_anonymous_leaf (in_addfield (a,th))
    end
  end

(* Vernac command declaration *)
open Extend
open Pcoq
open Genarg

VERNAC ARGUMENT EXTEND divarg
| [ "div" ":=" constr(adiv) ] -> [ adiv ]
END

VERNAC ARGUMENT EXTEND minusarg
| [ "minus" ":=" constr(aminus) ] -> [ aminus ]
END

(*
(* The v7->v8 translator needs printers, then temporary use ARGUMENT EXTEND...*)
VERNAC ARGUMENT EXTEND minus_div_arg
| [ "with" minusarg(m) divarg_opt(d) ] -> [ Some m, d ]
| [ "with" divarg(d) minusarg_opt(m) ] -> [ m, Some d ]
| [ ] -> [ None, None ]
END
*)

(* For the translator, otherwise the code above is OK *)
open Ppconstrnew
let pp_minus_div_arg _prc _prt (omin,odiv) = 
  if omin=None && odiv=None then mt() else
    spc() ++ str "with" ++
    pr_opt (fun c -> str "minus := " ++ _prc c) omin ++
    pr_opt (fun c -> str "div := " ++ _prc c) odiv
(*
let () =
  Pptactic.declare_extra_genarg_pprule true
    (rawwit_minus_div_arg,pp_minus_div_arg)
    (globwit_minus_div_arg,pp_minus_div_arg)
    (wit_minus_div_arg,pp_minus_div_arg)
*)
ARGUMENT EXTEND minus_div_arg 
  TYPED AS constr_opt * constr_opt
  PRINTED BY pp_minus_div_arg
| [ "with" minusarg(m) divarg_opt(d) ] -> [ Some m, d ]
| [ "with" divarg(d) minusarg_opt(m) ] -> [ m, Some d ]
| [ ] -> [ None, None ]
END

VERNAC COMMAND EXTEND Field
  [ "Add" "Field" 
      constr(a) constr(aplus) constr(amult) constr(aone)
      constr(azero) constr(aopp) constr(aeq)
      constr(ainv) constr(rth) constr(ainv_l) minus_div_arg(md) ]
    -> [ let (aminus_o, adiv_o) = md in
         add_field
           (constr_of a) (constr_of aplus) (constr_of amult)
           (constr_of aone) (constr_of azero) (constr_of aopp)
           (constr_of aeq) (constr_of ainv) (constr_of_opt a aminus_o)
           (constr_of_opt a adiv_o) (constr_of rth) (constr_of ainv_l) ]
END

(* Guesses the type and calls Field_Gen with the right theory *)
let field g =
  Library.check_required_library ["Coq";"field";"Field"];
  let ist = { lfun=[]; lmatch=[]; debug=get_debug () } in
  let typ = 
    match Hipattern.match_with_equation (pf_concl g) with
      | Some (eq,t::args) when eq = Coqlib.build_coq_eq_data.Coqlib.eq () -> t
      | _ -> error "The statement is not built from Leibniz' equality" in
  let th = VConstr (lookup typ) in
  (interp_tac_gen [(id_of_string "FT",th)] [] (get_debug ())
    <:tactic< Match Context With [|-(!eq ?1 ?2 ?3)] -> Field_Gen FT>>) g

(* Verifies that all the terms have the same type and gives the right theory *)
let guess_theory env evc = function
  | c::tl ->
    let t = type_of env evc c in
    if List.exists (fun c1 ->
      not (Reductionops.is_conv env evc t (type_of env evc c1))) tl then
      errorlabstrm "Field:" (str" All the terms must have the same type")
    else
      lookup t
  | [] -> anomaly "Field: must have a non-empty constr list here"

(* Guesses the type and calls Field_Term with the right theory *)
let field_term l g =
  Library.check_required_library ["Coq";"field";"Field"];
  let env = (pf_env g)
  and evc = (project g) in
  let th = valueIn (VConstr (guess_theory env evc l))
  and nl = List.map (fun x -> valueIn (VConstr x)) (Quote.sort_subterm g l) in
  (List.fold_right
    (fun c a ->
     let tac = (Tacinterp.interp <:tactic<(Field_Term $th $c)>>) in
     Tacticals.tclTHENFIRSTn tac [|a|]) nl Tacticals.tclIDTAC) g

(* Declaration of Field *)

TACTIC EXTEND Field
| [ "Field" ] -> [ field ]
| [ "Field" ne_constr_list(l) ] -> [ field_term l ]
END
