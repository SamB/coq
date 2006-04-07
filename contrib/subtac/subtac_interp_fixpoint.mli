val mkAppExplC :
  Libnames.reference * Topconstr.constr_expr list -> Topconstr.constr_expr
val mkSubset :
  Names.name Util.located ->
  Topconstr.constr_expr -> Topconstr.constr_expr -> Topconstr.constr_expr
val mkProj1 :
  Topconstr.constr_expr ->
  Topconstr.constr_expr -> Topconstr.constr_expr -> Topconstr.constr_expr
val mkProj2 :
  Topconstr.constr_expr ->
  Topconstr.constr_expr -> Topconstr.constr_expr -> Topconstr.constr_expr
val list_of_local_binders :
  Topconstr.local_binder list ->
  (Names.name Util.located * Topconstr.constr_expr) list
val pr_binder_list :
  (('a * Names.name) * Topconstr.constr_expr) list -> Pp.std_ppcmds
val rewrite_rec_calls : 'a -> 'b -> 'b
val rewrite_fixpoint :
  'a ->
  'b ->
  (Names.identifier * (int * Topconstr.recursion_order_expr) *
   Topconstr.local_binder list * Topconstr.constr_expr *
   Topconstr.constr_expr) *
  'c ->
  (Names.identifier * (int * Topconstr.recursion_order_expr) *
   Topconstr.local_binder list * Topconstr.constr_expr *
   Topconstr.constr_expr) *
  'c
val list_mapi : (int -> 'a -> 'b) -> 'a list -> 'b list
val rewrite_cases_aux :
  Util.loc * Rawterm.rawconstr option *
  (Rawterm.rawconstr *
   (Names.name * (Util.loc * Names.inductive * Names.name list) option))
  list *
  (Util.loc * Names.identifier list * Rawterm.cases_pattern list *
   Rawterm.rawconstr)
  list -> Rawterm.rawconstr

val rewrite_cases : Environ.env -> Rawterm.rawconstr -> Rawterm.rawconstr
