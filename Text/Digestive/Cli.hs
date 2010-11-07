-- | Proof-of-concept module: use digestive functors for a command line
-- interface prompt
--
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Text.Digestive.Cli
    ( Descriptions (..)
    , Prompt
    , prompt
    , runPrompt
    ) where

import Data.Map (Map)
import qualified Data.Map as M
import Data.Monoid (Monoid, mempty, mappend)
import Control.Applicative ((<$>))

import Text.Digestive.Result
import Text.Digestive.Types
import qualified Text.Digestive.Common as Common

newtype Descriptions = Descriptions
    { unDescriptions :: Map FormId [String]
    } deriving (Show)

instance Monoid Descriptions where
    mempty = Descriptions mempty
    mappend (Descriptions m1) (Descriptions m2) =
        Descriptions $ M.unionWith (++) m1 m2

type Prompt a = Form IO String String Descriptions a

-- | Remove the descriptions for the inputs already in the input map.
--
neededDescriptions :: InputMap -> Descriptions -> Descriptions
neededDescriptions (InputMap inputMap) =
    Descriptions . M.filterWithKey notInInput . unDescriptions
  where
    notInInput k _ = k `notElem` map fst inputMap

-- | Add errors to the descriptions
--
addErrors :: [(FormRange, String)] -> Descriptions -> Descriptions
addErrors errors (Descriptions descr) = Descriptions $ foldl add' descr errors
  where
    add' map' ((FormRange x _, e)) = M.insertWith (++) x [e] map'

newtype InputMap = InputMap
    { unInputMap :: [(FormId, String)]
    } deriving (Show, Monoid)

inputMapEnvironment :: Monad m => InputMap -> Environment m String
inputMapEnvironment map' = Environment $ return . flip lookup (unInputMap map')

promptOnce :: Descriptions -> IO (FormId, String)
promptOnce (Descriptions descr)
    | M.null descr = error "No descriptions!"
    | otherwise = do putStrLn ""
                     mapM_ putStrLn description
                     putStr "> "
                     (,) key <$> getLine
  where
    (key, description) = M.findMin descr

-- | Remove all input for which errors are found
--
removeInvalidInput :: InputMap -> [(FormRange, String)] -> InputMap
removeInvalidInput = foldl removeInvalidInput'
  where
    removeInvalidInput' :: InputMap -> (FormRange, String) -> InputMap
    removeInvalidInput' (InputMap map') (range, _) =
        InputMap $ filter (not . flip isInRange range . fst) map'

prompt :: String -> Prompt String
prompt descr = Common.input (const $ const $ const [])
                            toResult
                            (\x _ -> Descriptions $ M.singleton x [descr])
                            ""
  where
    toResult Nothing _ = Error []
    toResult (Just x) _ = Ok x

runPrompt :: Prompt a -> IO a
runPrompt form = prompt' mempty
  where
    prompt' inputMap = do
        (v, r) <- runForm form "form" $ inputMapEnvironment inputMap
        case r of
            Ok x -> return x
            Error e -> do let inputMap' = removeInvalidInput inputMap e
                              descr = addErrors e
                                    $ neededDescriptions inputMap' (unView v [])
                          input' <- promptOnce descr
                          prompt' $ inputMap' `mappend` InputMap [input']
