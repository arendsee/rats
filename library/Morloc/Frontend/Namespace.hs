{-|
Module      : Morloc.Frontend.Namespace
Description : All frontend types and datastructures
Copyright   : (c) Zebulun Arendsee, 2021
License     : GPL-3
Maintainer  : zbwrnz@gmail.com
Stability   : experimental
-}

module Morloc.Frontend.Namespace
  ( module Morloc.Namespace
  , Expr(..)
  , Import(..)
  , Stack
  , StackState(..)
  , StackConfig(..)
  -- ** DAG and associated types
  , ParserNode(..)
  , ParserDag
  , PreparedNode(..)
  , PreparedDag
  , TypedNode(..)
  , TypedDag
  -- ** Typechecking
  , Gamma
  , GammaIndex(..)
  , EType(..)
  , TypeSet(..)
  , Indexable(..)
  -- ** ModuleGamma paraphernalia
  , ModularGamma
  -- rifraf
  , resolve
  , substituteT
  ) where

import Morloc.Namespace
import Data.Set (Set)
import Data.Map.Strict (Map)
import Control.Monad.Except (ExceptT)
import Control.Monad.Reader (ReaderT)
import Control.Monad.State (StateT)
import Control.Monad.Writer (WriterT)
import Data.Scientific (Scientific)
import Data.Text (Text)



-- This functions removes qualified and existential types.
--  * all qualified terms are replaced with UnkT
--  * all existentials are replaced with default values if a possible
--    FIXME: should I really just take the first in the list???
resolve :: UnresolvedType -> Type
resolve (VarU v) = VarT v
resolve (FunU t1 t2) = FunT (resolve t1) (resolve t2)
resolve (ArrU v ts) = ArrT v (map resolve ts)
resolve (NamU r v ps rs) =
  let ts' = map (resolve . snd) rs
      ps' = map resolve ps 
  in NamT r v ps' (zip (map fst rs) ts')
resolve (ExistU _ _ []) = error "UnsolvedExistentialTerm"
resolve (ExistU _ _ (t:_)) = resolve t
resolve (ForallU v t) = substituteT v (UnkT v) (resolve t)

-- | substitute all appearances of a given variable with a given new type
substituteT :: TVar -> Type -> Type -> Type
substituteT v0 r0 t0 = sub t0
  where
    sub :: Type -> Type
    sub t@(UnkT _) = t
    sub t@(VarT v)
      | v0 == v = r0
      | otherwise = t
    sub (FunT t1 t2) = FunT (sub t1) (sub t2)
    sub (ArrT v ts) = ArrT v (map sub ts)
    sub (NamT r v ts rs) = NamT r v (map sub ts) [(x, sub t) | (x, t) <- rs]


-- | Terms, see Dunfield Figure 1
data Expr
  = SrcE [Source]
  -- ^ import "c" from "foo.c" ("f" as yolo)
  | Signature EVar EType
  -- ^ x :: A; e
  | Declaration EVar Expr
  -- ^ x=e1; e2
  | UniE
  -- ^ (())
  | VarE EVar
  -- ^ (x)
  | AccE Expr EVar
  -- ^ person@age - access a field in a record
  | ListE [Expr]
  -- ^ [e]
  | TupleE [Expr]
  -- ^ (e1), (e1,e2), ... (e1,e2,...,en)
  | LamE EVar Expr
  -- ^ (\x -> e)
  | AppE Expr Expr
  -- ^ (e e)
  | AnnE Expr [UnresolvedType]
  -- ^ (e : A)
  | NumE Scientific
  -- ^ number of arbitrary size and precision
  | LogE Bool
  -- ^ boolean primitive
  | StrE Text
  -- ^ literal string
  | RecE [(EVar, Expr)]
  deriving (Show, Ord, Eq)

-- | Extended Type that may represent a language specific type as well as sets
-- of properties and constrains.
data EType =
  EType
    { etype :: UnresolvedType
    , eprop :: Set Property
    , econs :: Set Constraint
    }
  deriving (Show, Eq, Ord)

instance HasOneLanguage EType where
  langOf e = langOf (etype e) 

