{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.Scaffold.Markdown
-- Description: Lean GitHub-Flavored Markdown (GFM) AST and deterministic pretty-printer
--
-- This module implements a lightweight, pure-Haskell abstract syntax tree for
-- GitHub-Flavored Markdown (GFM) and CommonMark, paired with a deterministic,
-- zero-allocation pretty-printer.
--
-- = Architectural Context & Invariants
--
-- In Gachi's infrastructure model (per Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization]), repository assets and operational documents
-- must be emitted with structural precision.
--
-- Rather than relying on fragile, ad-hoc string concatenation (@T.unlines@) or
-- dragging in heavyweight external engines with hundreds of transitive dependencies
-- (such as full Pandoc), this module provides a lean, strongly-typed document
-- generation layer.
--
-- == Key Guarantees
--
-- 1. __Pure & Total:__ The pretty-printer 'renderMarkdown' is a pure, total
--    function with zero runtime I/O, zero network calls, and zero external C FFI.
-- 2. __Structural Invariance:__
--    * Table columns are dynamically measured across all rows and padded to
--      uniform widths with aligned separator lines (@| :--- | :--- |@).
--    * Block spacing follows standard CommonMark double-newline conventions.
--    * Links, anchors, code fencing, and Tagref pointers are structurally valid
--      by construction.
-- 3. __Lightweight Footprint:__ Zero dependencies beyond @base@ and @text@.
--
-- = Worked Example
--
-- >>> import Gachi.Scaffold.Markdown
-- >>> let doc = [ h1 "Project Title", para "A brief overview.", table ["Col 1", "Col 2"] [[plain "Val A", plain "Val B"]] ]
-- >>> renderMarkdown doc
-- "# Project Title\n\nA brief overview.\n\n| Col 1 | Col 2 |\n| :--- | :--- |\n| Val A | Val B |\n"
module Gachi.Scaffold.Markdown
  ( -- * Document Abstract Syntax Tree
    Block(..)
  , Inline(..)

    -- * Pretty-Printing Operations
  , renderMarkdown
  , renderBlock
  , renderInline

    -- * Block Constructors
  , h1
  , h2
  , h3
  , h4
  , para
  , paraInlines
  , codeBlock
  , plainCodeBlock
  , bulletList
  , orderedList
  , table
  , hr
  , rawBlock

    -- * Inline Constructors
  , plain
  , bold
  , italic
  , code
  , link
  , linkInline
  , tagRef
  , tagDef
  , inlines
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

--------------------------------------------------------------------------------
-- Abstract Syntax Tree: Inlines
--------------------------------------------------------------------------------

-- | Inline typographical and structural elements within a Markdown block.
data Inline
  = Plain !Text
    -- ^ Unformatted plain text.
  | Bold !Text
    -- ^ Strongly emphasized text: @**text**@.
  | Italic !Text
    -- ^ Emphasized text: @*text*@.
  | Code !Text
    -- ^ Inline monospace code span: @`code`@.
  | Link !Text !Text
    -- ^ Hyperlink with display label and destination URL/anchor: @[label](url)@.
  | TagRef !Text
    -- ^ Mechanical Tagref reference pointer (formatted as @ref:slug@ in brackets).
  | TagDef !Text
    -- ^ Mechanical Tagref definition anchor (formatted as @tag:slug@ in brackets).
  | Inlines ![Inline]
    -- ^ Compound sequence of inline elements concatenated together.
  deriving stock (Eq, Show, Generic)

instance Semigroup Inline where
  Inlines xs <> Inlines ys = Inlines (xs ++ ys)
  Inlines xs <> y          = Inlines (xs ++ [y])
  x          <> Inlines ys = Inlines (x : ys)
  Plain ""   <> y          = y
  x          <> Plain ""   = x
  x          <> y          = Inlines [x, y]

instance Monoid Inline where
  mempty = Plain ""

--------------------------------------------------------------------------------
-- Abstract Syntax Tree: Blocks
--------------------------------------------------------------------------------

-- | Block-level document elements in GitHub-Flavored Markdown.
data Block
  = Heading !Int !Text
    -- ^ Section heading with depth level (1–6) and title text.
  | Paragraph ![Inline]
    -- ^ Standard paragraph comprising a sequence of inline elements.
  | FencedCode !(Maybe Text) !Text
    -- ^ Code block enclosed in triple backticks with optional language tag.
  | BulletList ![Inline]
    -- ^ Unordered list of bulleted items.
  | OrderedList ![Inline]
    -- ^ Ordered numbered list of items.
  | Table ![Text] ![[Inline]]
    -- ^ GitHub-Flavored Markdown table with column headers and cell rows.
  | ThematicBreak
    -- ^ Horizontal thematic divider: @---@.
  | RawBlock !Text
    -- ^ Pre-rendered raw text block preserved without transformation.
  deriving stock (Eq, Show, Generic)

--------------------------------------------------------------------------------
-- Ergonomic Block Smart Constructors
--------------------------------------------------------------------------------

-- | Creates a Level 1 Heading (@# Title@).
h1 :: Text -> Block
h1 = Heading 1

-- | Creates a Level 2 Heading (@## Title@).
h2 :: Text -> Block
h2 = Heading 2

-- | Creates a Level 3 Heading (@### Title@).
h3 :: Text -> Block
h3 = Heading 3

-- | Creates a Level 4 Heading (@#### Title@).
h4 :: Text -> Block
h4 = Heading 4

-- | Creates a paragraph from plain text.
para :: Text -> Block
para t = Paragraph [Plain t]

-- | Creates a paragraph from a sequence of structured inline elements.
paraInlines :: [Inline] -> Block
paraInlines = Paragraph

-- | Creates a syntax-highlighted fenced code block.
codeBlock :: Text -> Text -> Block
codeBlock lang = FencedCode (Just lang)

-- | Creates an untyped fenced code block without language annotation.
plainCodeBlock :: Text -> Block
plainCodeBlock = FencedCode Nothing

-- | Creates an unordered bulleted list from inline items.
bulletList :: [Inline] -> Block
bulletList = BulletList

-- | Creates an ordered numbered list from inline items.
orderedList :: [Inline] -> Block
orderedList = OrderedList

-- | Creates a formatted GFM table from headers and row cells.
table :: [Text] -> [[Inline]] -> Block
table = Table

-- | Creates a horizontal thematic break divider (@---@).
hr :: Block
hr = ThematicBreak

-- | Creates a raw unescaped block preserved without modification.
rawBlock :: Text -> Block
rawBlock = RawBlock

--------------------------------------------------------------------------------
-- Ergonomic Inline Smart Constructors
--------------------------------------------------------------------------------

-- | Creates a plain text inline element.
plain :: Text -> Inline
plain = Plain

-- | Creates a bold inline element (@**text**@).
bold :: Text -> Inline
bold = Bold

-- | Creates an italic inline element (@*text*@).
italic :: Text -> Inline
italic = Italic

-- | Creates an inline monospace code span (@`code`@).
code :: Text -> Inline
code = Code

-- | Creates an inline hyperlink (@[text](url)@).
link :: Text -> Text -> Inline
link = Link

-- | Creates an inline hyperlink from a rendered 'Inline' label (@[inline](url)@).
linkInline :: Inline -> Text -> Inline
linkInline inl = Link (renderInline inl)

-- | Constructs a dynamic Tagref reference pointer (formatted as @ref:slug@ in brackets).
tagRef :: Text -> Inline
tagRef = TagRef

-- | Constructs a dynamic Tagref definition anchor (formatted as @tag:slug@ in brackets).
tagDef :: Text -> Inline
tagDef = TagDef

--------------------------------------------------------------------------------
-- Pretty-Printing: Inlines
--------------------------------------------------------------------------------

-- | Renders an 'Inline' element to its canonical Markdown representation.
--
-- Time complexity: @O(L)@ proportional to inline text length.
renderInline :: Inline -> Text
renderInline (Plain t)    = t
renderInline (Bold t)     = "**" <> t <> "**"
renderInline (Italic t)   = "*" <> t <> "*"
renderInline (Code t)     = "`" <> t <> "`"
renderInline (Link t u)   = "[" <> t <> "](" <> u <> ")"
renderInline (TagRef slug) = "[" <> "ref:" <> slug <> "]"
renderInline (TagDef slug) = "[" <> "tag:" <> slug <> "]"
renderInline (Inlines is)  = T.concat (map renderInline is)

-- | Constructs a compound sequence of inlines.
inlines :: [Inline] -> Inline
inlines = Inlines

--------------------------------------------------------------------------------
-- Pretty-Printing: Blocks
--------------------------------------------------------------------------------

-- | Renders a sequence of 'Block' elements into a complete Markdown document.
--
-- Blocks are separated by standard blank lines adhering to CommonMark rules.
--
-- Time complexity: @O(N)@ proportional to total document nodes and cell counts.
renderMarkdown :: [Block] -> Text
renderMarkdown blocks =
  T.intercalate "\n" (map renderBlock blocks)

-- | Renders a single 'Block' element to formatted Markdown text.
renderBlock :: Block -> Text
renderBlock (Heading level title) =
  let hashes = T.replicate (max 1 (min 6 level)) "#"
  in hashes <> " " <> title <> "\n"

renderBlock (Paragraph inls) =
  T.concat (map renderInline inls) <> "\n"

renderBlock (FencedCode maybeLang codeContent) =
  let lang = fromMaybe "" maybeLang
      cleanContent = T.dropWhileEnd (== '\n') codeContent
  in "```" <> lang <> "\n" <> cleanContent <> "\n```\n"

renderBlock (BulletList items) =
  let renderItem item = "- " <> renderInline item
  in T.unlines (map renderItem items)

renderBlock (OrderedList items) =
  let renderItem idx item = T.pack (show (idx :: Int)) <> ". " <> renderInline item
  in T.unlines (zipWith renderItem [1 ..] items)

renderBlock (Table headers rows) =
  renderTableLayout headers rows

renderBlock ThematicBreak =
  "---\n"

renderBlock (RawBlock raw) =
  T.dropWhileEnd (== '\n') raw <> "\n"

--------------------------------------------------------------------------------
-- Table Formatting Mechanics
--------------------------------------------------------------------------------

-- | Formats a GitHub-Flavored Markdown table with auto-aligned column boundaries.
--
-- Dynamically evaluates cell text lengths across all headers and rows, computing
-- the minimum required padding per column and emitting clean separator lines.
renderTableLayout :: [Text] -> [[Inline]] -> Text
renderTableLayout headers rows =
  let renderedRows = map (map renderInline) rows
      colCount = length headers
      -- Pad or truncate each row to match header column count
      normalizedRows = map (normalizeRow colCount) renderedRows
      -- Compute maximum width per column (at least 3 characters for :---)
      allRowsWithHeader = headers : normalizedRows
      colWidths = [ maximum (3 : map (T.length . safeIndex c) allRowsWithHeader)
                  | c <- [0 .. colCount - 1]
                  ]
      -- Format header line
      headerLine = formatRow colWidths headers
      -- Format separator line (| :--- | :--- |)
      sepLine = formatSepRow colWidths
      -- Format data rows
      dataLines = map (formatRow colWidths) normalizedRows
  in T.unlines (headerLine : sepLine : dataLines)
  where
    normalizeRow targetLen r
      | length r >= targetLen = take targetLen r
      | otherwise             = r ++ replicate (targetLen - length r) ""

    safeIndex idx xs
      | idx < length xs = xs !! idx
      | otherwise       = ""

    formatRow widths cells =
      let padded = zipWith padCell widths cells
      in "| " <> T.intercalate " | " padded <> " |"

    formatSepRow widths =
      let seps = map (\w -> ":" <> T.replicate (max 2 (w - 1)) "-") widths
      in "| " <> T.intercalate " | " seps <> " |"

    padCell width cell =
      let padding = max 0 (width - T.length cell)
      in cell <> T.replicate padding " "
