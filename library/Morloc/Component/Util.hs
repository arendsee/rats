{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Morloc.Component.Util
Description : Utility functions for components
Copyright   : (c) Zebulun Arendsee, 2018
License     : GPL-3
Maintainer  : zbwrnz@gmail.com
Stability   : experimental
-}

module Morloc.Component.Util (
    simpleGraph
  , graphify
) where

import Morloc.Global
import Morloc.Sparql
import qualified Morloc.Data.Text as MT
import qualified Morloc.Monad as MM

import qualified Data.Map.Strict as Map
import qualified Data.Maybe as DM
import qualified Data.List as DL
import qualified Data.List.Extra as DLE

-- | This works for building a map based off a simple tree structure
simpleGraph
  :: (Ord key, Ord a)
  => (    Map.Map key (a, [key])
       -> key
       -> MorlocMonad b
     )
  -> ([Maybe MT.Text] -> MorlocMonad a) -- ^ using input text (e.g., from a SPARQL query) get data
  -> (MT.Text -> key) -- ^ transform a text field into a key
  -> (db -> MorlocMonad [[Maybe MT.Text]]) -- ^ query a database
  -> db -- ^ the database
  -> MorlocMonad (Map.Map key b) -- ^ return a flat map
simpleGraph f g h query d = query d >>= mapM tuplify >>= graphify f
  where
    tuplify xs = case (take 3 xs, drop 3 xs) of
      ([Just mid, el, child], rs) -> do
        a1 <- g rs                            -- a
        let k1 = h mid                        -- key
        let y = (,) <$> el <*> (fmap h child) -- Maybe (Text, [key])
        return ((k1, a1), y)                  -- ((key, a), Maybe (Text, [key]))
      _ -> MM.throwError $ SparqlFail "Unexpected SPARQL output"

-- | Build a map of objects from a tree-like structure with parent keys
-- mapping to one or more ordered child ids.
graphify
  :: (Ord index, Ord key, Ord a)
  => (    Map.Map key (a, [key])
       -> key
       -> MorlocMonad b
     )
  -> [((key, a), Maybe (index, key))]
  -> MorlocMonad (Map.Map key b) -- one element for each root element
graphify f xs = do
  values <- mapM (f hash) roots
  return . Map.fromList . zip roots $ values 
  where
    hash
      = Map.fromList
      . map (\((x,d),ys) -> (x, (d, ys)))
      . map (withSnd (map snd . DL.sort . DM.catMaybes))
      . DLE.groupSort
      $ xs

    roots = [p | ((p,_),_) <- xs, not (elem p [c | (_, Just (_,c)) <- xs])]
  
withSnd :: (a -> b) -> (c, a) -> (c , b)
withSnd f (x, y) = (x, f y)
