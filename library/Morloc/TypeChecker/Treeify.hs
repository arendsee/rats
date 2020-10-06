{-|
Module      : Morloc.TypeChecker.Treeify
Description : I am groot
Copyright   : (c) Zebulun Arendsee, 2020
License     : GPL-3
Maintainer  : zbwrnz@gmail.com
Stability   : experimental
-}

module Morloc.TypeChecker.Treeify (treeify) where

import Morloc.Namespace
import Morloc.Data.Doc
import Morloc.TypeChecker.PartialOrder
import Morloc.Pretty (prettyModule)
import qualified Morloc.Data.Text as MT
import qualified Morloc.Monad as MM
import qualified Data.Map as Map
import qualified Data.Set as Set


-- | Store all necessary information about a particular implementation of a
-- term.  A term may either be declared or sourced. If declared, the left and
-- right hand sides of the declaration are stored. If sourced, the Source
-- object is stored. In either case, the module where the term is defined is
-- also stored.
data TermOrigin = Declared Module EVar Expr | Sourced Module Source
  deriving(Show, Ord, Eq)

treeify :: [Module] -> MorlocMonad [SAnno GMeta Many [CType]]
treeify ms = do
  -- initialize state counter to 0, used to index manifolds
  MM.startCounter

  -- modmap :: Map.Map MVar Module
  let modmap = Map.fromList [(moduleName m, m) | m <- ms]

  -- pretty print modules to $MORLOC_HOME/tmp/mods.txt
  MM.logFileWith "mods.txt" (MT.unpack . render . vsep . map prettyModule) ms

  -- find each term that is exported to the nexus
  roots modmap   -- [(EVar, [TermOrigin])]
    -- turn each term into an ambiguous call tree
    >>= mapM (collect modmap)   -- [SAnno GMeta Many [CType]]