data Import =
  Import
    { importModuleName :: MVar
    , importInclude :: Maybe [(EVar, EVar)]
    , importExclude :: [EVar]
    , importNamespace :: Maybe EVar -- currently not used
    }
  deriving (Ord, Eq, Show)

-- | A context, see Dunfield Figure 6
data GammaIndex
  = VarG TVar
  -- ^ (G,a)
  | AnnG Expr TypeSet
  -- ^ (G,x:A) looked up in the (Var) and cut in (-->I)
  | ExistG TVar [UnresolvedType] [UnresolvedType]
  -- ^ (G,a^) unsolved existential variable
  | SolvedG TVar UnresolvedType
  -- ^ (G,a^=t) Store a solved existential variable
  | MarkG TVar
  -- ^ (G,>a^) Store a type variable marker bound under a forall
  | MarkEG EVar
  -- ^ ...
  | SrcG Source
  -- ^ source
  | UnsolvedConstraint UnresolvedType UnresolvedType
  -- ^ Store an unsolved serialization constraint containing one or more
  -- existential variables. When the existential variables are solved, the
  -- constraint will be written into the Stack state.
  deriving (Ord, Eq, Show)

type Gamma = [GammaIndex]

data TypeSet =
  TypeSet (Maybe EType) [EType]
  deriving (Show, Eq, Ord)

type ModularGamma = Map MVar (Map EVar TypeSet)

class Indexable a where
  index :: a -> GammaIndex

instance Indexable GammaIndex where
  index = id

instance Indexable UnresolvedType where
  index (ExistU t ts ds) = ExistG t ts ds
  index t = error $ "Can only index ExistT, found: " <> show t



type GeneralStack c e l s a
   = ReaderT c (ExceptT e (WriterT l (StateT s IO))) a

type Stack a = GeneralStack StackConfig MorlocError [Text] StackState a

data StackConfig =
  StackConfig
    { stackConfigVerbosity :: Int
    }

data StackState =
  StackState
    { stateVar :: Int
    , stateQul :: Int
    , stateSer :: [(UnresolvedType, UnresolvedType)]
    , stateDepth :: Int
    }
  deriving (Ord, Eq, Show)



-- | The type returned from the Parser. It contains all the information in a
-- single module but knows NOTHING about other modules.
data ParserNode = ParserNode  {
    parserNodePath :: Maybe Path
  , parserNodeBody :: [Expr]
  , parserNodeSourceMap :: Map (EVar, Lang) Source
  , parserNodeTypedefs :: Map TVar (UnresolvedType, [TVar])
  , parserNodeExports :: Set EVar
} deriving (Show, Ord, Eq)
type ParserDag = DAG MVar Import ParserNode

-- | Node description after desugaring (substitute type aliases and resolve
-- imports/exports)
data PreparedNode = PreparedNode {
    preparedNodePath :: Maybe Path
  , preparedNodeBody :: [Expr]
  , preparedNodeSourceMap :: Map (EVar, Lang) Source
  , preparedNodeExports :: Set EVar
  , preparedNodeTypedefs :: Map TVar (UnresolvedType, [TVar])
  , preparedNodePackers :: Map (TVar, Int) [UnresolvedPacker]
  -- ^ The (un)packers available in this module scope.
} deriving (Show, Ord, Eq)
type PreparedDag = DAG MVar [(EVar, EVar)] ParserNode

-- | Node description after type checking. This will later be fed into
-- `treeify` to make the SAnno objects that will be passed to Generator.
data TypedNode = TypedNode {
    typedNodeModuleName :: MVar
  , typedNodePath :: Maybe Path
  , typedNodeBody :: [Expr]
  , typedNodeTypeMap :: Map EVar TypeSet
  , typedNodeSourceMap :: Map (EVar, Lang) Source
  , typedNodeExports :: Set EVar
  , typedNodeTypedefs :: Map TVar (Type, [TVar])
  , typedNodePackers :: Map (TVar, Int) [UnresolvedPacker]
  , typedNodeConstructors :: Map TVar Source
  -- ^ The (un)packers available in this module scope.
} deriving (Show, Ord, Eq)
type TypedDag = DAG MVar [(EVar, EVar)] TypedNode
