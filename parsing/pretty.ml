
(* $Id$ *)

open Pp
open Util
open Names
open Term
open Declarations
open Inductive
open Sign
open Reduction
open Environ
open Instantiate
open Declare
open Impargs
open Libobject
open Printer

let print_basename sp = pr_global (ConstRef sp)

let print_closed_sections = ref false

let print_typed_value_in_env env (trm,typ) =
  [< prterm_env env trm ; 'fNL ;
     'sTR "     : "; prtype_env env typ ; 'fNL >]

let print_typed_value x = print_typed_value_in_env (Global.env ()) x

let pkprinters = function
  | FW -> (fprterm,fprterm_env)
  | CCI -> (prterm,prterm_env)
  | _ -> anomaly "pkprinters"
			  		  
let print_impl_args = function
  | []  -> [<>]
  | [i] -> [< 'sTR"Position ["; 'iNT i; 'sTR"] is implicit" >]
  | l   -> 
      [< 'sTR"Positions ["; 
         prlist_with_sep (fun () -> [< 'sTR";" >]) (fun i -> [< 'iNT i >]) l;
         'sTR"] are implicit" >]

(* To be improved; the type should be used to provide the types in the
   abstractions. This should be done recursively inside prterm, so that
   the pretty-print of a proposition (P:(nat->nat)->Prop)(P [u]u)
   synthesizes the type nat of the abstraction on u *)

let print_named_def name body typ =
  [< 'sTR "*** ["; 'sTR name ; 'sPC; 
     hOV 0 [< 'sTR ":="; 'sPC; prterm body; 'sPC;
	      'sTR ": "; prtype typ >];
	   'sTR "]"; 'fNL >]

let print_named_assum name typ =
  [< 'sTR "*** [" ; 'sTR name ; 'sTR " : "; prtype typ; 'sTR "]"; 'fNL >]

let print_named_decl (id,c,typ) =
  let s = string_of_id id in
  match c with
    | Some body -> print_named_def s body typ
    | None -> print_named_assum s typ

let assumptions_for_print lna =
  List.fold_right (fun na env -> add_name na env) lna empty_names_context

let implicit_args_id id l = 
  if l = [] then 
    [<>]
  else 
    [< 'sTR"For "; pr_id id; 'sTR": "; print_impl_args l ; 'fNL >]

let implicit_args_msg sp mipv = 
  [< prvecti
       (fun i mip -> 
	  let imps = inductive_implicits (sp,i) in
          [< (implicit_args_id mip.mind_typename (list_of_implicits imps));
             prvecti 
	       (fun j idc ->
		  let imps = constructor_implicits ((sp,i),succ j) in
                  (implicit_args_id idc (list_of_implicits imps)))
               mip.mind_consnames 
          >])
       mipv >]

let instance_of_named_context sign =
  Array.of_list (List.map mkVar (ids_of_named_context sign))

let print_mutual sp mib = 
  let pk = kind_of_path sp in
  let env = Global.env () in
  let evd = Evd.empty in
  let {mind_packets=mipv; mind_nparams=nparams} = mib in 
  let (lpars,_) = decomp_n_prod env evd nparams
		    (body_of_type (mind_user_arity mipv.(0))) in
  let arities = Array.map (fun mip -> (Name mip.mind_typename, None, mip.mind_nf_arity)) mipv in
  let env_ar = push_rels lpars env in
  let pr_constructor (id,c) =
    [< pr_id id; 'sTR " : "; prterm_env env_ar c >] in
  let print_constructors mis =
    let (_,lC) = mis_type_mconstructs mis in
    let lidC =
      array_map2 (fun id c -> (id, snd (decomp_n_prod env evd nparams c)))
	(mis_consnames mis) lC in
    let plidC =
      prvect_with_sep (fun () -> [<'bRK(1,0); 'sTR "| " >])
        pr_constructor
	lidC
    in
    hV 0 [< 'sTR "  "; plidC >] 
  in
  let params =
    if nparams = 0 then 
      [<>] 
    else
      [< 'sTR "["; pr_rel_context env lpars; 'sTR "]"; 'bRK(1,2) >] in
  let print_oneind tyi =
    let mis = build_mis ((sp,tyi),instance_of_named_context mib.mind_hyps) mib in
    let (_,arity) = decomp_n_prod env evd nparams
		      (body_of_type (mis_user_arity mis)) in
      (hOV 0
         [< (hOV 0
	       [< pr_id (mis_typename mis) ; 'bRK(1,2); params;
	          'sTR ": "; prterm_env env_ar arity; 'sTR " :=" >]);
            'bRK(1,2); print_constructors mis >]) 
  in 
  let mis0 = build_mis ((sp,0),instance_of_named_context mib.mind_hyps) mib in
  (* Case one [co]inductive *)
  if Array.length mipv = 1 then
    let (_,arity) = decomp_n_prod env evd nparams
		      (body_of_type (mis_user_arity mis0)) in 
    let sfinite = if mis_finite mis0 then "Inductive " else "CoInductive " in
    (hOV 0 [< 'sTR sfinite ; pr_id (mis_typename mis0);
              if nparams = 0 then 
		[<>] 
              else 
		[< 'sTR" ["; pr_rel_context env lpars; 'sTR "]">];
              'bRK(1,5); 'sTR": "; prterm_env env_ar arity; 'sTR" :=";
              'bRK(0,4); print_constructors mis0; 'fNL;
              implicit_args_msg sp mipv  >] )
  (* Mutual [co]inductive definitions *)
  else
    let _,(mipli,miplc) =
      List.fold_left 
        (fun (n,(li,lc)) mi ->
           if mi.mind_finite then (n+1,(n::li,lc)) else (n+1,(li,n::lc)))
        (0,([],[])) (Array.to_list mipv) 
    in 
    let strind =
      if mipli = [] then [<>] 
      else [< 'sTR "Inductive"; 'bRK(1,4);
              (prlist_with_sep
                 (fun () -> [< 'fNL; 'sTR"  with"; 'bRK(1,4) >])
                 print_oneind
                 (List.rev mipli)); 'fNL >]
    and strcoind =
      if miplc = [] then [<>] 
      else [< 'sTR "CoInductive"; 'bRK(1,4);
              (prlist_with_sep
                 (fun () -> [<'fNL; 'sTR "  with"; 'bRK(1,4) >]) 
                 print_oneind (List.rev miplc)); 'fNL >] 
    in
    (hV 0 [< 'sTR"Mutual " ; 
             if mis_finite mis0 then 
	       [< strind; strcoind >] 
             else 
	       [<strcoind; strind>];
             implicit_args_msg sp mipv >])

let print_section_variable sp =
  let (d,_,_) = get_variable sp in
  let l = implicits_of_var sp in
  [< print_named_decl d; print_impl_args l; 'fNL >]

let print_body = function
  | Some c  -> prterm c
  | None -> [< 'sTR"<no body>" >]

let print_typed_body (val_0,typ) =
  [< print_body val_0; 'fNL; 'sTR "     : "; prtype typ; 'fNL >]

let print_constant with_values sep sp =
  let cb = Global.lookup_constant sp in
  if kind_of_path sp = CCI then
    let val_0 = cb.const_body in
    let typ = cb.const_type in
    let l = constant_implicits sp in
    hOV 0 [< (match val_0 with 
		| None -> 
		    [< 'sTR"*** [ "; 
		       print_basename sp;  
		       'sTR " : "; 'cUT ; prtype typ ; 'sTR" ]"; 'fNL >]
		| _ -> 
		    [< print_basename sp; 
		       'sTR sep; 'cUT ;
		       if with_values then 
			 print_typed_body (val_0,typ) 
		       else 
			 [< prtype typ ; 'fNL >] >]); 
	     print_impl_args (list_of_implicits l); 'fNL >]
  else
    hOV 0 [< 'sTR"Fw constant " ; 
	     print_basename sp ; 'fNL>]

let print_inductive sp =
  let mib = Global.lookup_mind sp in
  if kind_of_path sp = CCI then
    [< print_mutual sp mib; 'fNL >]
  else
    hOV 0 [< 'sTR"Fw inductive definition "; 
	     print_basename sp; 'fNL >]

let print_syntactic_def with_values sep sp =
  let id = basename sp in
  [< 'sTR" Syntax Macro "; 
     pr_id id ; 'sTR sep;  
     if with_values then 
       let c = Syntax_def.search_syntactic_definition sp in 
       [< pr_rawterm c >]
     else [<>]; 'fNL >]

let print_leaf_entry with_values sep (sp,lobj) =
  let tag = object_tag lobj in
  match (sp,tag) with
    | (_,"VARIABLE") ->
	print_section_variable sp
    | (_,("CONSTANT"|"PARAMETER")) ->
	print_constant with_values sep sp
    | (_,"INDUCTIVE") ->
	print_inductive sp
    | (_,"AUTOHINT") -> 
	[< 'sTR" Add Auto Marker"; 'fNL >]
    | (_,"GRAMMAR") -> 
	[< 'sTR" Grammar Marker"; 'fNL >]
    | (_,"SYNTAXCONSTANT") -> 
	print_syntactic_def with_values sep sp
    | (_,"PPSYNTAX") -> 
	[< 'sTR" Syntax Marker"; 'fNL >]
    | (_,"TOKEN") -> 
	[< 'sTR" Token Marker"; 'fNL >]
    | (_,"CLASS") -> 
	[< 'sTR" Class Marker"; 'fNL >]
    | (_,"COERCION") -> 
	[< 'sTR" Coercion Marker"; 'fNL >]
    | (_,s) -> 
	[< 'sTR(string_of_path sp); 'sTR" : ";
           'sTR"Unrecognized object "; 'sTR s; 'fNL >]

let rec print_library_entry with_values ent = 
  let sep = if with_values then " = " else " : " in 
  match ent with
    | (sp,Lib.Leaf lobj) -> 
	[< print_leaf_entry with_values sep (sp,lobj) >]
    | (_,Lib.OpenedSection (str,_)) -> 
        [< 'sTR(" >>>>>>> Section " ^ str); 'fNL >]
    | (sp,Lib.ClosedSection _) -> 
        [< 'sTR(" >>>>>>> Closed Section " ^ (string_of_id (basename sp)));
	   'fNL >]
    | (_,Lib.Module str) ->
	[< 'sTR(" >>>>>>> Module " ^ str); 'fNL >]
    | (_,Lib.FrozenState _) ->
	[< >]
	
and print_context with_values = 
  let rec prec = function
    | h::rest -> [< prec rest ; print_library_entry with_values h >]
    | [] -> [< >]
  in 
  prec

let print_full_context () = print_context true (Lib.contents_after None)

let print_full_context_typ () = print_context false (Lib.contents_after None)

(* For printing an inductive definition with
   its constructors and elimination,
   assume that the declaration of constructors and eliminations
   follows the definition of the inductive type *)

let list_filter_vec f vec = 
  let rec frec n lf = 
    if n < 0 then lf 
    else if f vec.(n) then 
      frec (n-1) (vec.(n)::lf)
    else 
      frec (n-1) lf
  in 
  frec (Array.length vec -1) []

let read_sec_context qid =
  let sp, _ = Nametab.locate_module qid in
  let rec get_cxt in_cxt = function
    | ((sp',Lib.OpenedSection (str,_)) as hd)::rest ->
        if sp' = sp then (hd::in_cxt) else get_cxt (hd::in_cxt) rest
    | [] -> []
    | hd::rest -> get_cxt (hd::in_cxt) rest 
  in
  let cxt = (Lib.contents_after None) in
  List.rev (get_cxt [] cxt)

let print_sec_context sec = print_context true (read_sec_context sec)

let print_sec_context_typ sec = print_context false (read_sec_context sec)

let print_val env {uj_val=trm;uj_type=typ} =
  print_typed_value_in_env env (trm,typ)
    
let print_type env {uj_val=trm;uj_type=typ} =
  print_typed_value_in_env env (trm, type_app (nf_betaiota env Evd.empty) typ)
    
let print_eval red_fun env {uj_val=trm;uj_type=typ} =
  let ntrm = red_fun env Evd.empty trm in
  [< 'sTR "     = "; print_type env {uj_val = ntrm; uj_type = typ} >]

let print_name qid = 
  try 
    let sp,_ = Nametab.locate_obj qid in
    let (sp,lobj) = 
      let (sp,entry) =
	List.find (fun en -> (fst en) = sp) (Lib.contents_after None)
      in
      match entry with
	| Lib.Leaf obj -> (sp,obj)
	| _ -> raise Not_found
    in
    print_leaf_entry true " = " (sp,lobj)
  with Not_found -> 
  try 
    match Nametab.locate qid with
      | ConstRef sp -> print_constant true " = " sp
      | IndRef (sp,_) -> print_inductive sp
      | ConstructRef ((sp,_),_) -> print_inductive sp
      | VarRef sp -> print_section_variable sp
      | EvarRef n -> [< 'sTR "?"; 'iNT n; 'fNL >]
  with Not_found -> 
  try  (* Var locale de but, pas var de section... donc pas d'implicits *)
    let dir,str = repr_qualid qid in 
    if dir <> [] then raise Not_found;
    let name = id_of_string str in
    let (c,typ) = Global.lookup_named name in 
    [< print_named_decl (name,c,typ) >]
  with Not_found ->
  try
    let sp = Syntax_def.locate_syntactic_definition qid in
    print_syntactic_def true " = " sp
  with Not_found ->
    errorlabstrm "print_name"
      [< pr_qualid qid; 'sPC; 'sTR "not a defined object" >]

let print_opaque_name qid = 
  let sigma = Evd.empty in
  let env = Global.env () in
  let sign = Global.named_context () in
  try 
    let x = global_qualified_reference qid in
    match kind_of_term x with
      | IsConst (sp,_ as cst) ->
	  let cb = Global.lookup_constant sp in
          if is_defined cb then
	    let typ = constant_type env Evd.empty cst in
            print_typed_value (constant_value env cst, typ)
          else 
	    anomaly "print_opaque_name"
      | IsMutInd ((sp,_),_) ->
          print_mutual sp (Global.lookup_mind sp)
      | IsMutConstruct cstr -> 
	  let ty = Typeops.type_of_constructor env sigma cstr in
	  print_typed_value (x, ty)
      | IsVar id ->
          let (c,ty) = lookup_named id env in 
	  print_named_decl (id,c,ty)
      | _ -> failwith "print_name"
  with Not_found -> 
    errorlabstrm "print_opaque" [< pr_qualid qid; 'sPC; 'sTR "not declared" >]

let print_local_context () =
  let env = Lib.contents_after None in
  let rec print_var_rec = function 
    | [] -> [< >]
    | (sp,Lib.Leaf lobj)::rest ->
	if "VARIABLE" = object_tag lobj then
          let (d,_,_) = get_variable sp in 
	  [< print_var_rec rest;
             print_named_decl d >]
	else 
	  print_var_rec rest
    | _::rest -> print_var_rec rest

  and print_last_const = function
    | (sp,Lib.Leaf lobj)::rest -> 
        (match object_tag lobj with
           | "CONSTANT" | "PARAMETER" -> 
               let {const_body=val_0;const_type=typ} = 
		 Global.lookup_constant sp in
               [< print_last_const rest;
                  print_basename sp ;'sTR" = ";
                  print_typed_body (val_0,typ) >]
           | "INDUCTIVE" -> 
               let mib = Global.lookup_mind sp in 
               [< print_last_const rest;print_mutual sp mib; 'fNL >]
           | "VARIABLE" ->  [< >]
           | _          ->  print_last_const rest)
    | _ -> [< >]
  in 
  [< print_var_rec env;  print_last_const env >]

let fprint_var name typ =
  [< 'sTR ("*** [" ^ name ^ " :"); fprtype typ; 'sTR "]"; 'fNL >]

let fprint_judge {uj_val=trm;uj_type=typ} = 
  [< fprterm trm; 'sTR" : " ; fprterm (body_of_type typ) >]

let unfold_head_fconst = 
  let rec unfrec k = match kind_of_term k with
    | IsConst cst -> constant_value (Global.env ()) cst 
    | IsLambda (na,t,b) -> mkLambda (na,t,unfrec b)
    | IsApp (f,v) -> appvect (unfrec f,v)
    | _ -> k
  in 
  unfrec

(* for debug *)
let inspect depth = 
  let rec inspectrec n res env = 
    if n=0 or env=[] then 
      res
    else 
      inspectrec (n-1) (List.hd env::res) (List.tl env)
  in 
  let items = List.rev (inspectrec depth [] (Lib.contents_after None)) in
  print_context false items


(*************************************************************************)
(* Pretty-printing functions coming from classops.ml                     *)

open Classops

let string_of_strength = function 
  | NeverDischarge -> "(global)"
  | DischargeAt sp -> "(disch@"^(string_of_dirpath sp)

let print_coercion_value v = prterm v.cOE_VALUE.uj_val

let print_index_coercion c = 
  let _,v = coercion_info_from_index c in
  print_coercion_value v

let print_class i =
  let cl,x = class_info_from_index i in
  [< 'sTR x.cL_STR >]
  
let print_path ((i,j),p) = 
  [< 'sTR"["; 
     prlist_with_sep (fun () -> [< 'sTR"; " >])
       (fun c ->  print_index_coercion c) p;
     'sTR"] : "; print_class i; 'sTR" >-> ";
     print_class j >]

let _ = Classops.install_path_printer print_path

let print_graph () = 
  [< prlist_with_sep pr_fnl print_path (inheritance_graph()) >]

let print_classes () = 
  [< prlist_with_sep pr_spc
       (fun (_,(cl,x)) -> 
          [< 'sTR x.cL_STR  (*; 'sTR(string_of_strength x.cL_STRE) *) >]) 
       (classes()) >]

let print_coercions () = 
  [< prlist_with_sep pr_spc
       (fun (_,(_,v)) -> [< print_coercion_value v >]) (coercions()) >]
  
let cl_of_id id = 
  match string_of_id id with
    | "FUNCLASS" -> CL_FUN
    | "SORTCLASS" -> CL_SORT
    | _ -> let v = Declare.global_reference CCI id in
	   let cl,_ = constructor_at_head v in 
	   cl

let index_cl_of_id id =
  try 
    let cl = cl_of_id id in
    let i,_=class_info cl in 
    i
  with _ -> 
    errorlabstrm "index_cl_of_id"
      [< 'sTR(string_of_id id); 'sTR" is not a defined class" >]

let print_path_between ids idt = 
  let i = (index_cl_of_id ids) in
  let j = (index_cl_of_id idt) in
  let p = 
    try 
      lookup_path_between (i,j) 
    with _ -> 
      errorlabstrm "index_cl_of_id"
        [< 'sTR"No path between ";'sTR(string_of_id ids); 
	   'sTR" and ";'sTR(string_of_id ids) >]
  in
  print_path ((i,j),p)

(*************************************************************************)
