(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

open Pcoq
open Constr
open Prim
open Rawterm
open Term
open Names
open Libnames
open Topconstr

open Util

let constr_kw =
  [ "forall"; "fun"; "match"; "fix"; "cofix"; "with"; "in"; "for"; 
    "end"; "as"; "let"; "if"; "then"; "else"; "return";
    "Prop"; "Set"; "Type"; ".("; "_" ]

let _ = 
  if not !Options.v7 then
    List.iter (fun s -> Lexer.add_token("",s)) constr_kw

(* For Correctness syntax; doesn't work if in psyntax (freeze pb?)  *)
let _ = Lexer.add_token ("","!")

let pair loc =
  Qualid (loc, Libnames.qualid_of_string "Coq.Init.Datatypes.pair")

let mk_cast = function
    (c,(_,None)) -> c
  | (c,(_,Some ty)) -> CCast(join_loc (constr_loc c) (constr_loc ty), c, ty)

let mk_lam = function
    ([],c) -> c
  | (bl,c) -> CLambdaN(constr_loc c, bl,c)

let mk_match (loc,cil,rty,br) =
  CCases(loc,(None,rty),cil,br)

let index_of_annot bl ann =
  match bl,ann with
      [([_],_)], None -> 0
    | _, Some x ->
        let ids = List.map snd (List.flatten (List.map fst bl)) in
        (try list_index (snd x) ids - 1
        with Not_found -> error "no such fix variable")
    | _ -> error "cannot guess decreasing argument of fix"

let mk_fixb (loc,id,bl,ann,body,(tloc,tyc)) =
  let n = index_of_annot bl ann in
  let ty = match tyc with
      None -> CHole tloc
    | Some t -> CProdN(loc,bl,t) in
  (snd id,n,ty,CLambdaN(loc,bl,body))

let mk_cofixb (loc,id,bl,ann,body,(tloc,tyc)) =
  let _ = option_app (fun (aloc,_) ->
    Util.user_err_loc
      (aloc,"Constr:mk_cofixb",
       Pp.str"Annotation forbidden in cofix expression")) ann in
  let ty = match tyc with
      None -> CHole tloc
    | Some t -> CProdN(loc,bl,t) in
  (snd id,ty,CLambdaN(loc,bl,body))

let mk_fix(loc,kw,id,dcls) =
  if kw then 
    let fb = List.map mk_fixb dcls in
    CFix(loc,id,fb)
  else
    let fb = List.map mk_cofixb dcls in
    CCoFix(loc,id,fb)

let binder_constr =
  create_constr_entry (get_univ "constr") "binder_constr"

let rec mkCProdN loc bll c =
  match bll with
  | LocalRawAssum ((loc1,_)::_ as idl,t) :: bll -> 
      CProdN (loc,[idl,t],mkCProdN (join_loc loc1 loc) bll c)
  | LocalRawDef ((loc1,_) as id,b) :: bll -> 
      CLetIn (loc,id,b,mkCProdN (join_loc loc1 loc) bll c)
  | [] -> c
  | LocalRawAssum ([],_) :: bll -> mkCProdN loc bll c

let rec mkCLambdaN loc bll c =
  match bll with
  | LocalRawAssum ((loc1,_)::_ as idl,t) :: bll -> 
      CLambdaN (loc,[idl,t],mkCLambdaN (join_loc loc1 loc) bll c)
  | LocalRawDef ((loc1,_) as id,b) :: bll -> 
      CLetIn (loc,id,b,mkCLambdaN (join_loc loc1 loc) bll c)
  | [] -> c
  | LocalRawAssum ([],_) :: bll -> mkCLambdaN loc bll c

(* Hack to parse "(x:=t)" as an explicit argument without conflicts with the *)
(* admissible notation "(x t)" *)
let lpar_id_coloneq =
  Gram.Entry.of_parser "test_lpar_id_coloneq"
    (fun strm ->
      match Stream.npeek 1 strm with
        | [("","(")] ->
            (match Stream.npeek 2 strm with
	      | [_; ("IDENT",s)] ->
                  (match Stream.npeek 3 strm with
                    | [_; _; ("", ":=")] ->
                        Stream.junk strm; Stream.junk strm; Stream.junk strm;
                        Names.id_of_string s
	            | _ -> raise Stream.Failure)
              | _ -> raise Stream.Failure)
        | _ -> raise Stream.Failure)


if not !Options.v7 then
GEXTEND Gram
  GLOBAL: binder_constr lconstr constr operconstr sort global
  constr_pattern lconstr_pattern Constr.ident binder binder_let pattern;
  Constr.ident:
    [ [ id = Prim.ident -> id

      (* This is used in quotations and Syntax *)
      | id = METAIDENT -> id_of_string id ] ]
  ;
  Prim.name:
    [ [ "_" -> (loc, Anonymous) ] ]
  ;
  Prim.ast:
    [ [ "_" -> Coqast.Nvar(loc,id_of_string"_") ] ]
  ;
  global:
    [ [ r = Prim.reference -> r

      (* This is used in quotations *)
      | id = METAIDENT -> Ident (loc,id_of_string id) ] ]
  ;
  constr_pattern:
    [ [ c = constr -> c ] ]
  ;
  lconstr_pattern:
    [ [ c = lconstr -> c ] ]
  ;
  sort:
    [ [ "Set"  -> RProp Pos
      | "Prop" -> RProp Null
      | "Type" -> RType None ] ]
  ;
  lconstr:
    [ [ c = operconstr LEVEL "200" -> c ] ]
  ;
  constr:
    [ [ c = operconstr LEVEL "9" -> c ] ]
  ;
  operconstr:
    [ "250" LEFTA [ ]
    | "200" RIGHTA
      [ c = binder_constr -> c ]
    | "100" RIGHTA
      [ c1 = operconstr; ":"; c2 = binder_constr -> CCast(loc,c1,c2)
      | c1 = operconstr; ":"; c2 = operconstr LEVEL "200" -> CCast(loc,c1,c2) ]
    | "99" RIGHTA [ ]
    | "90" RIGHTA
      [ c1 = operconstr; "->"; c2 = binder_constr -> CArrow(loc,c1,c2)
      | c1 = operconstr; "->"; c2 = operconstr LEVEL"200" -> CArrow(loc,c1,c2)]
    | "10"
      [ f=operconstr; args=LIST1 appl_arg -> CApp(loc,(None,f),args)
      | "@"; f=global; args=LIST0 NEXT -> CAppExpl(loc,(None,f),args)
      | "-"; n=INT -> CNumeral (loc,Bignat.NEG (Bignat.of_string n)) ]
    | "9" [ ]
    | "1" LEFTA
      [ c=operconstr; ".("; f=global; args=LIST0 appl_arg; ")" ->
	CApp(loc,(Some (List.length args+1),CRef f),args@[c,None])
      | c=operconstr; ".("; "@"; f=global;
        args=LIST0 (operconstr LEVEL "9"); ")" ->
        CAppExpl(loc,(Some (List.length args+1),f),args@[c]) 
      | c=operconstr; "%"; key=IDENT -> CDelimiters (loc,key,c) ]
    | "0"
      [ c=atomic_constr -> c
      | c=match_constr -> c
      | "("; c = operconstr LEVEL "250"; ")" -> c ] ]
  ;
  binder_constr:
    [ [ "forall"; bl = binder_list; ","; c = operconstr LEVEL "200" ->
          mkCProdN loc bl c
      | "fun"; bl = binder_list; "=>"; c = operconstr LEVEL "200" ->
          mkCLambdaN loc bl c
      | "let"; id=name; bl = LIST0 binder_let; ty = type_cstr; ":=";
        c1 = operconstr LEVEL "200"; "in"; c2 = operconstr LEVEL "200" ->
          let loc1 = match bl with
            | LocalRawAssum ((loc,_)::_,_)::_ -> loc
            | LocalRawDef ((loc,_),_)::_ -> loc
            | _ -> dummy_loc in
          CLetIn(loc,id,mkCLambdaN loc1 bl (mk_cast(c1,ty)),c2)
      | "let"; fx = fix_constr; "in"; c = operconstr LEVEL "200" ->
          let (li,id) = match fx with
              CFix(_,id,_) -> id
            | CCoFix(_,id,_) -> id
            | _ -> assert false in
          CLetIn(loc,(li,Name id),fx,c)
      | "let"; lb = ["("; l=LIST0 name SEP ","; ")" -> l | "()" -> []];
	  po = return_type;
	  ":="; c1 = operconstr LEVEL "200"; "in";
          c2 = operconstr LEVEL "200" ->
          CLetTuple (loc,List.map snd lb,po,c1,c2)
      | "if"; c=operconstr LEVEL "200"; po = return_type;
	"then"; b1=operconstr LEVEL "200";
        "else"; b2=operconstr LEVEL "200" ->
          CIf (loc, c, po, b1, b2)
      | c=fix_constr -> c ] ]
  ;
  appl_arg:
    [ [ id = lpar_id_coloneq; c=lconstr; ")" ->
	  (c,Some (loc,ExplByName id))
      | c=constr -> (c,None) ] ]
  ;
  atomic_constr:
    [ [ g=global -> CRef g
      | s=sort -> CSort(loc,s)
      | n=INT -> CNumeral (loc,Bignat.POS (Bignat.of_string n))
      | "_" -> CHole loc
      | "?"; id=ident -> CPatVar(loc,(false,id)) ] ]
  ;
  fix_constr:
    [ [ kw=fix_kw; dcl=fix_decl ->
          let (_,n,_,_,_,_) = dcl in mk_fix(loc,kw,n,[dcl])
      | kw=fix_kw; dcl1=fix_decl; "with"; dcls=LIST1 fix_decl SEP "with";
        "for"; id=identref ->
          mk_fix(loc,kw,id,dcl1::dcls)
    ] ]
    ;
  fix_kw:
    [ [ "fix" -> true
      | "cofix" -> false ] ]
  ;
  fix_decl:
    [ [ id=identref; bl=LIST0 binder; ann=fixannot; ty=type_cstr; ":=";
        c=operconstr LEVEL "200" -> (loc,id,bl,ann,c,ty) ] ]
  ;
  fixannot:
    [ [ "{"; IDENT "struct"; id=name; "}" -> Some id
      | -> None ] ]
  ;
  match_constr:
    [ [ "match"; ci=LIST1 case_item SEP ","; ty=OPT case_type; "with";
        br=branches; "end" -> mk_match (loc,ci,ty,br) ] ]
  ;
  case_item:
    [ [ c=operconstr LEVEL "100"; p=pred_pattern -> 
      match c,p with
        | CRef (Ident (_,id)), (None,indp) -> (c,(Name id,indp))
        | _, (None,indp) -> (c,(Anonymous,indp))
        | _, (Some na,indp) -> (c,(na,indp)) ] ]
  ;
  pred_pattern:
    [ [ ona = OPT ["as"; id=name -> snd id];
        ty = OPT ["in"; t=lconstr -> t] -> (ona,ty) ] ]
  ;
  case_type:
    [ [ "return"; ty = operconstr LEVEL "100" -> ty ] ]
  ;
  return_type:
    [ [ a = OPT [ na = ["as"; id=name -> snd id | -> Names.Anonymous];
              ty = case_type -> (na,ty) ] -> 
        match a with 
          | None -> Names.Anonymous, None
          | Some (na,t) -> (na, Some t)
    ] ]
  ;
  branches:
    [ [ OPT"|"; br=LIST0 eqn SEP "|" -> br ] ]
  ;
  eqn:
    [ [ pl = LIST1 pattern LEVEL "200" SEP ","; "=>"; rhs = lconstr -> (loc,pl,rhs) ] ]
  ;
  pattern:
    [ "250" LEFTA [ ]
    | "200" RIGHTA [ ]
    | "99" RIGHTA [ ]
    | "90" RIGHTA [ ]
    | "10" LEFTA
      [ p = pattern ; lp = LIST1 (pattern LEVEL "0") ->
        (match p with
          | CPatAtom (_, Some r) -> CPatCstr (loc, r, lp)
          | _ -> Util.user_err_loc 
              (cases_pattern_loc p, "compound_pattern",
               Pp.str "Constructor expected"))
      | p = pattern; "as"; id = base_ident ->
	  CPatAlias (loc, p, id)
      | c = pattern; "%"; key=IDENT -> 
          CPatDelimiters (loc,key,c) ]
    | "9" []
    | "1" []
    | "0"
      [ r = Prim.reference -> CPatAtom (loc,Some r)
      | "_" -> CPatAtom (loc,None)
      | "("; p = pattern LEVEL "250"; ")" -> p
      | n = bigint -> CPatNumeral (loc,n) ] ]
  ;
(*
  lpattern:
    [ [ c = pattern -> c
      | p1=pattern; ","; p2=lpattern ->  CPatCstr (loc, pair loc, [p1;p2]) ] ]
  ;
*)
  binder_list:
    [ [ idl=LIST1 name; bl=LIST0 binder_let -> 
          LocalRawAssum (idl,CHole loc)::bl
      | idl=LIST1 name; ":"; c=lconstr -> 
          [LocalRawAssum (idl,c)]
      | "("; idl=LIST1 name; ":"; c=lconstr; ")"; bl=LIST0 binder_let ->
          LocalRawAssum (idl,c)::bl ] ]
  ;
  binder_let:
    [ [ id=name ->
          LocalRawAssum ([id],CHole loc)
      | "("; id=name; idl=LIST1 name; ":"; c=lconstr; ")" -> 
          LocalRawAssum (id::idl,c)
      | "("; id=name; ":"; c=lconstr; ")" -> 
          LocalRawAssum ([id],c)
      | "("; id=name; ":="; c=lconstr; ")" ->
          LocalRawDef (id,c)
      | "("; id=name; ":"; t=lconstr; ":="; c=lconstr; ")" -> 
          LocalRawDef (id,CCast (join_loc (constr_loc t) loc,c,t))
    ] ]
  ;
  binder:
    [ [ id=name -> ([id],CHole loc)
      | "("; idl=LIST1 name; ":"; c=lconstr; ")" -> (idl,c) ] ]
  ;
  type_cstr:
    [ [ c=OPT [":"; c=lconstr -> c] -> (loc,c) ] ]
  ;
  END;;
