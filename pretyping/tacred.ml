
(* $Id$ *)

open Pp
open Util
open Names
open Generic
open Term
open Inductive
open Environ
open Reduction
open Instantiate
open Redinfo

exception Elimconst
exception Redelimination

let rev_firstn_liftn fn ln = 
  let rec rfprec p res l = 
    if p = 0 then 
      res 
    else
      match l with
        | [] -> invalid_arg "Reduction.rev_firstn_liftn"
        | a::rest -> rfprec (p-1) ((lift ln a)::res) rest
  in 
  rfprec fn []

(*  EliminationFix ([(yi1,Ti1);...;(yip,Tip)],n) means f is some
   [y1:T1,...,yn:Tn](Fix(..) yi1 ... yip);
   f is applied to largs and we need for recursive calls to build
   [x1:Ti1',...,xp:Tip'](f a1..a(n-p) yi1 ... yip) 
   where a1...an are the n first arguments of largs and Tik' is Tik[yil=al]
   To check ... *)

let make_elim_fun f lv n largs =
  let (sp,args) = destConst f in
  let labs,_ = list_chop n largs in
  let p = List.length lv in
  let ylv = List.map fst lv in
  let la' = list_map_i 
	      (fun q aq ->
		 try (Rel (p+1-(list_index (n-q) ylv))) 
		 with Not_found -> aq) 0
              (List.map (lift p) labs) 
  in 
  fun id -> 
    let fi = DOPN(Const(make_path (dirpath sp) id (kind_of_path sp)),args) in
    list_fold_left_i 
      (fun i c (k,a) -> 
	 DOP2(Lambda,(substl (rev_firstn_liftn (n-k) (-i) la') a),
              DLAM(Name(id_of_string"x"),c))) 0 (applistc fi la') lv

(* [f] is convertible to [DOPN(Fix(recindices,bodynum),bodyvect)] make 
   the reduction using this extra information *)

let contract_fix_use_function f
  ((recindices,bodynum),(types,names,bodies as typedbodies)) =
  let nbodies = Array.length recindices in
  let make_Fi j =
    match List.nth names j with Name id -> f id | _ -> assert false in
  let lbodies = list_tabulate make_Fi nbodies in
  substl (List.rev lbodies) bodies.(bodynum)

let reduce_fix_use_function f whfun fix stack =
  let dfix = destFix fix in
  match fix_recarg dfix stack with
    | None -> (false,(fix,stack))
    | Some (recargnum,recarg) ->
        let (recarg'hd,_ as recarg')= whfun recarg [] in
        let stack' = list_assign stack recargnum (applist recarg') in
	(match recarg'hd with
           | DOPN(MutConstruct _,_) ->
	       (true,(contract_fix_use_function f dfix,stack'))
	   | _ -> (false,(fix,stack')))

let contract_cofix_use_function f (bodynum,(_,names,bodies as typedbodies)) =
  let nbodies = Array.length bodies in
  let make_Fi j =
    match List.nth names j with Name id -> f id | _ -> assert false in
  let subbodies = list_tabulate make_Fi nbodies in
  substl subbodies bodies.(bodynum)

let reduce_mind_case_use_function env f mia =
  match mia.mconstr with 
    | DOPN(MutConstruct(ind_sp,i as cstr_sp),args) ->
	let ncargs = (fst mia.mci).(i-1) in
	let real_cargs = list_lastn ncargs mia.mcargs in
	applist (mia.mlf.(i-1),real_cargs)
    | DOPN(CoFix _,_) as cofix ->
	let cofix_def = contract_cofix_use_function f (destCoFix cofix) in
	mkMutCaseA mia.mci mia.mP (applist(cofix_def,mia.mcargs)) mia.mlf
    | _ -> assert false
	  
let special_red_case env whfun p c ci lf  =
  let rec redrec c l = 
    let (constr,cargs) = whfun c l in 
    match constr with 
      | DOPN(Const sp,args) as g -> 
          if evaluable_constant env g then
            let gvalue = constant_value env g in
            if reducible_mind_case gvalue then
	      let build_fix_name id =
		DOPN(Const(make_path (dirpath sp) id (kind_of_path sp)),args)
	      in reduce_mind_case_use_function env build_fix_name
                   {mP=p; mconstr=gvalue; mcargs=cargs; mci=ci; mlf=lf}
            else 
	      redrec gvalue cargs
          else 
	    raise Redelimination
      | _ ->
          if reducible_mind_case constr then
            reduce_mind_case
	      {mP=p; mconstr=constr; mcargs=cargs; mci=ci; mlf=lf}
          else 
	    raise Redelimination
  in 
  redrec c []

let rec red_elim_const env sigma k largs =
  if not (evaluable_constant env k) then raise Redelimination;
  let (sp, args) = destConst k in
  let elim_style = constant_eval sp in
  match elim_style with
    | EliminationCases n when List.length largs >= n -> begin
	let c = constant_value env k in
	match whd_betadeltaeta_stack env sigma c largs with
	  | (DOPN(MutCase _,_) as mc,lrest) ->
              let (ci,p,c,lf) = destCase mc in
              (special_red_case env (construct_const env sigma) p c ci lf,
	       lrest)
	  | _ -> assert false
      end
    | EliminationFix (lv,n) when List.length largs >= n -> begin
	let c = constant_value env k in
	match whd_betadeltaeta_stack env sigma c largs with
	  | (DOPN(Fix _,_) as fix,lrest) -> 
	      let f id = make_elim_fun k lv n largs id in
              let (b,(c,rest)) = 
		reduce_fix_use_function f (construct_const env sigma) fix lrest
              in 
	      if b then (nf_beta env sigma c, rest) else raise Redelimination
	  | _ -> assert false
      end
    | _ -> raise Redelimination

and construct_const env sigma c stack = 
  let rec hnfstack x stack =
    match x with
      | (DOPN(Const _,_)) as k  ->
          (try
             let (c',lrest) = red_elim_const env sigma k stack in 
	     hnfstack c' lrest
           with Redelimination ->
             if evaluable_constant env k then 
	       let cval = constant_value env k in
	       (match cval with
                  | DOPN (CoFix _,_) -> (k,stack)
                  | _ -> hnfstack cval stack) 
             else 
	       raise Redelimination)
      | (DOPN(Abst _,_) as a) ->
          if evaluable_abst env a then 
	    hnfstack (abst_value env a) stack
          else 
	    raise Redelimination
      | DOP2(Cast,c,_) -> hnfstack c stack
      | DOPN(AppL,cl) -> hnfstack (array_hd cl) (array_app_tl cl stack)
      | DOP2(Lambda,_,DLAM(_,c)) ->
          (match stack with 
             | [] -> assert false
             | c'::rest -> stacklam hnfstack [c'] c rest)
      | DOPN(MutCase _,_) as c_0 ->
          let (ci,p,c,lf) = destCase c_0 in
          hnfstack 
	    (special_red_case env (construct_const env sigma) p c ci lf) 
	    stack
      | DOPN(MutConstruct _,_) as c_0 -> c_0,stack
      | DOPN(CoFix _,_) as c_0 -> c_0,stack
      | DOPN(Fix (_) ,_) as fix -> 
          let (reduced,(fix,stack')) = reduce_fix hnfstack fix stack in 
	  if reduced then hnfstack fix stack' else raise Redelimination
      | _ -> raise Redelimination
  in 
  hnfstack c stack

(* Hnf reduction tactic: *)

let hnf_constr env sigma c = 
  let rec redrec x largs =
    match x with
      | DOP2(Lambda,t,DLAM(n,c)) ->
          (match largs with
             | []      -> applist(x,largs)
             | a::rest -> stacklam redrec [a] c rest)
      | DOPN(AppL,cl)   -> redrec (array_hd cl) (array_app_tl cl largs)
      | DOPN(Const _,_) ->
          (try
             let (c',lrest) = red_elim_const env sigma x largs in 
	     redrec c' lrest
           with Redelimination ->
             if evaluable_constant env x then
               let c = constant_value env x in
	       (match c with 
                  | DOPN(CoFix _,_) -> applist(x,largs)
		  | _ ->  redrec c largs)
             else 
	       applist(x,largs))
      | DOPN(Abst _,_) ->
          if evaluable_abst env x then 
	    redrec (abst_value env x) largs
          else 
	    applist(x,largs)
      | DOP2(Cast,c,_) -> redrec c largs
      | DOPN(MutCase _,_) ->
          let (ci,p,c,lf) = destCase x in
          (try
             redrec 
	       (special_red_case env (whd_betadeltaiota_stack env sigma) 
		  p c ci lf) largs
           with Redelimination -> 
	     applist(x,largs))
      | (DOPN(Fix _,_)) ->
          let (reduced,(fix,stack)) = 
            reduce_fix (whd_betadeltaiota_stack env sigma) x largs
          in 
	  if reduced then redrec fix stack else applist(x,largs)
      | _ -> applist(x,largs)
  in 
  redrec c []

(* Simpl reduction tactic: same as simplify, but also reduces
   elimination constants *)

let whd_nf env sigma c = 
  let rec nf_app c stack =
    match c with
      | DOP2(Lambda,c1,DLAM(name,c2))    ->
          (match stack with
             | [] -> (c,[])
             | a1::rest -> stacklam nf_app [a1] c2 rest)
      | DOPN(AppL,cl) -> nf_app (array_hd cl) (array_app_tl cl stack)
      | DOP2(Cast,c,_) -> nf_app c stack
      | DOPN(Const _,_) ->
          (try
             let (c',lrest) = red_elim_const env sigma c stack in 
	     nf_app c' lrest
           with Redelimination -> 
	     (c,stack))
      | DOPN(MutCase _,_) ->
          let (ci,p,d,lf) = destCase c in
          (try
             nf_app (special_red_case env nf_app p d ci lf) stack
           with Redelimination -> 
	     (c,stack))
      | DOPN(Fix _,_) ->
          let (reduced,(fix,rest)) = reduce_fix nf_app c stack in 
	  if reduced then nf_app fix rest else (fix,stack)
      | _ -> (c,stack)
  in 
  applist (nf_app c [])

let nf env sigma c = strong whd_nf env sigma c

(* Generic reduction: reduction functions used in reduction tactics *)

type red_expr =
  | Red
  | Hnf
  | Simpl
  | Cbv of Closure.flags
  | Lazy of Closure.flags
  | Unfold of (int list * section_path) list
  | Fold of constr list
  | Pattern of (int list * constr * constr) list

let reduction_of_redexp = function
  | Red -> red_product
  | Hnf -> hnf_constr
  | Simpl -> nf
  | Cbv f -> cbv_norm_flags f
  | Lazy f -> clos_norm_flags f
  | Unfold ubinds -> unfoldn ubinds
  | Fold cl -> fold_commands cl
  | Pattern lp -> pattern_occs lp

(* Used in several tactics. *)

let one_step_reduce env sigma = 
  let rec redrec largs x =
    match x with
      | DOP2(Lambda,t,DLAM(n,c))  ->
          (match largs with
             | []      -> error "Not reducible 1"
             | a::rest -> applistc (subst1 a c) rest)
      | DOPN(AppL,cl) -> redrec (array_app_tl cl largs) (array_hd cl)
      | DOPN(Const _,_) ->
          (try
             let (c',l) = red_elim_const env sigma x largs in applistc c' l
           with Redelimination ->
             if evaluable_constant env x then
               applistc (constant_value env x) largs
             else error "Not reductible 1")
      | DOPN(Abst _,_) ->
          if evaluable_abst env x then applistc (abst_value env x) largs
          else error "Not reducible 0"
      | DOPN(MutCase _,_) ->
          let (ci,p,c,lf) = destCase x in
          (try
	     applistc 
	       (special_red_case env (whd_betadeltaiota_stack env sigma) 
		  p c ci lf) largs 
           with Redelimination -> error "Not reducible 2")
      | DOPN(Fix _,_) ->
          let (reduced,(fix,stack)) = 
	    reduce_fix (whd_betadeltaiota_stack env sigma) x largs
          in 
	  if reduced then applistc fix stack else error "Not reducible 3"
      | DOP2(Cast,c,_) -> redrec largs c
      | _ -> error "Not reducible 3"
  in 
  redrec []

(* put t as t'=(x1:A1)..(xn:An)B with B an inductive definition of name name
   return name, B and t' *)

let reduce_to_mind env sigma t = 
  let rec elimrec t l = 
    match whd_castapp_stack t [] with
      | (DOPN(MutInd mind,args),_) -> ((mind,args),t,prod_it t l)
      | (DOPN(Const _,_),_) -> 
          (try 
	     let t' = nf_betaiota env sigma (one_step_reduce env sigma t) in 
	     elimrec t' l
           with UserError _ -> errorlabstrm "tactics__reduce_to_mind"
               [< 'sTR"Not an inductive product : it is a constant." >])
      | (DOPN(MutCase _,_),_) ->
          (try 
	     let t' = nf_betaiota env sigma (one_step_reduce env sigma t) in 
	     elimrec t' l
           with UserError _ -> errorlabstrm "tactics__reduce_to_mind"
               [< 'sTR"Not an inductive product:"; 'sPC;
		  'sTR"it is a case analysis term" >])
      | (DOP2(Cast,c,_),[]) -> elimrec c l
      | (DOP2(Prod,ty,DLAM(n,t')),[]) -> elimrec t' ((n,ty)::l)
      | _ -> error "Not an inductive product"
 in 
 elimrec t []

let reduce_to_ind env sigma t =
  let ((ind_sp,_),redt,c) = reduce_to_mind env sigma t in 
  (Declare.path_of_inductive_path ind_sp, redt, c)
