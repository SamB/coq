(*i camlp4deps: "parsing/grammar.cma" i*)

(*s FunInv Tactic: inversion following the shape of a function.  *)
(* Use:
   \begin{itemize}
   \item The Tacinv directory must be in the path (-I <path> option)
   \item use the bytecode version of coqtop or coqc (-byte option), or make a
         coqtop 
   \item Do [Require Tacinv] to be able to use it.
   \item For syntax see Tacinv.v
   \end{itemize}
*)


(*i*)
open Termops
open Equality
open Names
open Pp
open Tacmach
open Proof_type
open Tacinterp
open Tactics
open Tacticals
open Term
open Util
open Printer
open Reductionops
open Inductiveops
open Coqlib
open Refine
open Typing
open Declare
open Decl_kinds
open Safe_typing
open Vernacinterp
open Evd
open Environ
open Entries
open Setoid_replace
open Tacinvutils
(*i*)

module Smap = Map.Make(struct type t = constr let compare = compare end)
let smap_to_list m = Smap.fold (fun c cb l -> (c,cb)::l) m []
let merge_smap m1 m2 = Smap.fold (fun c cb m -> Smap.add c cb m) m1 m2
let rec listsuf i l = if i<=0 then l else listsuf (i-1) (List.tl l)
let rec listpref i l = if i<=0 then [] else List.hd l :: listpref (i-1) (List.tl l)

let mkthesort = mkProp (* would like to put Type here, but with which index? *)

(*  this is the prefix used to name equality hypothesis generated by
    case analysis*)
let equality_hyp_string = "_eg_"