-- | Find the expressions that are exposed to the user.
-- Each element of the returned list consists of an EVar that is the term
-- exported from the main module. This term may be a named composition in the
-- main module, a sourced function/value from language-specific code, or an
-- imported term from another module. A term may be defined in multiple modules
-- or sourced from multiple implementations. Thus each term exported from main
-- is associated with a list of possible implementations/realizations.
roots :: Map.Map MVar Module -> MorlocMonad [(EVar, [TermOrigin])]
roots ms = do
  xs <- case roots of
    [m] ->
      let vs = Set.toList (moduleExports m) in
        return $ zip vs (map (findTerm False ms m) vs)
    [] -> MM.throwError CyclicDependency
    ms -> MM.throwError . GeneratorError $
          ("Multiple root modules: " <> render (vsep $ map prettyModule ms) <> MT.show' allImports)

  return xs
  where
    isRoot m = not $ Set.member (moduleName m) allImports
    allImports = Set.fromList . map importModuleName . concat . map moduleImports . Map.elems $ ms
    roots = filter isRoot (Map.elems ms)


-- | Build the call tree for a single nexus command. The result is ambiguous,
-- with 1 or more possible tree topologies, each with one or more possible for
-- each function.
collect
  :: Map.Map MVar Module
  -> (EVar, [TermOrigin])
  -> MorlocMonad (SAnno GMeta Many [CType])
collect ms (v, []) = MM.throwError . GeneratorError $
  "No origin found for variable '" <> unEVar v <> "'"
collect ms (evar', xs@(x:_)) = do
  -- Just look at one x, since any should emit the same GMeta (if not, then
  -- something is broken upstream of GMeta is not general enough)
  gmeta <- makeGMeta (Just evar') (getTermModule x) Nothing
  trees <- mapM collectTerm xs
  return $ SAnno (Many trees) gmeta
  where

    -- Notice that `args` is NOT an input to collectTerm. Morloc uses lexical
    -- scoping, and the input to collectTerm is the origin of a term, so the
    -- definition of the term is outside the scope of the parent expression.
    collectTerm
      :: TermOrigin
      -> MorlocMonad (SExpr GMeta Many [CType], [CType])
    collectTerm (Declared m _ (AnnE x ts)) = do
      xs <- collectExpr Set.empty m (getCTypes ts) x
      case xs of
        [x] -> return x
        _ -> MM.throwError . GeneratorError $
          "Expected exactly one topology for a declared term"
    collectTerm (Declared _ _ _) = MM.throwError . GeneratorError $
      "Invalid expression in CollectTerm Declared, expected AnnE"
    collectTerm term@(Sourced m src) = do
      ts <- getTermTypes term |>> getCTypes
      return (CallS src, ts)
      where
        getTermTypes :: TermOrigin -> MorlocMonad [Type]
        getTermTypes t = do
          (TypeSet _ es) <- getTermTypeSet t
          return $ [etype e | e <- es, Just (srcLang src) == langOf e]

    collectAnno
      :: Set.Set EVar
      -> Module
      -> Expr
      -> MorlocMonad (SAnno GMeta Many [CType])
    collectAnno args m (AnnE e ts) = do
      gtype <- getGType ts
      gmeta <- makeGMeta (getExprName e) m gtype
      trees <- collectExpr args m (getCTypes ts) e
      return $ SAnno (Many trees) gmeta
    collectAnno _ _ _ = error "impossible bug - unannotated expression"

    getExprName :: Expr -> Maybe EVar
    getExprName (VarE v) = Just v
    getExprName _ = Nothing

    collectExpr
      :: Set.Set EVar
      -> Module
      -> [CType]
      -> Expr
      -> MorlocMonad [(SExpr GMeta Many [CType], [CType])]
    collectExpr args m ts (UniE) = return [(UniS, ts)]
    collectExpr args m ts (NumE x) = return [(NumS x, ts)]
    collectExpr args m ts (LogE x) = return [(LogS x, ts)]
    collectExpr args m ts (StrE x) = return [(StrS x, ts)]
    collectExpr args m ts (VarE v)
      | Set.member v args = return [(VarS v, ts)]
      | otherwise = do
          let terms = findTerm True ms m v
          xs <- mapM collectTerm terms
          let chosen = map (chooseTypes ts) xs
          return chosen
      where
        -- FIXME: The typesystem should handle this. It should unroll every
        -- type as far as it can be unrolled, and infer specialized types all
        -- the way down. Multiple declarations of every term within a given
        -- language should be allowed. The function below will only work in
        -- special cases where there is A) a single instance of the term in
        -- each language and B) types beneath the term (if this is a
        -- composition) do not depend on the type on top.
        chooseTypes
          :: [CType]
          -> (SExpr GMeta Many [CType], [CType])
          -> (SExpr GMeta Many [CType], [CType])
        chooseTypes ts (x, ts') =
          (x, [ t
              | t <- ts
              , t' <- ts'
              , langOf t == langOf t'])
    collectExpr args m ts (ListE es) = do
      es' <- mapM (collectAnno args m) es
      return [(ListS es', ts)]
    collectExpr args m ts (TupleE es) = do
      es' <- mapM (collectAnno args m) es
      return [(TupleS es', ts)]
    collectExpr args m ts (RecE entries) = do
      es' <- mapM (collectAnno args m) (map snd entries)
      let entries' = zip (map fst entries) es'
      return [(RecS entries', ts)]
    collectExpr args m ts e@(LamE v x) =
      case unrollLambda e of
        (args', e') -> do
          -- say $ "in LamE:" <+> prettyExpr x
          e'' <- collectAnno (Set.union args (Set.fromList args')) m e'
          return [(LamS args' e'', ts)]
    -- AppS (SAnno g f c) [SAnno g f c]
    collectExpr args m ts (AppE e1 e2) = do
      -- say $ "in AppE:" <+> parens (prettyExpr e1) <+> parens (prettyExpr e2)
      -- The topology of e1' may vary. It could be a direct binary function. Or
      -- it could be a partially applied function. So it is necessary to map
      -- over the Many.
      e1'@(SAnno (Many fs) g1) <- collectAnno args m e1
      e2' <- collectAnno args m e2
      -- say $ "in AppE e1':" <+> writeManyAST e1'
      -- say $ "in AppE e2':" <+> writeManyAST e2'
      mapM (app g1 e2') fs

    collectExpr _ _ _ _ = MM.throwError . GeneratorError $
      "Unexpected expression in collectExpr"
    app
      :: GMeta
      -> SAnno GMeta Many [CType]
      -> (SExpr GMeta Many [CType], [CType])
      -> MorlocMonad (SExpr GMeta Many [CType], [CType])
    app _ e2 ((AppS f es), ts) = do
      ts' <- mapM partialApplyConcrete ts
      return (AppS f (es ++ [e2]), ts')
    app g e2 (f, ts) = do
      ts' <- mapM partialApplyConcrete ts
      return (AppS (SAnno (Many [(f, ts)]) g) [e2], ts')

    partialApplyConcrete :: CType -> MorlocMonad CType
    partialApplyConcrete t =
      fmap CType $ partialApply (unCType t)


-- | Find info common across realizations of a given term in a given module
makeGMeta :: Maybe EVar -> Module -> Maybe GType -> MorlocMonad GMeta
makeGMeta name m gtype = do
  i <- MM.getCounter
  case name >>= (flip Map.lookup) (moduleTypeMap m) of
    (Just (TypeSet (Just e) _)) -> do
      return $ GMeta
        { metaId = i
        , metaName = name
        , metaGType = maybe (Just . GType $ etype e) Just gtype
        , metaProperties = eprop e
        , metaConstraints = econs e
        }
    _ -> do
      return $ GMeta
        { metaId = i
        , metaName = name
        , metaGType = gtype
        , metaProperties = Set.empty
        , metaConstraints = Set.empty
        }


getTermModule :: TermOrigin -> Module
getTermModule (Sourced m _) = m
getTermModule (Declared m _ _) = m


getTermEVar :: TermOrigin -> EVar
getTermEVar (Sourced _ src) = srcAlias src
getTermEVar (Declared _ v _) = v


getTermTypeSet :: TermOrigin -> MorlocMonad TypeSet
getTermTypeSet t =
  case Map.lookup (getTermEVar t) (moduleTypeMap (getTermModule t)) of
    (Just ts) -> return ts
    Nothing -> MM.throwError . GeneratorError $ "Expected the term to have a typeset"


unrollLambda :: Expr -> ([EVar], Expr)
unrollLambda (LamE v e2) = case unrollLambda e2 of
  (vs, e) -> (v:vs, e)
unrollLambda (AnnE (LamE v e2) _) = case unrollLambda e2 of
  (vs, e) -> (v:vs, e)
unrollLambda e = ([], e)


getGType :: [Type] -> MorlocMonad (Maybe GType)
getGType ts = case [GType t | t <- ts, isNothing (langOf t)] of
  [] -> return Nothing
  [x] -> return $ Just x
  xs -> MM.throwError . GeneratorError $
    "Expected 0 or 1 general types, found " <> MT.show' (length xs)


getCTypes :: [Type] -> [CType]
getCTypes ts = [CType t | t <- ts, isJust (langOf t)]


partialApply :: Type -> MorlocMonad Type
partialApply (FunT _ t) = return t
partialApply (Forall v t) = do
  t' <- partialApply t
  return $ if varIsUsed v t' then Forall v t' else t'
  where
    varIsUsed :: TVar -> Type -> Bool
    varIsUsed v (VarT v') = v == v'
    varIsUsed v (ExistT v' ts ds)
      =  v == v'
      || any (varIsUsed v) ts
      || any (varIsUsed v) (map unDefaultType ds)
    varIsUsed v (Forall v' t)
      | v == v' = False
      | otherwise = varIsUsed v t
    varIsUsed v (FunT t1 t2) = varIsUsed v t1 || varIsUsed v t2
    varIsUsed v (ArrT v' ts) = any (varIsUsed v) ts
    varIsUsed v (NamT v' entries) = any (varIsUsed v) (map snd entries)
partialApply _ = MM.throwError . GeneratorError $
  "Cannot partially apply a non-function type"


partialApplyN :: Int -> Type -> MorlocMonad Type
partialApplyN i t
  | i < 0 = MM.throwError . GeneratorError $
    "Do you really want to apply a negative number of arguments?"
  | i == 0 = return t
  | i > 0 = do
    appliedType <- partialApply t
    partialApplyN (i-1) appliedType


{- | Find exported expressions.

Terms may be declared or sourced in the current module or they may be imported
from a different module. If they are imported, ascend through modules to the
original declaration, returning the module where they are defined.

For each input term (EVar) a list is returned. Each element in the list
describes a specific implementation of the term. These implementations may have
different topologies and languages. A given language may have more than one
implementation. However, all implementations share the same general type.

Each element in the return list is a tuple of two values. The module where the
term is exported and the source/declaration information needed to uniquely
specify it (within an Either monad). If the term is sourced, then a (Left
Source) data constructor holds the required source information. If the term is
declared, a (EVar, Expr) tuple stores the left and right sides of a declaration
(the same information that is stored in the Declaration data constructor of
Expr).
-}
findTerm
  :: Bool -- ^ should non-exported terms be included?
  -> Map.Map MVar Module
  -> Module -- ^ a module where EVar is used
  -> EVar -- ^ the variable name in the top level module
  -> [TermOrigin]
findTerm includeInternal ms m v
  | includeInternal || Set.member v (moduleExports m)
      = evarDeclared
      ++ evarSourced
      ++ evarImported
  | otherwise = []
  where
    evarDeclared :: [TermOrigin]
    evarDeclared = concat [findDecl e | (Declaration v' e) <- moduleBody m, v' == v]

    findDecl :: Expr -> [TermOrigin]
    -- If a term is defined as being equal to another term, find this other term.
    findDecl (VarE v')
      | v /= v' = findTerm False ms m v'
      | v == v' = error "found term of type `x = x`, the typechecker should have died on this ..."
    findDecl e = [Declared m v e]

    evarSourced :: [TermOrigin]
    evarSourced = map (\(_, src) -> Sourced m src)
                . Map.toList
                . Map.filterWithKey (\(v',_) _ -> v' == v)
                $ moduleSourceMap m

    evarImported :: [TermOrigin]
    evarImported =
      concat [findTerm False ms m' v | m' <- mapMaybe (flip Map.lookup $ ms) (listMVars m)]

    typeEVar :: EVar -> Expr
    typeEVar name = case Map.lookup name (moduleTypeMap m) of
      (Just (TypeSet t ts)) -> AnnE (VarE name) (map etype (maybe ts (\t' -> t':ts) t))
      Nothing -> error $ "Variable '" <> MT.unpack (unEVar name) <> "' is not defined"

    listMVars :: Module -> [MVar]
    listMVars = map importModuleName . filter (inImport v) . moduleImports

    inImport :: EVar -> Import -> Bool 
    inImport v imp = case (importInclude imp, importExclude imp) of  
        (Nothing, ex) -> not (elem v ex)
        (Just included, _) -> elem v (map snd included) 
