module Main where

import Control.Monad.State

import UUID
import Util
import Tree
import AST
import SimpleCXX
import Edits
import Propositions
import NullPropositions
import SAT
import FeatureTrace
import FeatureTraceRecording
import FTRDirect
import FTRTwoStep

import FeatureColour

import Div

import Data.Maybe ( fromJust )
import Data.List (intercalate)

-- Terminal printing ---------
import Control.Concurrent ()
import Control.Monad
import Control.Monad.IO.Class

import Data.Text.Prettyprint.Doc
import System.Terminal

-- import Prelude hiding ((<>))
-----------------------------

data CodePrintStyle = ShowAST | ShowCode deriving (Show)
data TraceDisplay = Trace | PC deriving (Show, Eq)
data TraceStyle = Text | Colour | None deriving (Show, Eq)

main :: IO ()
main = withTerminal $ runTerminalT printer

printer :: (MonadColorPrinter m) => m ()
printer = (putDoc $ runFTR <+> hardline) >> flush
    
runFTR :: (MonadColorPrinter m) => Doc (Attribute m)
runFTR = fst . flip runState 0 $ do
    tree0 <- div0
    tree_assert <- div_assert
    tree_error <- div_error
    tree_condition <- div_condition
    tree_div <- div_div
    tree_reciprocal_return <- div_reciprocal_return
    let 
        -- Debug settings
        codeStyle = ShowCode -- One of: ShowAST, ShowCode
        traceDisplay = PC -- One of: Trace, PC
        traceStyle = Colour -- One of: Text, Colour, None
        withTraceLines = True
        abstractTrees = False
        featureColourPalette = Div.featureColourPalette
        -- The initial feature trace of the first tree.
        trace0 = emptyTrace
        -- Some helper variables for edits
        id_reciprocal_body = uuidOf . fromJust $ find (\(Tree n _) -> value n == "body") tree0
        tree_return = fromJust $ find (\(Tree n _) -> value n == "return") tree0
        id_cond_body = uuidOf . fromJust $ find (\(Tree n _) -> value n == "body") tree_condition
        id_div_body = uuidOf . fromJust $ find (\(Tree n _) -> value n == "body") tree_div
        tree_x_condexpr = fromJust $ find (\(Tree n _) -> value n == "x") tree_condition
        tree_x_return = fromJust $ find (\(Tree n _) -> value n == "x") tree_return
        tree_1_return = fromJust $ find (\(Tree n _) -> value n == "1.0") tree_return
        -- The edits "made by the developer"
        editscript = [
            edit_ins_tree tree_assert id_reciprocal_body 0
          , edit_ins_partial tree_condition id_reciprocal_body 0 0 id_cond_body 0
          , edit_del_tree (uuidOf tree_assert)
          , edit_ins_tree tree_error id_cond_body 0
          , edit_ins_tree tree_div (uuidOf tree0) 0
          , edit_move_tree (uuidOf tree_condition) id_div_body 0
          , edit_move_tree (uuidOf tree_return) id_div_body 1 -- now we are done with div5.txt
          , edit_update (uuidOf tree_x_condexpr) (rule $ element $ tree_x_condexpr) "b"
          , edit_update (uuidOf tree_x_return) (rule $ element $ tree_x_return) "b"
          , edit_update (uuidOf tree_1_return) SCXX_VarRef "a"
          , edit_ins_tree tree_reciprocal_return id_reciprocal_body 0
            ]
        -- The feature contexts assigned to each edit
        featureContexts = [
            Just $ PVariable feature_Debug
          , Just $ PVariable feature_Reciprocal
          , Just $ PVariable feature_Reciprocal -- Error by user. Should actually be PTrue
          , Just $ PVariable feature_Reciprocal
          , Just $ PVariable feature_Division
          , Just $ PVariable feature_Division
          , Just $ PVariable feature_Division
          , Just $ PVariable feature_Division
          , Just $ PVariable feature_Division
          , Just $ PVariable feature_Division
          , Just $ PVariable feature_Reciprocal
            ]
        -- Select the FeatureTraceRecording implementation to run
        recordBuilder = FTRTwoStep.builder
        -- Run the ftr
        tracesAndTrees = featureTraceRecordingWithIntermediateSteps recordBuilder trace0 tree0 editscript featureContexts
        -- tracesAndTrees = [featureTraceRecording recordBuilder trace0 tree0 editscript featureContexts]
        -- Some helper variables for output formatting
        toPC = \trace tree -> if traceDisplay == PC then pc tree trace else trace
        treeAbstract = if abstractTrees then abstract else id
        treePrint = \tree trace -> case codeStyle of
            ShowAST -> (case traceStyle of
                None -> pretty.show
                Colour -> Tree.prettyPrint 0 pretty (\n -> paint (trace n) $ show n)
                Text -> pretty.(FeatureTrace.prettyPrint).(augmentWithTrace trace)) tree
            ShowCode -> showCodeAs mempty (indentGenerator trace) (stringPrint trace) (nodePrint trace) tree
            where nodePrint trace n = case traceStyle of
                      None -> pretty $ value n
                      Colour -> paint (trace n) $ value n
                      Text -> pretty $ concat ["<", NullPropositions.prettyPrint $ trace n, ">", value n]
                  stringPrint trace n s = case traceStyle of
                      Colour -> paint (trace n) s
                      _ -> pretty s
                  indentGenerator trace n i = if traceStyle == Colour && traceDisplay == Trace && withTraceLines && ntype n == Legator
                      then mappend (paint (trace n) "|") (pretty $ genIndent (i-1))
                      else pretty $ genIndent i
                  paint formula = (annotate (foreground $ FeatureColour.colourOf featureColourPalette formula)).pretty
    return
        $ mappend (pretty $ intercalate "\n  " [
            "\nRunning Feature Trace Recording with",
            "codeStyle      = "++show codeStyle,
            "traceDisplay   = "++show traceDisplay,
            "traceStyle     = "++show traceStyle,
            "withTraceLines = "++show withTraceLines,
            "abstractTrees  = "++show abstractTrees])
        $ flip foldr
            mempty
            (\(fc, edit, (trace, tree)) s ->
                mconcat [
                    hardline,
                    hardline,
                    pretty $ concat ["==== Run ", show edit, " under context = "],
                    annotate (foreground $ FeatureColour.colourOf featureColourPalette fc) $ pretty $ NullPropositions.prettyPrint fc,
                    pretty $ " giving us ====",
                    hardline,
                    treePrint tree trace,
                    s])
        $ zip3
            (Nothing:featureContexts) -- Prepend dummy feature context here as fc for initial tree. The context could be anything so Nothing is the simplest one.
            (edit_identity:editscript) -- Prepend identity edit here to show initial tree.
            ((\(trace, tree) -> (toPC trace tree, treeAbstract tree)) <$> tracesAndTrees)