(* bug de refine: on doit ssavoir sur quelle hypothese on se trouve. valeur
   initiale au debut de l'appel a la fonction proofPrinc: 1. *)
let nthhyp = ref 1
 (*debugging*)
 (* let rewrules = ref [] *)
 (*debugging*)
let debug i = prstr ("DEBUG "^ string_of_int i ^"\n")
let pr2constr = (fun c1 c2 -> prconstr c1; prstr " <---> "; prconstr c2)
(* Operations on names *)
let id_of_name = function
    Anonymous -> id_of_string "H"
  | Name id   -> id;;
let string_of_name nme = string_of_id (id_of_name nme)
 (*end debugging *)

let constr_of c = Constrintern.interp_constr Evd.empty (Global.env()) c

let rec collect_cases l =
 match l with
  | [||] -> [||],[],[],[||],[||],[]
  | arr -> 
     let (a,c,d,f,e,g)= arr.(0) in
     let aa,lc,ld,_,_,_ = 
      collect_cases (Array.sub arr 1 ((Array.length arr)-1)) in
     Array.append [|a|] aa , (c@lc) , (d@ld) , f , e, g

let rec collect_pred l =
 match l with
  | [] -> [],[],[]
  | (e1,e2,e3)::l' -> let a,b,c = collect_pred l' in (e1::a),(e2::b),(e3::c)


(*s specific manipulations on constr *)
let lift1_leqs leq=
 List.map 
  (function (r,(typofg,g,d)) 
      -> lift 1 r, (lift 1 typofg, lift 1 g , lift 1 d)) leq

let lift1_relleqs leq= List.map (function (r,x) -> lift 1 r,x) leq

(* WARNING: In the types, we don't lift the rels in the type. This is
   intentional. Use with care. *)
let lift1_lvars lvars= List.map 
 (function x,(nme,c) -> lift 1 x, (nme, (*lift 1*) c)) lvars

let pop1_levar levars = List.map (function ev,tev -> ev, popn 1 tev) levars


let rec add_n_dummy_prod t n = 
 if n<=0 then t
 else add_n_dummy_prod (mkNamedProd (id_of_string "DUMMY") mkthesort t) (n-1)

(* [add_lambdas t gl [csr1;csr2...]] returns [[x1:type of csr1]
   [x2:type of csr2] t [csr <- x1 ...]], names of abstracted variables
   are not specified *)
let rec add_lambdas t gl lcsr =
 match lcsr with
  | [] -> t
  | csr::lcsr' -> 
     let hyp_csr,hyptyp = csr,(pf_type_of gl csr) in
     lambda_id hyp_csr hyptyp (add_lambdas t gl lcsr')

(* [add_pis t gl [csr1;csr2...]] returns ([x1] :type of [csr1]
   [x2]:type of csr2) [t]*)
let rec add_pis t gl lcsr =
 match lcsr with
  | [] -> t
  | csr::lcsr' -> 
     let hyp_csr,hyptyp = csr,(pf_type_of gl csr) in
     prod_id hyp_csr hyptyp (add_pis t gl lcsr')

let mkProdEg teq eql eqr concl =
 mkProd (name_of_string "eg", mkEq teq eql eqr, lift 1 concl)

let eqs_of_beqs x = 
 List.map (function (_,(a,b,c)) -> (Anonymous, mkEq a b c)) x


let rec eqs_of_beqs_named_aux s i l =
 match l with 
  | [] -> []
  | (r,(a,b,c))::l' -> 
     (Name(id_of_string (s^ string_of_int i)), mkEq a b c)
     ::eqs_of_beqs_named_aux s (i-1) l'


let eqs_of_beqs_named s l = eqs_of_beqs_named_aux s (List.length l) l

let rec patternify ltypes c nme =
 match ltypes with
  | [] -> c
  | (mv,t)::ltypes' -> 
     let c'= substitterm 0 mv (mkRel 1) c in
     let tlift = lift (List.length ltypes') t in
     let res = 
      patternify ltypes' (mkLambda (newname_append nme "rec", tlift, c')) nme in
     res

let rec npatternify ltypes c =
 match ltypes with
  | [] -> c
  | (mv,nme,t)::ltypes' -> 
     let c'= substitterm 0 mv (mkRel 1) c in
(*      let _ = prconstr c' in *)
     let tlift = lift (List.length ltypes') t in
     let res = 
      npatternify ltypes' (mkLambda (newname_append nme "", tlift, c')) in
(*      let _ = prconstr res in *)
     res

let rec apply_levars c lmetav =
 match lmetav with
  | [] -> [],c
  | (i,typ) :: lmetav' -> 
     let levars,trm = apply_levars c lmetav' in
     let exkey = mknewexist() in
     ((exkey,typ)::levars),  applistc trm [mkEvar exkey]
      (* EXPERIMENT le refine est plus long si on met un cast:
         ((exkey,typ)::levars), mkCast ((applistc trm [mkEvar exkey]),typ) *)


let prod_change_concl c newconcl = 
 let lv,_ = decompose_prod c in prod_it  newconcl lv

let lam_change_concl c newconcl = 
 let lv,_ = decompose_prod c in lam_it newconcl lv


let rec mkAppRel c largs n =
 match largs with
  | [] -> c
  | arg::largs' -> 
     let newc = mkApp (c,[|(mkRel n)|]) in mkAppRel newc largs' (n-1)

let applFull c typofc =
 let lv,t = decompose_prod typofc in 
 let ltyp = List.map fst lv in 
 let res = mkAppRel c ltyp (List.length ltyp) in
 res


let rec build_rel_map typ type_of_b = 
 match (kind_of_term typ), (kind_of_term type_of_b) with
    Evar _ , Evar _  -> Smap.empty
  | Rel i, Rel j -> if i=j then Smap.empty 
    else Smap.add typ type_of_b Smap.empty
  | Prod (name,c1,c2), Prod (nameb,c1b,c2b) -> 
     let map1 = build_rel_map c1 c1b in
     let map2 = build_rel_map (pop c2) (pop c2b) in
     merge_smap map1 map2
  | App (f,args), App (fb,argsb) ->
     (try build_rel_map_list (Array.to_list args) (Array.to_list argsb)
     with Invalid_argument _ -> 
      failwith ("Could not generate case annotation. "^ 
      "Two application with different length"))
  | Const c1, Const c2 -> if c1=c2 then Smap.empty
    else failwith ("Could not generate case annotation. "^ 
    "Two different constants in a case annotation.")
  | Ind c1, Ind c2 -> if c1=c2 then Smap.empty
    else failwith ("Could not generate case annotation. "^ 
    "Two different constants in a case annotation.")
  | _,_ -> failwith ("Could not generate case annotation. "^
    "Incompatibility between annotation and actual type")
and build_rel_map_list ltyp ltype_of_b =
 List.fold_left2 (fun a b c -> merge_smap a (build_rel_map b c))
  Smap.empty ltyp ltype_of_b


(*s Use (and proof) of the principle *)

(*
  \begin {itemize}
  \item [concl] ([constr]): conclusions, cad (xi:ti)gl, ou gl est le but a
  prouver, et xi:ti correspondent aux arguments donn�s � la tactique.  On
  enl�ve un produit � chaque fois qu'on rencontre un binder, sans lift ou pop.
  Initialement: une seule conclusion, puis specifique a chaque branche.
  \item[absconcl] ([constr array]): les conclusions (un predicat pour chaque
  fixp. mutuel) patternis�es pour  pouvoir �tre appliqu�es.
  \item [mimick] ([constr]): le terme qu'on imite. On plonge  dedans au fur et
  � mesure, sans lift ni pop.
  \item [nmefonc] ([constr array]): la constante correspondant � la fonction
  appel�e, permet de remplacer les appels recursifs par des appels � la
  constante correspondante (non pertinent (et inutile) si on permet l'appel de
  la tactique sur une terme donn� directement (au lieu d'une constante comme
  pour l'instant)).
  \item [fonc] ([int*int]) : bornes des indices des variable correspondant aux
  appels r�cursifs (plusieurs car fixp.  mutuels), utile pour reconna�tre les
  appels r�cursifs (ATTENTION: initialement vide, reste vide tant qu'on n'est
  pas dans un fix).  
  \end{itemize}
*)

type mimickinfo =
    {
     concl: constr;
     absconcl: constr array;
     mimick: constr;
     env: env;
     sigma: Evd.evar_map;
     nmefonc: constr array;
     fonc: int * int;
     doeqs: bool; (* this reference is to toggle building of equalities during
                    the building of the principle (default is true) *)
     fix: bool (* did I already went through a fix or case constr? lambdas
                  found before a case or a fix are treated as parameters of
                  the induction principle *)
    }

(*
  \begin{itemize}
  \item [lst_vars] ([(constr*(name*constr)) list]): liste des variables
  rencontr�es jusqu'� maintenant.
  \item [lst_eqs] ([constr list]): liste d'�quations engendr�es au cours du
  parcours, cette liste grandit � chaque case, et il faut lifter le tout �
  chaque binder.
  \item [lst_recs] ([constr list]): listes des appels r�cursifs rencontr�s
  jusque l�.
  \end{itemize}

  Cette fonction rends un nuplet de la forme:

  [t,
  [(ev1,tev1);(ev2,tev2)..],
  [(i1,j1,k1);(i2,j2,k2)..],
  [|c1;c2..|],
  [|typ1;typ2..|],
  [(param,tparam)..]]

 *)

(* This could be the return type of [proofPrinc], but not yet *)
type funind =
    {
     princ:constr;
     evarlist: (constr*Term.types) list;
     hypnum: (int*int*int) list;
     mutfixmetas: constr array ;
     conclarray: types array;
     params:(constr*name*constr) list
    }

(* 
  o�:

  \begin{itemize} 

  \item[t] est le principe demand�, il contient des meta variables
  repr�sentant soit des trous � prouver plus tard, soit les conclusions �
  compl�ter avant de rendre le terme (suivant qu'on utilise le principe pour
  faire refine ou functional scheme). Il y plusieurs conclusions si plusieurs
  fonction mutuellement r�cursives) voir la suite.

  \item[[(ev1,tev1);(ev2,tev2)...]] est l'ensemble des m�ta variables
  correspondant � des trous. [evi] est la meta variable, [tevi] est son type.

  \item[(in,jn,kn)] sont les nombres respectivement de variables, d'�quations,
  et d'hypoth�ses de r�currence pour le but n. Permet de faire le bon nombre
  d'intros et des rewrite au bons endroits dans la suite.

  \item[[|c1;c2...|]] est un tableau de meta variables correspondant � chacun
  des pr�dicats mutuellement r�cursifs construits.

  \item[[|typ1;typ2...|]] est un tableau contenant les conclusions respectives
  de chacun des pr�dicats mutuellement r�cursifs. Permet de finir la
  construction du principe.

  \item[[(param,tparam)..]] est la liste des param�tres (les lambda au-dessus
  du fix) du fixpoint si fixpoint il y a.

  \end{itemize}
*)
let heq_prefix = "H_eq_"

type kind_of_hyp = Var | Eq  (*| Rec*)

let rec proofPrinc mi lst_vars lst_eqs lst_recs:
 constr * (constr*Term.types) list * (int*int*int) list 
 * constr array * types array * (constr*name*constr) list =
 match kind_of_term mi.mimick with
    (* Fixpoint: we reproduce the Fix, fonc becomes (1,nbofmutf) to point on
       the name of recursive calls *) 
  | Fix((iarr,i),(narr,tarr,carr)) -> 

     (* We construct the right predicates for each mutual fixpt *)     
     let rec build_pred n =
      if n >= Array.length iarr then []
      else
        let ftyp = Array.get tarr n in
        let gl = mknewmeta() in
        let gl_app = applFull gl ftyp in
        let pis = prod_change_concl ftyp gl_app in
        let gl_abstr = lam_change_concl ftyp gl_app in
        (gl,gl_abstr,pis):: build_pred (n+1) in

     let evarl,predl,pisl = collect_pred (build_pred 0) in
     let newabsconcl = Array.of_list predl in
     let evararr = Array.of_list evarl in
     let pisarr = Array.of_list pisl in
     let newenv = push_rec_types (narr,tarr,carr) mi.env in

     let rec collect_fix n =
      if n >= Array.length iarr then [],[],[],[]
      else
        let nme = Array.get narr n in
        let c = Array.get carr n in
        (* rappelle sur le sous-terme, on ajoute un niveau de
           profondeur (lift) parce que Fix est un binder. *)
        let newmi = {mi with concl=(pisarr.(n)); absconcl=newabsconcl;
        mimick=c; fonc=(1,((Array.length iarr)));env=newenv;fix=true} in
        let appel_rec,levar,lposeq,_,evarrarr,parms = 
         proofPrinc newmi (lift1_lvars lst_vars) 
          (lift1_leqs lst_eqs) (lift1L lst_recs) in
        let lnme,lappel_rec,llevar,llposeq = collect_fix (n+1) in
        (nme::lnme),(appel_rec::lappel_rec),(levar@llevar), (lposeq@llposeq) in

     let lnme,lappel_rec,llevar,llposeq =collect_fix  0 in
     let lnme' = List.map (fun nme -> newname_append nme "_ind") lnme in
     let anme = Array.of_list lnme' in
     let aappel_rec = Array.of_list lappel_rec in
     (* llevar are put outside the fix, so one level of rel must be removed *)
     mkFix((iarr,i),(anme, pisarr,aappel_rec)),(pop1_levar llevar),llposeq,evararr,pisarr,[]

  (* <pcase> Cases b of arrPt end.*)
  | Case(cinfo, pcase, b, arrPt) -> 

     let prod_pcase,_ = decompose_lam pcase in
     let nmeb,lastprod_pcase = List.hd prod_pcase in
     let b'= apply_leqtrpl_t b lst_eqs in
     let type_of_b = Typing.type_of mi.env mi.sigma b in
     let new_lst_recs = lst_recs @ hdMatchSub_cpl b mi.fonc in
     (* Replace the calls to the function (recursive calls) by calls to the
        corresponding constant:  *)
     let d,f = mi.fonc in 
     let res = ref b' in
     let _ = for i = d to f do 
       res := substitterm 0 (mkRel i) mi.nmefonc.(f-i) !res done in
     let newb = !res in

     (* [fold_proof t l n] rend le resultat de l'appel recursif sur les
        elements de la liste l (correpsondant a arrPt), appele avec les bons
        arguments: [concl] devient [(DUMMY1:t1;...;DUMMY:tn)concl'], ou [n]
        est le nombre d'arguments du constructeur consid�r� (FIX: Hormis les
        parametres!!), et [concl'] est concl ou l'on a r��crit [b] en ($c_n$
        [rel1]...).*)

     let rec fold_proof nth_construct eltPt' =  
      (* mise a jour de concl pour l'interieur du case, concl'= concl[b <- C x3
         x2 x1... ], sans quoi les annotations ne sont plus coherentes *)
      let cstr_appl,nargs = nth_dep_constructor type_of_b nth_construct in
      let concl'' = 
       substitterm 0 (lift nargs b) cstr_appl (lift nargs mi.concl) in
      let neweq = mkEq type_of_b newb (popn nargs cstr_appl) in
      let concl_dummy = add_n_dummy_prod concl'' nargs in
      let lsteqs_rew = apply_eq_leqtrpl lst_eqs neweq in
      let new_lsteqs = 
       (mkRel (0-nargs),(type_of_b,newb, popn nargs cstr_appl))::lsteqs_rew in
      let a',a'' = decompose_lam_n nargs eltPt' in
      let newa'' = 
       if mi.doeqs 
       then mkLambda (name_of_string heq_prefix,lift nargs neweq,lift 1 a'') 
       else a'' in
      let newmimick = lamn nargs a' newa'' in
      let b',b'' = decompose_prod_n nargs concl_dummy in
      let newb'' = 
       if mi.doeqs 
       then mkProd (name_of_string heq_prefix,lift nargs neweq,lift 1 b'')
       else b'' in
      let newconcl = prodn nargs b' newb'' in
      let newmi = {mi with mimick=newmimick; concl=newconcl; fix=true} in
      let a,b,c,d,e,p = proofPrinc newmi lst_vars new_lsteqs new_lst_recs in
      a,b,c,d,e,p
      in
     
     let arrPt_proof,levar,lposeq,evararr,absc,_ = 
      collect_cases (Array.mapi fold_proof arrPt) in
     let prod_pcase,concl_pcase = decompose_lam pcase in
     let nme,typ = List.hd prod_pcase in
     let suppllam_pcase = List.tl prod_pcase in
     (* je remplace b par rel1 (apres avoir lifte un coup) dans la
        future annotation du futur case: ensuite je mettrai un lambda devant *)
     let typesofeqs' = eqs_of_beqs_named equality_hyp_string lst_eqs in
     (*      let typesofeqs = prod_it_lift typesofeqs' mi.concl in *)
     let typesofeqs = mi.concl in
     let typeof_case'' = 
      substitterm 0 (lift 1 b) (mkRel 1) (lift 1 typesofeqs) in
     
     (* C'est un peu compliqu� ici: en cas de type inductif vraiment d�pendant
        le piquant du case [pcase] contient des lambdas suppl�mentaires en t�te
        je les ai dans la variable [suppllam_pcase]. Le probl�me est que la
        conclusion du piquant doit faire r�f�rence � ces variables plut�t qu'�
        celle de l'exterieur. Ce qui suit permet de changer les reference de
        newpacse' pour pointer vers les lambda du piquant. On proc�de comme
        suit: on rep�re les rels qui pointent � l'interieur du piquant dans la
        fonction imit�e, pour �a on parcourt le dernier lambda du piquant (qui
        contient le type de l'argument du case), et on remplace les rels
        correspondant dans la preuve construite. *)
     
     (* typ vient du piquant, type_of_b vient du typage de b.*)
     
     let rel_smap = 
      if List.length suppllam_pcase=0 then Smap.empty else
        build_rel_map (lift (List.length suppllam_pcase) type_of_b) typ in
     let rel_map = smap_to_list rel_smap in
     let rec substL l c =
      match l with
         [] -> c
       | ((e,e') ::l') -> substL l' (substitterm 0 e (lift 1 e') c) in
     let newpcase' = substL rel_map typeof_case'' in
     let neweq = mkEq (lift (List.length suppllam_pcase + 1) type_of_b) 
      (lift (List.length suppllam_pcase + 1) newb) (mkRel 1) in
     let newpcase = 
      if mi.doeqs then
        mkProd (name_of_string "eg", neweq, lift 1 newpcase') else newpcase'
     in
     (* construction du dernier lambda du piquant. *)
     let typeof_case' = mkLambda (newname_append nme "_ind" ,typ, newpcase) in
     (* ajout des lambdas suppl�mentaires (type d�pendant) du piquant. *)
     let typeof_case = 
      lamn (List.length suppllam_pcase) suppllam_pcase typeof_case' in 
     let trm' = mkCase (cinfo,typeof_case,newb, arrPt_proof) in
     let trm = 
      if mi.doeqs then mkApp (trm',[|(mkRefl type_of_b newb)|]) 
      else trm' in
     trm,levar,lposeq,evararr,absc,[] (* fix parms here (fix inside case)*)
      
  | Lambda(nme, typ, cstr) ->
     let _, _, cconcl = destProd mi.concl in
     let d,f=mi.fonc in
     let newenv = push_rel (nme,None,typ) mi.env in
     let newmi = {mi with concl=cconcl; mimick=cstr; env=newenv;
      fonc=((if d > 0 then d+1 else 0),(if f > 0 then f+1 else 0))} in
     let newlst_var = (* if this lambda is a param, then don't add it here *)
      if mi.fix then (mkRel 1,(nme,typ)) :: lift1_lvars lst_vars
      else (*(mkRel 1,(nme,typ)) :: *) lift1_lvars lst_vars in
     let rec_call,levar,lposeq,evararr,absc,parms =
      proofPrinc newmi newlst_var (lift1_leqs lst_eqs) (lift1L lst_recs) in
     (* are we inside a fixpoint or a case? then this is a normal lambda *)
     if mi.fix then mkLambda (nme,typ,rec_call) , levar, lposeq,evararr,absc,[]
     else (* otherwise this is a parameter *)
       let metav = mknewmeta() in
       let substmeta t = popn 1 (substitterm 0 (mkRel 1) metav t) in
       let newrec_call = substmeta rec_call in
       let newlevar = List.map (fun ev,tev -> ev, substmeta tev) levar in
       let newabsc = Array.map substmeta absc in
       newrec_call,newlevar,lposeq,evararr,newabsc,((metav,nme, typ)::parms)

  | LetIn(nme,cstr1, typ, cstr) ->
     failwith ("I don't deal with let ins yet. "^
				 "Please expand them before applying this function.")

  | u -> 
     let varrels = List.rev (List.map fst lst_vars) in
     let varnames = List.map snd lst_vars in
     let nb_vars = (List.length varnames) in
     let nb_eqs = (List.length lst_eqs) in
     let eqrels = List.map fst lst_eqs in
     (* [terms_recs]: appel rec du fixpoint, On concat�ne les appels recs
        trouv�s dans les let in et les Cases. *)
     (* TODO: il faudra g�rer plusieurs pt fixes imbriqu�s ? *)
     let terms_recs = lst_recs @ (hdMatchSub_cpl mi.mimick mi.fonc)  in
     
     (*c construction du terme: application successive des variables, des
       egalites et des appels rec, a la variable existentielle correspondant a
       l'hypothese de recurrence en cours. *)
     (* d'abord, on fabrique les types des appels recursifs en replacant le nom
        de des fonctions par les predicats dans [terms_recs]: [(f_i t u v)]
        devient [(P_i t u v)] *)
     (* TODO optimiser ici: *)
     let appsrecpred = exchange_reli_arrayi_L mi.absconcl mi.fonc terms_recs in
     let typeofhole''  = prod_it_anonym_lift mi.concl appsrecpred in
     let typeofhole    = prodn nb_vars varnames typeofhole'' in
		   
     (* Un bug de refine m'oblige � mettre ici un H (meta variable � ce point,
        mais remplac� par H avant le refine) au lieu d'un '?', je mettrai les
        '?'  � la fin comme �a [(([H1,H2,H3...] ...) ? ? ?)] *)

     let newmeta = mknewmeta() in
     let concl_with_var = applistc newmeta varrels in
     let conclrecs = applistc concl_with_var terms_recs in
     conclrecs,[newmeta,typeofhole], [nb_vars,(List.length terms_recs)
      ,nb_eqs],[||],mi.absconcl,[]



let mkevarmap_aux ex = let x,y = ex in	(mkevarmap_from_listex x),y

(* Interpretation of constr's *)
let constr_of_Constr c = Constrintern.interp_constr Evd.empty (Global.env()) c


(* TODO: deal with any term, not only a constant. *)
let interp_fonc_tacarg fonctac gl =
 (* [fonc] is the constr corresponding to fontact not unfolded,
    if [fonctac] is a (qualified) name then this is a [const] ?. *)
(*  let fonc = constr_of_Constr fonctac in *)
 (* TODO: replace the [with _ -> ] by something more precise in
    the following. *)
 (* [def_fonc] is the definition of fonc. TODO: We should do this only
    if [fonc] is a const, and take [fonc] otherwise.*)
 try fonctac, pf_const_value gl (destConst fonctac)
 with _ -> failwith ("don't know how to deal with this function "
 ^"(DEBUG:is it a constante?)")




(* [invfun_proof fonc  def_fonc  gl_abstr pis]  builds  the principle,
   following  the shape  of   [def_fonc],    [fonc]  is the      constant
   corresponding to [def_func] (or a reduced form of  it ?), gl_abstr and
   pis are the goal to be proved, of the form [x,y...]g and (x.y...)g.

   This function calls the big function proofPrinc. *)

let invfun_proof fonc def_fonc gl_abstr pis env sigma =
 let mi = {concl=pis; absconcl=gl_abstr; mimick=def_fonc; env=env;
 sigma=sigma; nmefonc=fonc; fonc=(0,0); doeqs=true; fix=false} in
 let princ_proof,levar,lposeq,evararr,absc,parms = proofPrinc mi [] [] [] in
 princ_proof,levar,lposeq,evararr,absc,parms

(* Do intros [i] times, then do rewrite on all introduced hyps which are called
   like [heq_prefix], FIX: have another filter than the name. *)
let rec iterintro i = 
 if i<=0 then tclIDTAC else 
   tclTHEN
    (tclTHEN 
     intro
     (iterintro (i-1)))
    (fun gl -> 
     (tclREPEAT 
      (tclNTH_HYP i
       (fun hyp -> 
        let hypname = (string_of_id (destVar hyp)) in
        let sub = 
         try String.sub hypname 0 (String.length heq_prefix)
         with _ -> "" (* different than [heq_prefix] *) in
        if sub=heq_prefix then rewriteLR hyp else tclFAIL 0 "Cannot rewrite")
      )) gl)


(* 
       (fun hyp gl -> 
        let _ = print_string ("nthhyp= "^ string_of_int i) in
        if isConst hyp && ((name_of_const hyp)==heq_prefix) then
          let _ = print_string "YES\n" in
          rewriteLR hyp gl 
        else 
          let _ = print_string "NO\n" in
          tclIDTAC gl)
 *)
    
(* [invfun_basic C listargs_ids gl dorew lposeq] builds the tactic
   which:
   \begin{itemize}
   \item Do refine on C (the induction principle),
   \item try to Clear listargs_ids
   \item if boolean dorew is true, then intro all new hypothesis, and
   try rewrite on those hypothesis that are equalities.
   \end{itemize}
*)

let invfun_basic open_princ_proof_applied listargs_ids gl dorew lposeq =
 (tclTHEN_i
  (tclTHEN
   (tclTHEN
    (* Refine on the right term (following the sheme of the
       given function) *)
    (fun gl -> refine open_princ_proof_applied  gl)
    (* Clear the hypothesis given as arguments of the tactic
       (because they are generalized) *)
    (tclTHEN simpl_in_concl (tclTRY (clear listargs_ids))))
   (* Now we introduce the created hypothesis, and try rewrite on
      equalities due to case analysis *)
   (fun gl ->  (tclIDTAC gl)))
		(fun i gl -> 
   if not dorew then tclIDTAC gl
   else
     (* d,m,f correspond respectively to vars, induction hyps and
        equalities*)
     let d,m,f = List.nth lposeq (i-1) in
     tclTHEN (iterintro (d)) (tclDO m (tclTRY intro)) gl)
 )
 gl




(* This function trys to reduce instanciated arguments, provided they
   are of the form [(C t u v...)] where [C] is a constructor, and
   provided that the argument is not the argument of a fixpoint (i.e. the
   argument corresponds to a simple lambda) . *)
let rec applistc_iota cstr lcstr env sigma = 
 match lcstr with
  | [] -> cstr,[]
  | arg::lcstr' -> 
     let arghd = 
      if isApp arg then let x,_ = destApplication arg in x else arg in
     if isConstruct arghd (* of the form [(C ...)]*)
     then 
        applistc_iota (Tacred.nf env sigma (nf_beta (applistc cstr [arg])))
         lcstr' env sigma
     else 
       try 
        let nme,typ,suite = destLambda cstr in
        let c, l = applistc_iota suite lcstr' env sigma in
        mkLambda (nme,typ,c), arg::l
       with _ -> cstr,arg::lcstr' (* the arg does not correspond to a lambda*)



(* TODO: ne plus mettre les sous-but � l'exterieur, mais � l'int�rieur (le bug
   de refine est normalement resolu). Ca permettra 2 choses: d'une part que
   les preuves soient plus simple, et d'autre part de fabriquer un terme de
   refine qui pourra s'aapliquer SANS FAIRE LES INTROS AVANT, ce qui est bcp
   mieux car fonctionne comme induction et plus comme inversion (pas de perte
   de connexion entre les hypoth�se et les variables). *)

(*s Tactic that makes induction and case analysis following the shape
  of a function (idf) given with arguments (listargs) *)
let invfun c l dorew gl = 
(* \begin{itemize}
    \item [fonc] = the constant corresponding to the function
    (necessary for equalities of the form [(f x1 x2 ...)=...] where
    [f] is the recursive function).
    \item [def_fonc] = body of the function, where let ins have
    been expanded. *)
 let fonc, def_fonc' = interp_fonc_tacarg c gl in
 let def_fonc'',listargs' = 
  applistc_iota def_fonc' l (pf_env gl) (project gl)  in
 let def_fonc = expand_letins def_fonc'' in
 (* quantifies on previously generalized arguments. 
    [(x1:T1)...g[arg1 <- x1 ...]] *)
 let pis = add_pis (pf_concl gl) gl listargs' in
 (* princ_proof builds the principle *)
 let _ = resetmeta() in
 let princ_proof,levar, lposeq,evararr,_,parms = 
  invfun_proof [|fonc|] def_fonc [||] pis (pf_env gl) (project gl) in

 (* Generalize the goal. [[x1:T1][x2:T2]... g[arg1 <- x1 ...]]. *)
 let gl_abstr' = add_lambdas (pf_concl gl) gl listargs' in
 (* apply parameters immediately *)
 let gl_abstr = applistc gl_abstr' (List.map (fun x,y,z -> x) (List.rev parms)) in

 (* we apply args of the fix now, the parameters will be applied later *)
 let princ_proof_applied_args = 
  applistc princ_proof (listsuf (List.length parms) listargs') in

 (* parameters are still there so patternify must not take them -> lift *)
 let princ_proof_applied_lift = 
  lift (List.length levar) princ_proof_applied_args in

 let princ_applied_hyps'' = patternify (List.rev levar)
  princ_proof_applied_lift (Name (id_of_string "Hyp"))  in
 (* if there was a fix, we will not add "Q" as in funscheme, so we make a pop,
    TODO: find were we made the lift in proofPrinc instead and supress it here,
    and add lift in funscheme. *)
 let princ_applied_hyps' = 
  if Array.length evararr > 0 then popn 1 princ_applied_hyps''
  else princ_applied_hyps'' in
 
 let princ_applied_hyps = 
  if Array.length evararr > 0 then (* mutual Fixpoint not treated in the tactic *) 
     (substit_red 0 (evararr.(0)) gl_abstr princ_applied_hyps')
  else princ_applied_hyps' (* No Fixpoint *) in
 let _ = prNamedConstr "princ_applied_hyps" princ_applied_hyps in

 (* replace params metavar by real args *)
 let rec replace_parms lparms largs t = 
  match lparms, largs with
     [], _ -> t
   | ((p,_,_)::lp), (a::la) -> let t'= substitterm 0 p a t in replace_parms lp la t'
   | _, _ -> error "problem with number of args." in
 let princ_proof_applied = replace_parms parms listargs' princ_applied_hyps in


(*
 (* replace params metavar by abstracted variables *)
  let princ_proof_params = npatternify (List.rev parms) princ_applied_hyps in
 (* we apply now the real parameters *)
 let princ_proof_applied = 
  applistc princ_proof_params (listpref (List.length parms) listargs') in
*)



 let princ_applied_evars = apply_levars princ_proof_applied levar in
 let open_princ_proof_applied = princ_applied_evars in
 let listargs_ids = List.map destVar (List.filter isVar listargs') in
 invfun_basic (mkevarmap_aux open_princ_proof_applied) listargs_ids 
  gl dorew lposeq

(* function must be a constant, all arguments must be given. *)
let invfun_verif c l dorew gl =
 if not (isConst c) then error "given function is not a constant"
 else 
   let x,_ = decompose_prod (pf_type_of gl c) in
   if List.length x = List.length l then 
     try invfun c l dorew gl
     with 
        UserError (x,y) -> raise (UserError (x,y))
   else error "wrong number of arguments for the function"


TACTIC EXTEND FunctionalInduction
  [ "Functional" "Induction" constr(c)  ne_constr_list(l) ] 
     -> [ invfun_verif c l true ]
END



(* Construction of the functional scheme. *)
let buildFunscheme fonc mutflist =
 let def_fonc = expand_letins (def_of_const fonc) in
 let ftyp = type_of (Global.env ()) Evd.empty fonc in
 let _ = resetmeta() in
 let gl = mknewmeta() in
 let gl_app = applFull gl ftyp in
 let pis = prod_change_concl ftyp gl_app in
 (* Here we call the function invfun_proof, that effectively 
    builds the scheme *)
 let princ_proof,levar,_,evararr,absc,parms = 
  invfun_proof mutflist def_fonc [||] pis (Global.env()) Evd.empty in
 (* parameters are still there (unboud rel), and patternify must not take them
  -> lift*)
 let princ_proof_lift = lift (List.length levar) princ_proof in
 let princ_proof_hyps = 
  patternify (List.rev levar) princ_proof_lift (Name (id_of_string "Hyp"))  in
 let rec princ_replace_metas ev abs i t = 
  if i>= Array.length ev then t
  else (* fix? *)
    princ_replace_metas ev abs (i+1)
     (mkLambda (
      (Name (id_of_string ("Q"^(string_of_int i)))),
      prod_change_concl (lift 0 abs.(i)) mkthesort,
      (substitterm 0 ev.(i) (mkRel 1) (lift 0 t))))
 in
 let rec princ_replace_params params t = 
  List.fold_left (
   fun acc ev,nam,typ -> 
    mkLambda (Name (id_of_name nam) , typ, 
    substitterm 0 ev (mkRel 1) (lift 0 acc)))
   t params in
 if Array.length evararr = 0 (* Is there a Fixpoint? *)
	then (* No Fixpoint *)
   princ_replace_params parms (mkLambda ((Name (id_of_string "Q")), 
		 prod_change_concl ftyp mkthesort,
   (substitterm 0 gl (mkRel 1) princ_proof_hyps)))
	else (* there is a fix -> add parameters + replace metas *)
   let princ_rpl = princ_replace_metas evararr absc 0 princ_proof_hyps in
   princ_replace_params parms princ_rpl


    
(* Declaration of the functional scheme. *)
let declareFunScheme f fname mutflist =
 let scheme = 
   buildFunscheme (constr_of f) 
    (Array.of_list (List.map constr_of (f::mutflist))) in
  let _ = prstr "Principe:" in
  let _ = prconstr scheme in
 let ce = { 
  const_entry_body = scheme;
  const_entry_type = None;
  const_entry_opaque = false } in
 let _= ignore (declare_constant fname (DefinitionEntry ce,IsDefinition)) in
 ()



VERNAC COMMAND EXTEND FunctionalScheme
 [ "Functional" "Scheme" ident(na) ":=" "Induction" "for" 
    constr(c) "with" ne_constr_list(l) ]
  -> [ declareFunScheme c na l ]
| [ "Functional" "Scheme" ident(na) ":=" "Induction" "for" constr(c) ]
  -> [ declareFunScheme c na [] ]
END

 



(* 
*** Local Variables: ***
*** compile-command: "make -C ../.. contrib/funind/tacinv.cmo" ***
*** tab-width: 1 ***
*** tuareg-default-indent:1 ***
*** tuareg-begin-indent:1 ***
*** tuareg-let-indent:1 ***
*** tuareg-match-indent:-1 ***
*** tuareg-try-indent:1 ***
*** tuareg-with-indent:1 ***
*** tuareg-if-then-else-inden:1 ***
*** fill-column: 78 ***
*** indent-tabs-mode: nil ***
***  test-tactic: "../../bin/coqtop -translate -q -batch -load-vernac-source ../../test-suite/success/Funind.v" ***
*** End: ***
*)
          

