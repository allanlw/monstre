{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ForeignFunctionInterface #-}
module RegexTreeReduce where

import System.Environment
import System.Exit
import Text.Read
import Text.Show.Pretty
import Text.JSON
import Data.Char
import Data.List
import Text.JSON.Generic
import Control.Exception
import Data.Typeable
import Foreign.C.String

-- Input regular expression AST type
data RegexExpr = REAlternative [RegexExpr]
               | REElement [RegexExpr]
               | RECharacter_class [RegexExpr]
               | RENegated_character_class [RegexExpr]
               | RERange [RegexExpr]
               | RELiteral String
               | REWordboundary String
               | RENotwordchar String
               | REWhitespace String
               | RENumber Int
               | REGreedy
               | RELazy
               | REAny
               | REStart_of_subject
               | REEndofsubjectorline String
               | RENon_capturing_group [RegexExpr]
               | RENon_capturing_group_options [RegexExpr]
               | RECapturing_group [RegexExpr]
               | REOr [RegexExpr]
               | REQuantifier [RegexExpr]
               | REDecimaldigit String
               | RENegative_look_ahead [RegexExpr]
               | REOptions [RegexExpr]
               | REOption String
               | RESet [RegexExpr]
               | REUnset
   deriving (Show, Read)

data UnhandledRegexExpr = UnhandledRegex (Either RegexExpr String) deriving (Show, Typeable)
instance Exception UnhandledRegexExpr

-- Simplified regular expression AST Type
data SimpleRegex = SConcat SimpleRegex SimpleRegex
                 | SAlternation SimpleRegex SimpleRegex
                 | SConstant Char
                 | SKleen SimpleRegex
                 | SAny
                 | SEmpty
   deriving (Show, Read, Data, Typeable)

maxConstantRepetitions :: Int
maxConstantRepetitions = 16 -- maximum number of repetitions to allow in {0,n}

readRegexExpr :: String -> RegexExpr
readRegexExpr s =
  case (readMaybe s :: Maybe RegexExpr) of
    Nothing -> throw $ UnhandledRegex $ Right "Read parse error"
    Just a -> a

simplifyRegex :: RegexExpr -> SimpleRegex
simplifyRegex = simplifyRegex2_ . simplifyRegex1_

-- Complete Alphabet that we will inspect
totalAlphabet :: [Char]
totalAlphabet = filter isPrint $ map chr [0..127]

-- Takes a "negated" character class, and returns a new one that is
-- A non-negated character class that matches all the other bytes
negateCharacterClass :: [RegexExpr] -> [RegexExpr]
negateCharacterClass cls = [RELiteral [c2] | c2 <- totalAlphabet \\ [c | RELiteral [c] <- cls]]

-- first pass
simplifyRegex1_ :: RegexExpr -> SimpleRegex
simplifyRegex1_ re =
  case re of
    REAlternative [a] -> simplifyRegex a
    REAlternative (a:xs) -> SConcat (simplifyRegex1_ a) (simplifyRegex1_ $ REAlternative xs)
    REOr [a] -> simplifyRegex1_ a
    REOr (a:xs) -> SAlternation (simplifyRegex1_ a) (simplifyRegex1_ $ REOr xs)
    -- Base REElement matches, ones with quantifiers get reduced to this
    REElement [RECapturing_group xs] -> simplifyRegex1_ $ REAlternative xs
    REElement [RENon_capturing_group xs] -> simplifyRegex1_ $ REAlternative xs
    REElement [RELiteral [a]] -> SConstant a
    REElement [RECharacter_class [a]] -> simplifyRegex1_ $ REElement [ a ]
    REElement [RECharacter_class (a:xs)] -> simplifyRegex1_ $ REOr [ REElement [ a ], REElement [RECharacter_class xs] ]
    REElement [RENegated_character_class q] -> simplifyRegex1_ $ REElement [RECharacter_class $ negateCharacterClass q]
    REElement [REAny] -> SAny
    REElement [REDecimaldigit "\\d"] -> simplifyRegex1_ $ REElement [ RECharacter_class [RERange [RELiteral "0", RELiteral "9"] ] ]
    REElement [RERange [ RELiteral [a], RELiteral [b] ] ] -> simplifyRegex1_ $ REElement [ RECharacter_class [RELiteral [q] | q <- [a..b] ] ]
    REElement [REWhitespace "\\s"] -> simplifyRegex1_ $ REElement [ RECharacter_class [RELiteral [x] | x <- " \t\r\n"]]
    -- first handle "Infinite" quantifiers separately
    REElement [a, REQuantifier [RENumber 0, RENumber 2147483647, _]] -> SKleen $ simplifyRegex1_ $ REElement [a]
    REElement [a, REQuantifier [RENumber n, RENumber 2147483647, g]] -> simplifyRegex1_ $ REAlternative [REElement[a], REElement [a, REQuantifier[ RENumber $ n - 1, RENumber 2147483647, g] ] ]
    -- then handle regular quantifiers
    REElement [a, REQuantifier [RENumber 0, RENumber 0, _]] -> SEmpty
    REElement [a, REQuantifier [RENumber 0, RENumber z, g]] -> if z > maxConstantRepetitions then SKleen $ simplifyRegex1_ $ REElement[a] else simplifyRegex1_ $ REOr [ REAlternative (replicate z $ REElement [a]), REElement [a, REQuantifier [ RENumber 0, RENumber $ z - 1, g ] ] ]
    REElement [a, REQuantifier [RENumber n, RENumber z, g]] -> simplifyRegex1_ $ REAlternative [ REElement [a], REElement [a, REQuantifier [ RENumber $ n - 1, RENumber $ z - 1, g] ] ]
    -- this that we don't implement but that can get reasonable analysis regardless
    REElement [REStart_of_subject] -> SEmpty
    REElement [REWordboundary "\\b"] -> SEmpty
    REElement [RENotwordchar "\\W"] -> SConstant '/' -- just some placeholder non-word character
    REElement [REEndofsubjectorline "$"] -> SEmpty
    -- others are not handled
    e -> throw $ UnhandledRegex $ Left e

-- Clean up garbage on second pass
simplifyRegex2_ :: SimpleRegex -> SimpleRegex
simplifyRegex2_ re =
  case re of
    SConcat SEmpty a -> simplifyRegex2_ a
    SConcat a SEmpty -> simplifyRegex2_ a
    q -> q

reduceTree :: String -> String
reduceTree = encodeJSON . simplifyRegex . readRegexExpr

foreign export ccall reduceTreeC :: CString -> IO CString
reduceTreeC :: CString -> IO CString
reduceTreeC a =
  do
    input <- peekCString a
    let r = reduceTree input
    catch (newCString r) (\e -> newCString $ show (e :: UnhandledRegexExpr))
