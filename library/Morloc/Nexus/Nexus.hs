{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Morloc.Nexus.Nexus
Description : Code generators for the user interface
Copyright   : (c) Zebulun Arendsee, 2018
License     : GPL-3
Maintainer  : zbwrnz@gmail.com
Stability   : experimental
-}

module Morloc.Nexus.Nexus (generate) where

import Morloc.Types
import Morloc.Config (Config)
import qualified Morloc.Nexus.Template.Perl as Perl

-- | Generate the nexus, which is a program that coordinates the execution of
-- the language-specific function pools.
generate :: SparqlDatabaseLike db => Config -> Lang -> db -> IO Script
generate config "perl" = Perl.generate config
generate _ l = error ("Cannot generate nexus in language: " ++ show l)
