(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

(*i*)
open Util
open Names
open Sign
open Term
open Libnames
open Nametab
(*i*)

(* Untyped intermediate terms, after ASTs and before constr. *)

type loc = int * int

(* locs here refers to the ident's location, not whole pat *)
(* the last argument of PatCstr is a possible alias ident for the pattern *)
type cases_pattern =
  | PatVar of loc * name
  | PatCstr of loc * constructor * cases_pattern list * name

let pattern_loc = function
    PatVar(loc,_) -> loc
  | PatCstr(loc,_,_,_) -> loc

type patvar = identifier

type rawsort = RProp of Term.contents | RType of Univ.universe option

type fix_kind = RFix of (int array * int) | RCoFix of int

type binder_kind = BProd | BLambda | BLetIn

type quantified_hypothesis = AnonHyp of int | NamedHyp of identifier

type 'a explicit_bindings = (loc * quantified_hypothesis * 'a) list

type 'a bindings = 
  | ImplicitBindings of 'a list
  | ExplicitBindings of 'a explicit_bindings
  | NoBindings

type 'a with_bindings = 'a * 'a bindings

type hole_kind =
  | ImplicitArg of global_reference * int
  | BinderType of name
  | QuestionMark
  | CasesType
  | InternalHole
  | TomatchTypeParameter of inductive * int

type rawconstr = 
  | RRef of (loc * global_reference)
  | RVar of (loc * identifier)
  | REvar of loc * existential_key
  | RPatVar of loc * (bool * patvar) (* Used for patterns only *)
  | RApp of loc * rawconstr * rawconstr list
  | RLambda of loc * name * rawconstr * rawconstr
  | RProd of loc * name * rawconstr * rawconstr
  | RLetIn of loc * name * rawconstr * rawconstr
  | RCases of loc * (rawconstr option * rawconstr option ref) *
      (rawconstr * (name * (loc * inductive * name list) option) ref) list * 
      (loc * identifier list * cases_pattern list * rawconstr) list
      (* Rem: "ref" used for the v7->v8 translation only *)
  | ROrderedCase of loc * case_style * rawconstr option * rawconstr * 
      rawconstr array * rawconstr option ref
  | RLetTuple of loc * name list * (name * rawconstr option) * 
      rawconstr * rawconstr
  | RIf of loc * rawconstr * (name * rawconstr option) * rawconstr * rawconstr
  | RRec of loc * fix_kind * identifier array * 
      rawconstr array * rawconstr array
  | RSort of loc * rawsort
  | RHole of (loc * hole_kind)
  | RCast of loc * rawconstr * rawconstr
  | RDynamic of loc * Dyn.t

let cases_predicate_names tml =
  List.flatten (List.map (function
    | (tm,{contents=(na,None)}) -> [na]
    | (tm,{contents=(na,Some (_,_,nal))}) -> na::nal) tml)

(*i - if PRec (_, names, arities, bodies) is in env then arities are
   typed in env too and bodies are typed in env enriched by the
   arities incrementally lifted 

  [On pourrait plutot mettre les arit�s aves le type qu'elles auront
   dans le contexte servant � typer les body ???]

   - boolean in POldCase means it is recursive
i*)

let map_rawconstr f = function
  | RVar (loc,id) -> RVar (loc,id)
  | RApp (loc,g,args) -> RApp (loc,f g, List.map f args)
  | RLambda (loc,na,ty,c) -> RLambda (loc,na,f ty,f c)
  | RProd (loc,na,ty,c) -> RProd (loc,na,f ty,f c)
  | RLetIn (loc,na,b,c) -> RLetIn (loc,na,f b,f c)
  | RCases (loc,(tyopt,rtntypopt),tml,pl) ->
      RCases (loc,(option_app f tyopt,ref (option_app f !rtntypopt)),
        List.map (fun (tm,x) -> (f tm,x)) tml,
        List.map (fun (loc,idl,p,c) -> (loc,idl,p,f c)) pl)
  | ROrderedCase (loc,b,tyopt,tm,bv,x) ->
      ROrderedCase (loc,b,option_app f tyopt,f tm, Array.map f bv,ref (option_app f !x))
  | RLetTuple (loc,nal,(na,po),b,c) ->
      RLetTuple (loc,nal,(na,option_app f po),f b,f c)
  | RIf (loc,c,(na,po),b1,b2) ->
      RIf (loc,f c,(na,option_app f po),f b1,f b2)
  | RRec (loc,fk,idl,tyl,bv) -> RRec (loc,fk,idl,Array.map f tyl,Array.map f bv)
  | RCast (loc,c,t) -> RCast (loc,f c,f t)
  | (RSort _ | RHole _ | RRef _ | REvar _ | RPatVar _ | RDynamic _) as x -> x

(*
let name_app f e = function
  | Name id -> let (id, e) = f id e in (Name id, e)
  | Anonymous -> Anonymous, e

let fold_ident g idl e =
  let (idl,e) =
    Array.fold_right
      (fun id (idl,e) -> let id,e = g id e in (id::idl,e)) idl ([],e)
  in (Array.of_list idl,e)

let map_rawconstr_with_binders_loc loc g f e = function
  | RVar (_,id) -> RVar (loc,id)
  | RApp (_,a,args) -> RApp (loc,f e a, List.map (f e) args)
  | RLambda (_,na,ty,c) ->
      let na,e = name_app g e na in RLambda (loc,na,f e ty,f e c)
  | RProd (_,na,ty,c) ->
      let na,e = name_app g e na in RProd (loc,na,f e ty,f e c)
  | RLetIn (_,na,b,c) ->
      let na,e = name_app g e na in RLetIn (loc,na,f e b,f e c)
  | RCases (_,tyopt,tml,pl) ->
      (* We don't modify pattern variable since we don't traverse patterns *)
      let g' id e = snd (g id e) in
      let h (_,idl,p,c) = (loc,idl,p,f (List.fold_right g' idl e) c) in
      RCases
	(loc,option_app (f e) tyopt,List.map (f e) tml, List.map h pl)
  | ROrderedCase (_,b,tyopt,tm,bv) ->
      ROrderedCase (loc,b,option_app (f e) tyopt,f e tm,Array.map (f e) bv)
  | RRec (_,fk,idl,tyl,bv) ->
      let idl',e' = fold_ident g idl e in
      RRec (loc,fk,idl',Array.map (f e) tyl,Array.map (f e') bv)
  | RCast (_,c,t) -> RCast (loc,f e c,f e t)
  | RSort (_,x) -> RSort (loc,x)
  | RHole (_,x)  -> RHole (loc,x)
  | RRef (_,x) -> RRef (loc,x)
  | REvar (_,x) -> REvar (loc,x)
  | RPatVar (_,x) -> RPatVar (loc,x)
  | RDynamic (_,x) -> RDynamic (loc,x)
*)

let rec subst_pat subst pat = 
  match pat with
  | PatVar _ -> pat
  | PatCstr (loc,((kn,i),j),cpl,n) -> 
      let kn' = subst_kn subst kn 
      and cpl' = list_smartmap (subst_pat subst) cpl in
	if kn' == kn && cpl' == cpl then pat else
	  PatCstr (loc,((kn',i),j),cpl',n)

let rec subst_raw subst raw = 
  match raw with
  | RRef (loc,ref) -> 
      let ref' = subst_global subst ref in 
	if ref' == ref then raw else
	  RRef (loc,ref')

  | RVar _ -> raw
  | REvar _ -> raw
  | RPatVar _ -> raw

  | RApp (loc,r,rl) -> 
      let r' = subst_raw subst r 
      and rl' = list_smartmap (subst_raw subst) rl in
	if r' == r && rl' == rl then raw else
	  RApp(loc,r',rl')

  | RLambda (loc,n,r1,r2) -> 
      let r1' = subst_raw subst r1 and r2' = subst_raw subst r2 in
	if r1' == r1 && r2' == r2 then raw else
	  RLambda (loc,n,r1',r2')

  | RProd (loc,n,r1,r2) -> 
      let r1' = subst_raw subst r1 and r2' = subst_raw subst r2 in
	if r1' == r1 && r2' == r2 then raw else
	  RProd (loc,n,r1',r2')

  | RLetIn (loc,n,r1,r2) -> 
      let r1' = subst_raw subst r1 and r2' = subst_raw subst r2 in
	if r1' == r1 && r2' == r2 then raw else
	  RLetIn (loc,n,r1',r2')

  | RCases (loc,(ro,rtno),rl,branches) -> 
      let ro' = option_smartmap (subst_raw subst) ro 
      and rtno' = ref (option_smartmap (subst_raw subst) !rtno)
      and rl' = list_smartmap (fun (a,x as y) ->
        let a' = subst_raw subst a in
        let (n,topt) = !x in 
        let topt' = option_smartmap
          (fun (loc,(sp,i),x as t) ->
            let sp' = subst_kn subst sp in
            if sp == sp' then t else (loc,(sp',i),x)) topt in
        if a == a' && topt == topt' then y else (a',ref (n,topt'))) rl
      and branches' = list_smartmap 
			(fun (loc,idl,cpl,r as branch) ->
			   let cpl' = list_smartmap (subst_pat subst) cpl
			   and r' = subst_raw subst r in
			     if cpl' == cpl && r' == r then branch else
			       (loc,idl,cpl',r'))
			branches
      in
	if ro' == ro && rl' == rl && branches' == branches then raw else
	  RCases (loc,(ro',rtno'),rl',branches')

  | ROrderedCase (loc,b,ro,r,ra,x) -> 
      let ro' = option_smartmap (subst_raw subst) ro
      and r' = subst_raw subst r 
      and ra' = array_smartmap (subst_raw subst) ra in
	if ro' == ro && r' == r && ra' == ra then raw else
	  ROrderedCase (loc,b,ro',r',ra',x)

  | RLetTuple (loc,nal,(na,po),b,c) ->
      let po' = option_smartmap (subst_raw subst) po
      and b' = subst_raw subst b 
      and c' = subst_raw subst c in
	if po' == po && b' == b && c' == c then raw else
          RLetTuple (loc,nal,(na,po'),b',c')
      
  | RIf (loc,c,(na,po),b1,b2) ->
      let po' = option_smartmap (subst_raw subst) po
      and b1' = subst_raw subst b1 
      and b2' = subst_raw subst b2 
      and c' = subst_raw subst c in
	if c' == c & po' == po && b1' == b1 && b2' == b2 then raw else
          RIf (loc,c',(na,po'),b1',b2')

  | RRec (loc,fix,ida,ra1,ra2) -> 
      let ra1' = array_smartmap (subst_raw subst) ra1
      and ra2' = array_smartmap (subst_raw subst) ra2 in
	if ra1' == ra1 && ra2' == ra2 then raw else
	  RRec (loc,fix,ida,ra1',ra2')

  | RSort _ -> raw

  | RHole (loc,ImplicitArg (ref,i)) ->
      let ref' = subst_global subst ref in 
	if ref' == ref then raw else
	  RHole (loc,ImplicitArg (ref',i))
  | RHole (loc, (BinderType _ | QuestionMark | CasesType |
      InternalHole | TomatchTypeParameter _)) -> raw

  | RCast (loc,r1,r2) -> 
      let r1' = subst_raw subst r1 and r2' = subst_raw subst r2 in
	if r1' == r1 && r2' == r2 then raw else
	  RCast (loc,r1',r2')

  | RDynamic _ -> raw

let loc_of_rawconstr = function
  | RRef (loc,_) -> loc
  | RVar (loc,_) -> loc
  | REvar (loc,_) -> loc
  | RPatVar (loc,_) -> loc
  | RApp (loc,_,_) -> loc
  | RLambda (loc,_,_,_) -> loc
  | RProd (loc,_,_,_) -> loc
  | RLetIn (loc,_,_,_) -> loc
  | RCases (loc,_,_,_) -> loc
  | ROrderedCase (loc,_,_,_,_,_) -> loc
  | RLetTuple (loc,_,_,_,_) -> loc
  | RIf (loc,_,_,_,_) -> loc
  | RRec (loc,_,_,_,_) -> loc
  | RSort (loc,_) -> loc
  | RHole (loc,_) -> loc
  | RCast (loc,_,_) -> loc
  | RDynamic (loc,_) -> loc

type 'a raw_red_flag = {
  rBeta : bool;
  rIota : bool;
  rZeta : bool;
  rDelta : bool; (* true = delta all but rConst; false = delta only on rConst*)
  rConst : 'a list
}

type 'a occurrences = int list * 'a

type ('a,'b) red_expr_gen =
  | Red of bool
  | Hnf
  | Simpl of 'a occurrences option
  | Cbv of 'b raw_red_flag
  | Lazy of 'b raw_red_flag
  | Unfold of 'b occurrences list
  | Fold of 'a list
  | Pattern of 'a occurrences list
  | ExtraRedExpr of string * 'a

type ('a,'b) may_eval =
  | ConstrTerm of 'a
  | ConstrEval of ('a, 'b) red_expr_gen * 'a
  | ConstrContext of (loc * identifier) * 'a
  | ConstrTypeOf of 'a
