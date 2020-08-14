{-# LANGUAGE DeriveTraversable #-}

module Tree where
import Data.List
import Data.Maybe

import Util

data Tree a = Tree a [Tree a] deriving (Eq, Traversable)

prettyPrint :: Show a => Int -> Tree a -> String
prettyPrint i (Tree n []) = (genIndent i) ++ (show n) ++ " []\n"
prettyPrint i (Tree n children) =
  (genIndent i) ++ (show n) ++ " [\n" ++ (concat $ fmap (prettyPrint $ i+1) children) ++ (genIndent i) ++ "]\n"

instance Show a => Show (Tree a) where
  show = prettyPrint 0

instance Functor Tree where
  fmap f (Tree n c) = Tree (f n) (fmap (fmap f) c)

instance Foldable Tree where
  foldMap f {- a to Monoid -} (Tree x c) = mappend (f x) (mconcat $ fmap (foldMap f) c)

instance Applicative Tree where
   pure a = Tree a []
   (<*>) (Tree f cf) (Tree x cx) = Tree (f x) (concatMap (\g -> fmap (\c -> g <*> c) cx) cf)

--instance Traversable Tree where
--  traverse g (Tree x []) = fmap pure (g x)
--  traverse g t@(Tree x c) = fmap (traverse g) c
  
isleaf :: Tree a -> Bool
isleaf (Tree _ children) = null children

element :: Tree a -> a
element (Tree n _) = n

find :: Tree a -> (Tree a -> Bool) -> Maybe(Tree a)
find x@(Tree _ children) predicate = case predicate x of
  True -> Just x
  False -> safehead $ catMaybes $ map (\t -> Tree.find t predicate) children

parent :: Eq a => Tree a -> Tree a -> Maybe(Tree a)
parent root t = Tree.find root (\(Tree _ children) -> elem t children)

manipulate :: (Tree a -> Tree a) -> Tree a -> Tree a
manipulate f (Tree x children) = f (Tree x (fmap (manipulate f) children))

{-
Removes all subtrees meeting the imposed condition.
The root remains untouched.
-}
filterTrees :: (Tree a -> Bool) -> Tree a -> Tree a
filterTrees p = manipulate (\(Tree n c) -> Tree n (Data.List.filter p c))

{-
Removes all nodes meeting the imposed condition.
Children of removed nodes are moved up and become children of the parent of the removed node.
The root remains untouched.
-}
filterNodes :: (Tree a -> Bool) -> Tree a -> Tree a
filterNodes p = manipulate (\tree@(Tree node children) ->
    Tree node (concat $ fmap (\c@(Tree _ cc) -> if p c then cc else [c]) children))