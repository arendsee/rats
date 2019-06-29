{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Manifold
Description : Functions for dealing with Manifolds
Copyright   : (c) Zebulun Arendsee, 2018
License     : GPL-3
Maintainer  : zbwrnz@gmail.com
Stability   : experimental
-}

module Morloc.Manifold
( 
    getManSrcs
  , filterByManifoldClass
  , getUnpackers
  , getPacker
  , getUsedManifolds
  , determineManifoldClass
  , isMorlocCall
  , uniqueRealization
) where

import Morloc.Global
import Morloc.Data.Doc hiding ((<$>))
import qualified Morloc.Data.Text as MT
import qualified Morloc.Monad as MM
import qualified Data.List as DL
import qualified Data.Maybe as DM
import qualified Data.Map.Strict as Map
import qualified Morloc.System as MS
import qualified Morloc.TypeHandler as MTH

-- | Get the paths to the sources 
getManSrcs :: Lang -> (MT.Text -> MorlocMonad Doc) -> [Manifold] -> MorlocMonad [Doc]
getManSrcs lang f ms = MM.mapM f . DL.nub . DM.mapMaybe getManSrc $ ms' where
  getManSrc :: Manifold -> Maybe MT.Text
  getManSrc m = case (mSourcePath m, mModulePath m) of
    (Just srcpath, Just modpath) ->
      case MS.takeDirectory modpath of
        "."  -> Just srcpath
        path -> Just $ path <> "/" <> srcpath
    _ -> Nothing

  -- select the manifolds that are in the same language as the grammar 
  ms' = filter (\m -> lang == mLang m) ms

determineManifoldClass :: Lang -> Manifold -> ManifoldClass
determineManifoldClass lang m
  | mDefined m && not (mCalled m) && not (mExported m) = Uncalled
  | mLang m == lang
      && not (mCalled m)
      && mSourced m
      && mExported m = Source
  | not (mCalled m) && mExported m = Uncalled
  | mLang m == lang = Cis 
  | (mLang m /= lang) && mCalled m = Trans
  | otherwise = Uncalled

filterByManifoldClass :: Lang -> ManifoldClass -> [Manifold] -> [Manifold]
filterByManifoldClass lang mc ms = filter (\m -> mc == determineManifoldClass lang m) ms

-- | Is this manifold a called morloc function?
isMorlocCall :: Manifold -> Bool
isMorlocCall m = mDefined m && DM.isNothing (mComposition m)

-- find a packer for each argument passed to a manifold
getUnpackers :: SerialMap -> Manifold -> MorlocMonad [Doc]
getUnpackers hash m = case mConcreteType m of
  (Just (MFuncType _ ts _)) -> mapM (getUnpacker hash) ts
  (Just _) -> MM.throwError . TypeError $ "Unpackers must be functions"
  Nothing -> case mAbstractType m of
    (Just (MFuncType _ ts _)) -> mapM (getUnpacker hash) ts
    (Just _) -> MM.throwError . TypeError $ "Unpackers must be functions"
    Nothing -> MM.throwError . TypeError $
      "Expected a function for the following manifold: " <> MT.pretty m
  where
    getUnpacker :: SerialMap -> MType -> MorlocMonad Doc
    getUnpacker smap t =
      case (MTH.findMostSpecificType
             . Map.keys
             . Map.filterWithKey (\p _ -> MTH.childOf t p)
             $ (serialUnpacker smap)
           ) >>= (flip Map.lookup) (serialUnpacker smap)
      of
        (Just x) -> return (text' x)
        Nothing -> MM.throwError . GeneratorError
          $  "No unpacker found - this is either a bug in the "
          <> "morloc codebase or incomplete serialization handling "
          <> "for the given language." <> "\n"
          <> " - SerialMap: " <> MT.show' smap <> "\n"
          <> " - MType: " <> MT.show' t

-- | If a language-specific signature is given for the manifold, choose a
-- packer that matches the language-specific output type. Otherwise, search for
-- a packer that matches the morloc type.
-- TODO: make the MorlocMonad
getPacker :: SerialMap -> Manifold -> Doc
getPacker hash m = case packerType of
  (Just t) -> case Map.lookup t (serialPacker hash) of
    (Just n) -> text' n
    Nothing -> error "You should not be reading this"
  Nothing -> error "No packer found for this type"
  where
    packerType :: Maybe MType
    packerType = case cPacker of
      (Just x) -> Just x
      Nothing -> aPacker

    cPacker :: Maybe MType
    cPacker = case mConcreteType m of
      (Just (MFuncType _ _ t)) -> MTH.findMostSpecificType (packers t)
      (Just _) -> error "Ah shit"
      Nothing -> Nothing

    aPacker :: Maybe MType
    aPacker = case mAbstractType m of
      (Just (MFuncType _ _ t)) -> MTH.findMostSpecificType (packers t)
      (Just _) -> error "Ah shit"
      Nothing -> Nothing

    packers :: MType -> [MType]
    packers o
      = Map.keys
      . Map.filterWithKey (\p _ -> MTH.childOf o p)
      $ (serialPacker hash)

-- | Find the manifolds that must be defined in a pool for a given language.
getUsedManifolds :: Lang -> [Manifold] -> [Manifold]
getUsedManifolds lang ms = filter buildIt ms
  where
    buildIt :: Manifold -> Bool
    buildIt m =
      let mc = determineManifoldClass lang m in
        mc == Cis || mc == Source

-- | @realize@ determines which instances to use for each manifold.
uniqueRealization
  :: [Manifold] 
  -- ^ Abstract manifolds with possibly multiple realizations or none.
  -> MorlocMonad [Manifold]
  -- ^ Uniquely realized manifolds (e.g., mRealizations has exactly one element)
uniqueRealization ms = do
  let ms' = map (MTH.chooseRealization ms) ms
  return $ map (compInit ms') ms'
  where

    -- initialize composition realizations
    compInit :: [Manifold] -> Manifold -> Manifold 
    compInit ms'' m
      | mDefined m = makeRealization m (mRealizations (findChild ms'' m))
      | otherwise = m

    findChild :: [Manifold] -> Manifold -> Manifold
    findChild ms'' m = case filter (\n -> mComposition n == (Just (mMorlocName m))) ms'' of
      (child:_) -> child
      xs -> error ("error in findChild: m=" <> show m <> " --- " <> "xs=" <> show xs)

    makeRealization :: Manifold -> [Realization] -> Manifold
    makeRealization p rs = p { mRealizations = map (\r -> r { rSourced = False }) rs }
