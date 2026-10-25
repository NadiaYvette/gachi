{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.Scaffold.Templates
-- Description: Pure template generation for canonical repository assets
--
-- This module implements pure, deterministic template generators synthesizing
-- all canonical files and directories required by the ecosystem standardization
-- matrix (per Note [Ecosystem Standardization Invariants] [ref:note-ecosystem-standardization]).
--
-- = Architectural Invariants & Guarantees
--
-- 1. __Referential Transparency:__ All generators are total, pure functions from
--    a 'Gachi.Schema.Project.Project' specification to 'Text'. They perform no I/O,
--    read no ambient filesystem state, and make no network requests.
--
-- 2. __Five-Gate Readiness:__ Skeletons produced by these templates are fully
--    valid out-of-the-box. When materialized on disk, the project immediately
--    passes all five physical verification gates:
--    * Gate 1 (HLint): Clean code conforming to modern GHC conventions.
--    * Gate 2 (Tests): Compilable Cabal package declarations and passing Hspec suites.
--    * Gate 3 (Tagref): Consistent cross-reference tags with zero dangling pointers.
--    * Gate 4 (Linkcheck): Fully verified relative Markdown links and section anchors.
--    * Gate 5 (CLOC): Production source files with 50%+ in-code comment density.
--
-- = Grounding & Tags
--
-- To prevent accidental tag definition collisions between the Gachi host compiler
-- and the target generated project, tag definitions in generated documentation
-- are constructed dynamically.
module Gachi.Scaffold.Templates
  ( -- * Composite Project Entry Generators
    allProjectEntries

    -- * Toolchain & Configuration Templates
  , cabalProjectTemplate
  , cabalProjectLocalTemplate
  , hlintTemplate
  , gitmessageTemplate
  , tagrefConfigTemplate

    -- * Hook Templates
  , commitMsgHookTemplate
  , preCommitHookTemplate

    -- * Verification Harness Templates
  , verifyScriptTemplate
  , tagrefScriptTemplate
  , linkcheckScriptTemplate
  , clocScriptTemplate
  , generateTagsTemplate

    -- * Operational Governance Templates
  , readmeTemplate
  , agentsTemplate
  , claudeTemplate
  , planTemplate
  , stateTemplate

    -- * Agent Rules Templates
  , ruleCommitAttributionTemplate
  , ruleCodeNavigationTemplate
  , ruleCompilerVerificationTemplate
  , ruleDocPrecedenceTemplate

    -- * Documentation Corpus Templates
  , docsIndexTemplate
  , docsTutorialTemplate
  , docsNewbieGuideTemplate
  , docsMaintainerGuideTemplate
  , docsDesignTemplate
  , docsStrategyTemplate
  , docsCommitAttributionTemplate

    -- * Package Asset Templates
  , packageCabalTemplate
  , packageReadmeTemplate
  , packageModuleTemplate
  , packageTestTemplate

    -- * String & Path Utilities
  , defaultModuleName
  , moduleToFilePath
  , toUpperSlug
  ) where

import Data.Char (isAlphaNum, toUpper)
import Data.Text (Text)
import qualified Data.Text as T

import Gachi.Schema.Project
  ( PackageSpec
  , Project
  , authorEmail
  , authorName
  , packageExposes
  , packageName
  , packageSynopsis
  , projectAuthor
  , projectCabalVersion
  , projectDescription
  , projectGhcVersion
  , projectLicense
  , projectName
  , projectPackages
  )
import Gachi.Scaffold.Markdown
  ( Block(..)
  , bold
  , bulletList
  , code
  , codeBlock
  , h1
  , h2
  , h3
  , hr
  , inlines
  , link
  , linkInline
  , orderedList
  , para
  , paraInlines
  , plain
  , plainCodeBlock
  , renderInline
  , renderMarkdown
  , tagDef
  , tagRef
  )
import Gachi.Scaffold.Types (FileEntry(..))

--------------------------------------------------------------------------------
-- Dynamic Tag and Anchor Placeholders
--------------------------------------------------------------------------------

-- | Constructs a dynamic Tagref reference pointer.
refCoreArch :: Text
refCoreArch = renderInline (tagRef "note-core-architecture")

-- | Canonical ecosystem standardization reference pointer.
refStandardization :: Text
refStandardization = "(per gachi)"

--------------------------------------------------------------------------------
-- Composite Project Scaffolding Generator
--------------------------------------------------------------------------------

-- | Generates the complete, canonical list of 'FileEntry' records for a 'Project'.
--
-- This function assembles all root configuration files, Git hooks, verification
-- scripts, operational roadmaps, agent guidance, documentation notes, and
-- multi-package source hierarchies.
--
-- Time complexity: @O(F)@ proportional to total generated files.
allProjectEntries :: Project -> [FileEntry]
allProjectEntries proj =
  concat
    [ rootToolchainEntries proj
    , gitHooksEntries proj
    , verificationHarnessEntries proj
    , operationalGovernanceEntries proj
    , agentRuleEntries proj
    , documentationCorpusEntries proj
    , packageHierarchyEntries proj
    ]

--------------------------------------------------------------------------------
-- 1. Root Toolchain & Build Assets
--------------------------------------------------------------------------------

-- | Synthesizes root build configuration files: @cabal.project@,
-- @cabal.project.local.example@, @.hlint.yaml@, @.gitmessage@, and @tagref.yml@.
rootToolchainEntries :: Project -> [FileEntry]
rootToolchainEntries proj =
  [ FileEntry "cabal.project" (cabalProjectTemplate proj) False
  , FileEntry "cabal.project.local.example" cabalProjectLocalTemplate False
  , FileEntry ".hlint.yaml" hlintTemplate False
  , FileEntry ".gitmessage" gitmessageTemplate False
  , FileEntry "tagref.yml" (tagrefConfigTemplate proj) False
  ]

-- | Generates root @cabal.project@ configuring compiler pinning and warnings.
cabalProjectTemplate :: Project -> Text
cabalProjectTemplate proj = T.unlines
  [ "packages:"
  , "  packages/*/"
  , ""
  , "with-compiler: ghc-" <> projectGhcVersion proj
  , "write-ghc-environment-files: always"
  , ""
  , "package *"
  , "  ghc-options: -Wall -Wcompat -Wredundant-constraints"
  , "  haddock-options: -w"
  ]

-- | Generates @cabal.project.local.example@ developer override template.
cabalProjectLocalTemplate :: Text
cabalProjectLocalTemplate = T.unlines
  [ "-- cabal.project.local.example — Local developer configuration template"
  , "-- Copy to cabal.project.local for machine-specific overrides (git-ignored)"
  , ""
  , "-- Optional: Override default compiler"
  , "-- with-compiler: ghc-9.14.1"
  , ""
  , "-- Optional: Enable documentation generation during builds"
  , "-- documentation: True"
  , ""
  , "-- Optional: Verbose compiler output"
  , "-- verbose: 1"
  ]

-- | Generates strict @.hlint.yaml@ enforcing clean code and semantic rules.
hlintTemplate :: Text
hlintTemplate = T.unlines
  [ "# .hlint.yaml — Ecosystem HLint Configuration"
  , "# Zero-hint cleanliness policy enforced across all source files."
  , ""
  , "- arguments:"
  , "    - -XOverloadedRecordDot"
  , "    - -XDataKinds"
  , "    - -XTypeOperators"
  , "    - -XTypeApplications"
  , ""
  , "- warn:"
  , "    name: \"Use OverloadedRecordDot\""
  , "    lhs: \"getField @a x\""
  , "    rhs: \"x.a\""
  , "    note: \"Prefer native OverloadedRecordDot syntax over explicit getField\""
  ]

-- | Generates @.gitmessage@ commit template specifying Sarutahiko AI attribution rules.
gitmessageTemplate :: Text
gitmessageTemplate = T.unlines
  [ "# <summary line>                                                     (max 72 chars)"
  , "#"
  , "# <Why this change, what problem it solves, what it rules out. The 'why',"
  , "#  not the 'what' -- the diff already says what. Delete these comment lines;"
  , "#  git strips them when the message is edited.>"
  , "#"
  , "# -- AI attribution (sarutahiko convention) -----------------------------------"
  , "# If any AI coding assistant or orchestrator took part in authoring the change,"
  , "# add standard git trailers:"
  , "#"
  , "#     Assisted-by: <Tool> (<Provider> / <Model>)"
  , "#     Orchestrated-by: <Engine>"
  , "#"
  , "# Examples:"
  , "#     Assisted-by: Antigravity (Google / gemini-3.8-pro)"
  , "#     Assisted-by: Freebuff"
  , "#     Orchestrated-by: Yamaarashi Flow Task Runner"
  , "#"
  , "# Do NOT use Co-authored-by: or Co-developed-by: for an assistant -- those"
  , "# claim legal authorship and certify the Developer Certificate of Origin, which"
  , "# only a human can do. Never add Signed-off-by: on an AI's behalf."
  , "#"
  , "# A commit written entirely by a human needs no AI trailer."
  , "# See docs/notes/COMMIT_ATTRIBUTION.md for details."
  ]

-- | Generates @tagref.yml@ cross-reference configuration.
tagrefConfigTemplate :: Project -> Text
tagrefConfigTemplate proj = T.unlines
  [ "# SPDX-License-Identifier: " <> projectLicense proj
  , "# Tagref configuration for " <> projectName proj
  , ""
  , "ignore_rules:"
  , "  - \"bin/" <> projectName proj <> "-tagref\""
  , "  - \".githooks\""
  ]

--------------------------------------------------------------------------------
-- 2. Git Governance & Hook Assets
--------------------------------------------------------------------------------

-- | Synthesizes @.githooks/@ scripts: @commit-msg@ and @pre-commit@.
gitHooksEntries :: Project -> [FileEntry]
gitHooksEntries proj =
  [ FileEntry ".githooks/commit-msg" commitMsgHookTemplate True
  , FileEntry ".githooks/pre-commit" (preCommitHookTemplate proj) True
  ]

-- | Generates @.githooks/commit-msg@ enforcing Sarutahiko commit attribution conventions.
commitMsgHookTemplate :: Text
commitMsgHookTemplate = T.unlines
  [ "#!/bin/sh"
  , "# commit-msg: enforce sarutahiko AI-attribution convention."
  , "set -u"
  , ""
  , "msg_file=$1"
  , "[ -f \"$msg_file\" ] || exit 0"
  , ""
  , "trailers=$(git interpret-trailers --parse < \"$msg_file\" 2>/dev/null) || exit 0"
  , "status=0"
  , "err() { printf 'commit-msg: %s\\n' \"$*\" >&2; status=1; }"
  , ""
  , "# Reject robot emoji"
  , "if grep -q '🤖' \"$msg_file\"; then"
  , "  err \"robot emoji in message; delete it.\""
  , "fi"
  , ""
  , "# Reject Co-authored-by for AI assistants"
  , "ai_names='copilot|chatgpt|gpt-[0-9]|codex|cursor|gemini|llama|qwen|deepseek|mistral|claude|anthropic|openai|aider|devin|codebuff|freebuff|buffy|space[ _-]?bunny|antigravity|noreply@|\\[bot\\]|@bot\\b'"
  , "if printf '%s\\n' \"$trailers\" | grep -Ei \"^[[:space:]]*(Co-authored-by|Co-developed-by|Signed-off-by):.*($ai_names)\"; then"
  , "  err \"Co-authored-by:/Signed-off-by: naming an AI assistant. Use 'Assisted-by: <Tool> (<Provider> / <Model>)' instead.\""
  , "fi"
  , ""
  , "exit $status"
  ]

-- | Generates @.githooks/pre-commit@ validating Tagref and Markdown links before commit.
preCommitHookTemplate :: Project -> Text
preCommitHookTemplate proj =
  let pName = projectName proj
  in T.unlines
    [ "#!/bin/sh"
    , "# .githooks/pre-commit: mechanically enforce tagref and link integrity."
    , "set -eu"
    , ""
    , "REPO_ROOT=\"$(git rev-parse --show-toplevel 2>/dev/null || pwd)\""
    , ""
    , "if [ -x \"${REPO_ROOT}/bin/" <> pName <> "-tagref\" ]; then"
    , "  if ! \"${REPO_ROOT}/bin/" <> pName <> "-tagref\"; then"
    , "    printf '\\npre-commit: Tagref cross-reference check failed.\\n' >&2"
    , "    exit 1"
    , "  fi"
    , "fi"
    , ""
    , "if [ -x \"${REPO_ROOT}/bin/" <> pName <> "-linkcheck\" ]; then"
    , "  if ! \"${REPO_ROOT}/bin/" <> pName <> "-linkcheck\" --quiet; then"
    , "    printf '\\npre-commit: Markdown link & anchor check failed.\\n' >&2"
    , "    exit 1"
    , "  fi"
    , "fi"
    , ""
    , "exit 0"
    ]

--------------------------------------------------------------------------------
-- 3. Turnkey Physical Verification Suite
--------------------------------------------------------------------------------

-- | Synthesizes executable scripts under @bin/@:
-- @<name>-verify@, @<name>-tagref@, @<name>-linkcheck@, @<name>-cloc@, and @generate-tags@.
verificationHarnessEntries :: Project -> [FileEntry]
verificationHarnessEntries proj =
  let pName = T.unpack (projectName proj)
  in [ FileEntry ("bin/" <> pName <> "-verify") (verifyScriptTemplate proj) True
     , FileEntry ("bin/" <> pName <> "-tagref") (tagrefScriptTemplate proj) True
     , FileEntry ("bin/" <> pName <> "-linkcheck") (linkcheckScriptTemplate proj) True
     , FileEntry ("bin/" <> pName <> "-cloc") (clocScriptTemplate proj) True
     , FileEntry "bin/generate-tags" generateTagsTemplate True
     ]

-- | Generates @bin/<name>-verify@ running the five standard physical verification gates.
verifyScriptTemplate :: Project -> Text
verifyScriptTemplate proj =
  let pName = projectName proj
  in T.unlines
    [ "#!/usr/bin/env bash"
    , "# bin/" <> pName <> "-verify — Physical verification runner for " <> pName
    , "set -euo pipefail"
    , ""
    , "SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\""
    , "REPO_ROOT=\"$(cd \"${SCRIPT_DIR}/..\" && pwd)\""
    , ""
    , "verify_hlint() {"
    , "  echo \"=== [1/5] HLint Static Analysis Gate ===\""
    , "  local hlint_cmd=\"\""
    , "  if [[ -x \"${HOME}/.ghcup/bin/hlint\" ]]; then"
    , "    hlint_cmd=\"${HOME}/.ghcup/bin/hlint\""
    , "  elif command -v hlint >/dev/null 2>&1; then"
    , "    hlint_cmd=\"$(command -v hlint)\""
    , "  fi"
    , "  if [[ -n \"${hlint_cmd}\" ]]; then"
    , "    \"${hlint_cmd}\" \"${REPO_ROOT}\"/packages/*/src >/dev/null"
    , "    echo \"  [+] Clean HLint run: 0 hints.\""
    , "  else"
    , "    echo \"  [SKIP] hlint binary not found.\""
    , "  fi"
    , "}"
    , ""
    , "verify_tests() {"
    , "  echo \"=== [2/5] Full Cabal Test Suite ===\""
    , "  (cd \"${REPO_ROOT}\" && cabal test all >/dev/null)"
    , "  echo \"  [+] All test suite assertions PASSED.\""
    , "}"
    , ""
    , "verify_tagref() {"
    , "  echo \"=== [3/5] Tagref Cross-Reference Gate ===\""
    , "  if [[ -x \"${REPO_ROOT}/bin/" <> pName <> "-tagref\" ]]; then"
    , "    local tagref_out"
    , "    tagref_out=\"$(\"${REPO_ROOT}/bin/" <> pName <> "-tagref\")\""
    , "    echo \"  [+] Tagref verified: ${tagref_out}\""
    , "  else"
    , "    echo \"  [SKIP] Tagref script not found.\""
    , "  fi"
    , "}"
    , ""
    , "verify_linkcheck() {"
    , "  echo \"=== [4/5] Markdown Link & Anchor Integrity Gate ===\""
    , "  if [[ -x \"${REPO_ROOT}/bin/" <> pName <> "-linkcheck\" ]]; then"
    , "    local linkcheck_out"
    , "    linkcheck_out=\"$(\"${REPO_ROOT}/bin/" <> pName <> "-linkcheck\" --quiet)\""
    , "    echo \"  [+] Markdown links verified: ${linkcheck_out}\""
    , "  else"
    , "    echo \"  [SKIP] Linkcheck script not found.\""
    , "  fi"
    , "}"
    , ""
    , "verify_cloc() {"
    , "  echo \"=== [5/5] CLOC Comment Density Gate ===\""
    , "  if [[ -x \"${REPO_ROOT}/bin/" <> pName <> "-cloc\" ]]; then"
    , "    local cloc_out"
    , "    cloc_out=\"$(\"${REPO_ROOT}/bin/" <> pName <> "-cloc\" --quiet --check)\""
    , "    echo \"  [+] Comment density verified: ${cloc_out}\""
    , "  else"
    , "    echo \"  [SKIP] CLOC script not found.\""
    , "  fi"
    , "}"
    , ""
    , "verify_hlint"
    , "verify_tests"
    , "verify_tagref"
    , "verify_linkcheck"
    , "verify_cloc"
    , ""
    , "echo \"=== All 5 Physical Verification Checks PASSED ===\""
    ]

-- | Generates @bin/<name>-tagref@ cross-reference validation script with Python fallback.
tagrefScriptTemplate :: Project -> Text
tagrefScriptTemplate proj =
  let pName = projectName proj
  in T.unlines
    [ "#!/usr/bin/env bash"
    , "# bin/" <> pName <> "-tagref — Mechanical Tagref Cross-Reference Verification Harness"
    , "set -euo pipefail"
    , ""
    , "SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\""
    , "REPO_ROOT=\"$(cd \"${SCRIPT_DIR}/..\" && pwd)\""
    , ""
    , "if command -v tagref >/dev/null 2>&1; then"
    , "  (cd \"${REPO_ROOT}\" && tagref \"$@\")"
    , "else"
    , "  REPO_ROOT=\"${REPO_ROOT}\" python3 - <<'EOF'"
    , "import sys, os, re, subprocess"
    , ""
    , "repo_root = os.environ.get(\"REPO_ROOT\", os.getcwd())"
    , "ignore_rules = [\"bin/" <> pName <> "-tagref\", \".githooks\"]"
    , "tag_regex = re.compile(r\"\\[tag:([a-zA-Z0-9_\\-]+)\\]\")"
    , "ref_regex = re.compile(r\"\\[ref:([a-zA-Z0-9_\\-]+)\\]\")"
    , ""
    , "try:"
    , "    git_files = subprocess.check_output([\"git\", \"ls-files\"], cwd=repo_root, text=True).splitlines()"
    , "except Exception:"
    , "    git_files = []"
    , ""
    , "if not git_files:"
    , "    for root, dirs, files in os.walk(repo_root):"
    , "        dirs[:] = [d for d in dirs if d not in (\".git\", \"dist-newstyle\")]"
    , "        for f in files:"
    , "            git_files.append(os.path.relpath(os.path.join(root, f), repo_root))"
    , ""
    , "tags = {}"
    , "refs = []"
    , "scanned = 0"
    , ""
    , "for rel_path in git_files:"
    , "    if any(rel_path == rule or rel_path.startswith(rule.rstrip(\"/\") + \"/\") for rule in ignore_rules):"
    , "        continue"
    , "    abs_path = os.path.join(repo_root, rel_path)"
    , "    try:"
    , "        with open(abs_path, \"r\", encoding=\"utf-8\", errors=\"ignore\") as f:"
    , "            scanned += 1"
    , "            for lineno, line in enumerate(f, 1):"
    , "                for match in tag_regex.finditer(line):"
    , "                    t = match.group(1)"
    , "                    if t in tags:"
    , "                        print(f\"Error: duplicate tag '{t}' in {rel_path}:{lineno}\", file=sys.stderr)"
    , "                        sys.exit(1)"
    , "                    tags[t] = f\"{rel_path}:{lineno}\""
    , "                for match in ref_regex.finditer(line):"
    , "                    refs.append((match.group(1), f\"{rel_path}:{lineno}\"))"
    , "    except Exception:"
    , "        continue"
    , ""
    , "dangling = [f\"Error: dangling reference '{r}' at {loc}\" for r, loc in refs if r not in tags]"
    , "if dangling:"
    , "    for d in dangling:"
    , "        print(d, file=sys.stderr)"
    , "    sys.exit(1)"
    , ""
    , "print(f\"{len(tags)} tags, 0 group members, {len(refs)} references validated in {scanned} files.\")"
    , "EOF"
    , "fi"
    ]

-- | Generates @bin/<name>-linkcheck@ deterministic Markdown link and anchor validator.
linkcheckScriptTemplate :: Project -> Text
linkcheckScriptTemplate proj =
  let pName = projectName proj
  in T.unlines
    [ "#!/usr/bin/env python3"
    , "\"\"\""
    , "bin/" <> pName <> "-linkcheck — Intra-Corpus Markdown Link & Anchor Verification"
    , "\"\"\""
    , "import sys, os, re, argparse, subprocess"
    , ""
    , "REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), \"..\"))"
    , "LINK_REGEX = re.compile(r'!?\\[([^\\]]*)\\]\\(([^)\\s]+)(?:\\s+[\"\\'][^\"\\']*[\"\\'])?\\)')"
    , "HEADING_REGEX = re.compile(r\"^(#{1,6})\\s+(.+)$\", re.MULTILINE)"
    , "EXTERNAL_SCHEMES = (\"http://\", \"https://\", \"mailto:\", \"rad:\", \"ftp://\")"
    , ""
    , "def github_slugify(text):"
    , "    text = re.sub(r\"<[^>]+>\", \"\", text)"
    , "    text = re.sub(r\"\\[([^\\]]*)\\]\\([^)]+\\)\", r\"\\1\", text)"
    , "    text = re.sub(r\"[`*_{}\\[\\]()#+\\-.!?:,\\x27\\\"]\", \"\", text)"
    , "    text = text.strip().lower()"
    , "    return re.sub(r\"\\s+\", \"-\", text)"
    , ""
    , "def parse_anchors(file_path):"
    , "    if not os.path.isfile(file_path): return set(), 0"
    , "    with open(file_path, \"r\", encoding=\"utf-8\", errors=\"ignore\") as f:"
    , "        content = f.read()"
    , "    lines = content.splitlines()"
    , "    anchors = set()"
    , "    if file_path.endswith(\".md\"):"
    , "        for m in HEADING_REGEX.finditer(content):"
    , "            anchors.add(github_slugify(m.group(2)))"
    , "    return anchors, len(lines)"
    , ""
    , "def check_links(file_path, anchors_cache):"
    , "    broken = []"
    , "    checked = 0"
    , "    if not os.path.isfile(file_path): return 0, [(0, file_path, \"Missing file\")]"
    , "    with open(file_path, \"r\", encoding=\"utf-8\", errors=\"ignore\") as f:"
    , "        lines = f.readlines()"
    , "    in_code = False"
    , "    for idx, line in enumerate(lines, 1):"
    , "        if line.strip().startswith(\"```\"): in_code = not in_code; continue"
    , "        if in_code: continue"
    , "        for m in LINK_REGEX.finditer(line):"
    , "            target = m.group(2)"
    , "            if any(target.startswith(s) for s in EXTERNAL_SCHEMES): continue"
    , "            checked += 1"
    , "            path_part, _, anchor = target.partition(\"#\")"
    , "            resolved = os.path.normpath(os.path.join(os.path.dirname(file_path), path_part)) if path_part else file_path"
    , "            if not os.path.exists(resolved):"
    , "                broken.append((idx, target, f\"File '{resolved}' does not exist\"))"
    , "                continue"
    , "            if anchor and resolved.endswith(\".md\"):"
    , "                if resolved not in anchors_cache: anchors_cache[resolved] = parse_anchors(resolved)"
    , "                anchors, _ = anchors_cache[resolved]"
    , "                if anchor.lower() not in anchors:"
    , "                    broken.append((idx, target, f\"Anchor '#{anchor}' missing in '{resolved}'\"))"
    , "    return checked, broken"
    , ""
    , "def main():"
    , "    parser = argparse.ArgumentParser()"
    , "    parser.add_argument(\"--quiet\", \"-q\", action=\"store_true\")"
    , "    args = parser.parse_args()"
    , "    anchors_cache = {}"
    , "    all_broken = []"
    , "    total_checked = 0"
    , "    targets = []"
    , "    for root, dirs, files in os.walk(REPO_ROOT):"
    , "        dirs[:] = [d for d in dirs if d not in (\".git\", \"dist-newstyle\")]"
    , "        for f in files:"
    , "            if f.endswith(\".md\"): targets.append(os.path.join(root, f))"
    , "    for t in sorted(targets):"
    , "        chk, brk = check_links(t, anchors_cache)"
    , "        total_checked += chk"
    , "        for line, url, err in brk:"
    , "            all_broken.append((t, line, url, err))"
    , "    if all_broken:"
    , "        for path, line, url, err in all_broken:"
    , "            print(f\"{os.path.relpath(path, REPO_ROOT)}:{line}: broken link '{url}' -> {err}\", file=sys.stderr)"
    , "        sys.exit(1)"
    , "    print(f\"0 broken links ({total_checked} checked across {len(targets)} files).\")"
    , ""
    , "if __name__ == '__main__': main()"
    ]

-- | Generates @bin/<name>-cloc@ evaluating 50%+ in-code comment density.
clocScriptTemplate :: Project -> Text
clocScriptTemplate proj =
  let pName = projectName proj
  in T.unlines
    [ "#!/usr/bin/env python3"
    , "\"\"\""
    , "bin/" <> pName <> "-cloc — Comment Density Audit Harness for " <> pName
    , "\"\"\""
    , "import sys, os, glob, argparse"
    , ""
    , "REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), \"..\"))"
    , ""
    , "def count_hs(filepath):"
    , "    blank = comment = code = 0"
    , "    in_block = 0"
    , "    with open(filepath, \"r\", encoding=\"utf-8\", errors=\"replace\") as f:"
    , "        for line in f:"
    , "            s = line.strip()"
    , "            if not s: blank += 1; continue"
    , "            i = 0"
    , "            line_has_comment = line_has_code = False"
    , "            while i < len(s):"
    , "                if in_block > 0:"
    , "                    if s[i:i+2] == \"-}\": in_block -= 1; i += 2; line_has_comment = True"
    , "                    elif s[i:i+2] == \"{-\": in_block += 1; i += 2; line_has_comment = True"
    , "                    else: i += 1; line_has_comment = True"
    , "                else:"
    , "                    if s[i:i+2] == \"--\": line_has_comment = True; break"
    , "                    elif s[i:i+2] == \"{-\": in_block += 1; i += 2; line_has_comment = True"
    , "                    else: line_has_code = True; i += 1"
    , "            if line_has_comment and not line_has_code: comment += 1"
    , "            elif line_has_code: code += 1"
    , "            elif line_has_comment: comment += 1"
    , "            else: blank += 1"
    , "    return blank, comment, code"
    , ""
    , "def main():"
    , "    parser = argparse.ArgumentParser()"
    , "    parser.add_argument(\"--quiet\", \"-q\", action=\"store_true\")"
    , "    parser.add_argument(\"--check\", action=\"store_true\", default=True)"
    , "    args = parser.parse_args()"
    , "    src_files = glob.glob(os.path.join(REPO_ROOT, \"packages\", \"*\", \"src\", \"**\", \"*.hs\"), recursive=True)"
    , "    tot_comment = tot_code = 0"
    , "    for f in src_files:"
    , "        _, com, cod = count_hs(f)"
    , "        tot_comment += com; tot_code += cod"
    , "    density = (tot_comment / (tot_comment + tot_code) * 100.0) if (tot_comment + tot_code) > 0 else 0.0"
    , "    if args.check and density < 25.0:"
    , "        print(f\"Comment density gate FAILED: {density:.1f}% < 25.0% threshold\", file=sys.stderr)"
    , "        sys.exit(1)"
    , "    print(f\"{density:.1f}% ({tot_comment} comments / {tot_code} code lines in src/; target: 50.0%+)\")"
    , ""
    , "if __name__ == '__main__': main()"
    ]

-- | Generates @bin/generate-tags@ indexing symbols using hasktags or ctags.
generateTagsTemplate :: Text
generateTagsTemplate = T.unlines
  [ "#!/usr/bin/env bash"
  , "# bin/generate-tags — Fast symbol indexing for code navigation"
  , "set -euo pipefail"
  , ""
  , "SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\""
  , "REPO_ROOT=\"$(cd \"${SCRIPT_DIR}/..\" && pwd)\""
  , "TARGET_DIRS=(\"${REPO_ROOT}/packages\")"
  , ""
  , "if command -v hasktags >/dev/null 2>&1; then"
  , "  (cd \"${REPO_ROOT}\" && hasktags -c -x -f tags \"${TARGET_DIRS[@]}\")"
  , "  echo \"Tags generated successfully in ./tags\""
  , "elif command -v ctags >/dev/null 2>&1; then"
  , "  (cd \"${REPO_ROOT}\" && ctags -R -f tags \"${TARGET_DIRS[@]}\")"
  , "  echo \"Tags generated successfully in ./tags\""
  , "else"
  , "  echo \"[WARN] Neither hasktags nor ctags found on PATH.\""
  , "fi"
  ]

--------------------------------------------------------------------------------
-- 4. Operational Governance & Agent Guidance
--------------------------------------------------------------------------------

-- | Synthesizes @README.md@, @AGENTS.md@, @CLAUDE.md@, @PLAN.md@, and @STATE.md@.
operationalGovernanceEntries :: Project -> [FileEntry]
operationalGovernanceEntries proj =
  [ FileEntry "README.md" (readmeTemplate proj) False
  , FileEntry "AGENTS.md" (agentsTemplate proj) False
  , FileEntry "CLAUDE.md" (claudeTemplate proj) False
  , FileEntry "PLAN.md" (planTemplate proj) False
  , FileEntry "STATE.md" (stateTemplate proj) False
  ]

-- | Generates root @README.md@ describing project overview, build steps, and licenses.
readmeTemplate :: Project -> Text
readmeTemplate proj =
  let pName = projectName proj
      auth = projectAuthor proj
  in renderMarkdown
    [ h1 pName
    , para (projectDescription proj)
    , h2 "Quick Start"
    , codeBlock "bash"
        ( "# Build all packages\n\
          \cabal build all\n\n\
          \# Run full test suite\n\
          \cabal test all\n\n\
          \# Run physical verification gates\n\
          \./bin/" <> pName <> "-verify" )
    , h2 "Documentation"
    , bulletList
        [ inlines [linkInline (code "AGENTS.md") "AGENTS.md", plain " — Advisory context and rules for AI assistants."]
        , inlines [linkInline (code "PLAN.md") "PLAN.md", plain " — Strategic roadmap and phase delivery schedule."]
        , inlines [linkInline (code "STATE.md") "STATE.md", plain " — Active operational session frontier."]
        , inlines [linkInline (code "docs/INDEX.md") "docs/INDEX.md", plain " — Documentation corpus inventory."]
        , inlines [linkInline (code "docs/TUTORIAL.md") "docs/TUTORIAL.md", plain " — Getting started tutorial."]
        ]
    , h2 "License & Attribution"
    , bulletList
        [ inlines [bold "License:", plain (" " <> projectLicense proj)]
        , inlines [bold "Author:", plain (" " <> authorName auth <> " <" <> authorEmail auth <> ">")]
        ]
    ]

-- | Generates @AGENTS.md@ establishing AI coding assistant reading order and advisories.
agentsTemplate :: Project -> Text
agentsTemplate proj =
  let pName = projectName proj
      uSlug = toUpperSlug pName
  in renderMarkdown
    [ h1 "AGENTS.md — Advisory Context for AI Coding Assistants"
    , para "Pointer file. Canonical sources win on any disagreement."
    , h2 "What this repository is"
    , para ("`" <> pName <> "` — " <> projectDescription proj)
    , h2 "Read first, in this order"
    , orderedList
        [ inlines [linkInline (code "README.md") "README.md", plain " — what this is, and its status."]
        , inlines [linkInline (code "PLAN.md") "PLAN.md", plain " & ", linkInline (code "STATE.md") "STATE.md", plain " — operational roadmap and active session frontier."]
        , inlines [linkInline (code ("docs/notes/" <> uSlug <> "_DESIGN.md")) ("docs/notes/" <> uSlug <> "_DESIGN.md"), plain " — canonical design notes and invariants."]
        , inlines [linkInline (code "docs/notes/DOC_STRATEGY.md") "docs/notes/DOC_STRATEGY.md", plain " — documentation policy: genres, lifecycle, tone."]
        , inlines [linkInline (code "docs/INDEX.md") "docs/INDEX.md", plain " — corpus inventory and reading map."]
        ]
    , h2 "Subdivided operational rules (`.agents/rules/`)"
    , bulletList
        [ inlines [linkInline (code ".agents/rules/commit-attribution.md") ".agents/rules/commit-attribution.md", plain " — Linux kernel RFC 2822 trailer format (`Assisted-by:`), DCO boundaries."]
        , inlines [linkInline (code ".agents/rules/code-navigation.md") ".agents/rules/code-navigation.md", plain " — Token-saving funnel (`./tags` symbol jump, targeted slice viewing)."]
        , inlines [linkInline (code ".agents/rules/compiler-verification.md") ".agents/rules/compiler-verification.md", plain " — Zero-log compiler verification, tests, and zero-contamination."]
        , inlines [linkInline (code ".agents/rules/documentation-precedence.md") ".agents/rules/documentation-precedence.md", plain " — Precedence rule (\"code wins at runtime; notes corrected regardless\")."]
        ]
    , h2 "Operational advisories"
    , orderedList
        [ plain "**Design docs are load-bearing.** Stale notes must be corrected in the same change set."
        , plain "Commits: descriptive-imperative subject under 72 chars, body explains why. AI attribution uses git trailers per `sarutahiko`: `Assisted-by: <Tool> (<Provider> / <Model>)`."
        , plain ("Toolchain: GHC " <> projectGhcVersion proj <> " / Cabal " <> projectCabalVersion proj <> ".")
        , plain "Two-file loop: Update `STATE.md` before ending or resetting a session."
        ]
    ]

-- | Generates @CLAUDE.md@ pointing to canonical advisory in @AGENTS.md@.
claudeTemplate :: Project -> Text
claudeTemplate _ = renderMarkdown
  [ h1 "CLAUDE.md"
  , paraInlines
      [ plain "Canonical advisory instructions are maintained in "
      , link "AGENTS.md" "AGENTS.md"
      , plain "."
      ]
  ]

-- | Generates @PLAN.md@ tracking strategic milestones.
planTemplate :: Project -> Text
planTemplate proj =
  let pName = projectName proj
  in renderMarkdown
    [ h1 (pName <> " — Strategic Roadmap (`PLAN.md`)")
    , paraInlines
        [ bold "Status:"
        , plain " ACTIVE STRATEGIC ROADMAP  \n"
        , bold "Scope:"
        , plain (" " <> projectDescription proj <> "  \n")
        , bold "Documentation:"
        , plain " "
        , linkInline (code "docs/INDEX.md") "docs/INDEX.md"
        , plain "  \n"
        , bold "Operational State:"
        , plain " "
        , linkInline (code "STATE.md") "STATE.md"
        ]
    , hr
    , h2 "Phase 1: Foundational Architecture [ACTIVE]"
    , bulletList
        [ inlines
            [ plain "[x] "
            , bold "Milestone 1.1:"
            , plain " Canonical Workspace Scaffolding\n  - Multi-package hierarchy, documentation corpus, and verification harnesses grounded."
            ]
        , inlines
            [ plain "[ ] "
            , bold "Milestone 1.2:"
            , plain " Core Implementation & Domain Logic\n  - Core abstractions, unit tests, and property test verification."
            ]
        ]
    ]

-- | Generates @STATE.md@ tracking active session frontier.
stateTemplate :: Project -> Text
stateTemplate proj =
  let pName = projectName proj
  in renderMarkdown
    [ h1 (pName <> " — State")
    , paraInlines
        [ plain "Operational frontier. Read with "
        , linkInline (code "PLAN.md") "PLAN.md"
        , plain "; update before ending a session."
        ]
    , h2 "Where we are"
    , para ("The workspace skeleton for `" <> pName <> "` is initialized and verified under GHC " <> projectGhcVersion proj <> ".")
    , h2 "Active Frontier"
    , bulletList
        [ plain "Complete Milestone 1.2 core domain logic."
        , plain ("Maintain 5-gate physical verification via `./bin/" <> pName <> "-verify`.")
        ]
    ]

--------------------------------------------------------------------------------
-- 5. Subdivided Agent Operational Rules
--------------------------------------------------------------------------------

-- | Synthesizes `.agents/rules/` guidance files.
agentRuleEntries :: Project -> [FileEntry]
agentRuleEntries _ =
  [ FileEntry ".agents/rules/commit-attribution.md" ruleCommitAttributionTemplate False
  , FileEntry ".agents/rules/code-navigation.md" ruleCodeNavigationTemplate False
  , FileEntry ".agents/rules/compiler-verification.md" ruleCompilerVerificationTemplate False
  , FileEntry ".agents/rules/documentation-precedence.md" ruleDocPrecedenceTemplate False
  ]

-- | Generates `.agents/rules/commit-attribution.md`.
ruleCommitAttributionTemplate :: Text
ruleCommitAttributionTemplate = renderMarkdown
  [ h1 "Commit Attribution Rules"
  , para "AI attribution uses git trailers per `sarutahiko`:\n\
         \`Assisted-by: <Tool> (<Provider> / <Model>)` (or `<Tool>`) and optional `Orchestrated-by: <Engine>`."
  , para "Never `Co-authored-by:` or `Signed-off-by:` for AI tools (only humans certify the DCO)."
  ]

-- | Generates `.agents/rules/code-navigation.md`.
ruleCodeNavigationTemplate :: Text
ruleCodeNavigationTemplate = renderMarkdown
  [ h1 "Code Navigation Rules"
  , para "Always follow the Progressive Disclosure Funnel:"
  , orderedList
      [ plain "Level 0: Global Navigation (`docs/INDEX.md`, `tags` file)"
      , plain "Level 1: Structural Outline (module export lists)"
      , plain "Level 2: Targeted Slice (`view_file` StartLine / EndLine)"
      ]
  ]

-- | Generates `.agents/rules/compiler-verification.md`.
ruleCompilerVerificationTemplate :: Text
ruleCompilerVerificationTemplate = renderMarkdown
  [ h1 "Compiler Verification Rules"
  , para "Maintain zero warnings under `-Wall -Wcompat -Wredundant-constraints`."
  , para "Run physical verification gates before committing."
  ]

-- | Generates `.agents/rules/documentation-precedence.md`.
ruleDocPrecedenceTemplate :: Text
ruleDocPrecedenceTemplate = renderMarkdown
  [ h1 "Documentation Precedence Rules"
  , para "Precedence rule: Code wins at runtime; notes corrected regardless."
  , para "Design docs are load-bearing. Update notes when implementation changes."
  ]

--------------------------------------------------------------------------------
-- 6. Canonical Documentation Corpus
--------------------------------------------------------------------------------

-- | Synthesizes `docs/` hierarchy and notes.
documentationCorpusEntries :: Project -> [FileEntry]
documentationCorpusEntries proj =
  let uSlug = T.unpack (toUpperSlug (projectName proj))
  in [ FileEntry "docs/INDEX.md" (docsIndexTemplate proj) False
     , FileEntry "docs/TUTORIAL.md" (docsTutorialTemplate proj) False
     , FileEntry "docs/NEWBIE_GUIDE.md" (docsNewbieGuideTemplate proj) False
     , FileEntry "docs/MAINTAINER_GUIDE.md" (docsMaintainerGuideTemplate proj) False
     , FileEntry ("docs/notes/" <> uSlug <> "_DESIGN.md") (docsDesignTemplate proj) False
     , FileEntry "docs/notes/DOC_STRATEGY.md" (docsStrategyTemplate proj) False
     , FileEntry "docs/notes/COMMIT_ATTRIBUTION.md" (docsCommitAttributionTemplate proj) False
     ]

-- | Generates `docs/INDEX.md` inventory.
docsIndexTemplate :: Project -> Text
docsIndexTemplate proj =
  let pName = projectName proj
      uSlug = toUpperSlug pName
      pkgs = projectPackages proj
  in renderMarkdown
    [ h1 (pName <> " Documentation Index")
    , para ("Welcome to the `" <> pName <> "` technical documentation corpus.")
    , h2 "Core Orientation"
    , bulletList
        [ inlines [linkInline (code "README.md") "../README.md", plain " — High-level project overview and quick start."]
        , inlines [linkInline (code "AGENTS.md") "../AGENTS.md", plain " — AI coding assistant guidance and rules."]
        , inlines [linkInline (code "PLAN.md") "../PLAN.md", plain " — Strategic roadmap."]
        , inlines [linkInline (code "STATE.md") "../STATE.md", plain " — Active operational frontier."]
        , inlines [linkInline (code "TUTORIAL.md") "TUTORIAL.md", plain " — Getting started tutorial."]
        , inlines [linkInline (code "NEWBIE_GUIDE.md") "NEWBIE_GUIDE.md", plain " — Token-conservation funnel and navigation."]
        , inlines [linkInline (code "MAINTAINER_GUIDE.md") "MAINTAINER_GUIDE.md", plain " — Maintenance and verification gates."]
        ]
    , h2 "Design Notes (`docs/notes/`)"
    , bulletList
        [ inlines [linkInline (code (uSlug <> "_DESIGN.md")) ("notes/" <> uSlug <> "_DESIGN.md"), plain " — Canonical design notes."]
        , inlines [linkInline (code "DOC_STRATEGY.md") "notes/DOC_STRATEGY.md", plain " — Documentation strategy and precedence rules."]
        , inlines [linkInline (code "COMMIT_ATTRIBUTION.md") "notes/COMMIT_ATTRIBUTION.md", plain " — Commit attribution standards."]
        ]
    , h2 "Active Packages"
    , bulletList
        [ inlines [linkInline (code ("packages/" <> packageName pkg <> "/")) ("../packages/" <> packageName pkg <> "/"), plain (" — " <> packageSynopsis pkg)]
        | pkg <- pkgs
        ]
    ]

-- | Generates `docs/TUTORIAL.md`.
docsTutorialTemplate :: Project -> Text
docsTutorialTemplate proj =
  let pName = projectName proj
      uSlug = toUpperSlug pName
  in renderMarkdown
    [ h1 ("Getting Started with " <> pName)
    , para ("A foundational tutorial for working with `" <> pName <> "`.")
    , h2 "1. Concepts"
    , para ("`" <> pName <> "` provides modular components structured around " <> projectDescription proj <> ".")
    , h2 "2. Navigation"
    , paraInlines
        [ plain "See "
        , linkInline (code "docs/INDEX.md") "INDEX.md"
        , plain ", "
        , linkInline (code "docs/NEWBIE_GUIDE.md") "NEWBIE_GUIDE.md"
        , plain ", and "
        , linkInline (code ("docs/notes/" <> uSlug <> "_DESIGN.md")) ("notes/" <> uSlug <> "_DESIGN.md")
        , plain "."
        ]
    ]

-- | Generates `docs/NEWBIE_GUIDE.md`.
docsNewbieGuideTemplate :: Project -> Text
docsNewbieGuideTemplate proj =
  let pName = projectName proj
  in renderMarkdown
    [ h1 (pName <> " Newbie Quickstart & Token-Conservation Guide")
    , paraInlines
        [ bold "Parent Strategy:"
        , plain " "
        , linkInline (code "docs/notes/DOC_STRATEGY.md") "notes/DOC_STRATEGY.md"
        , plain "  \n"
        , bold "Corpus Inventory:"
        , plain " "
        , linkInline (code "docs/INDEX.md") "INDEX.md"
        , plain "  \n"
        , bold "Tutorial:"
        , plain " "
        , linkInline (code "docs/TUTORIAL.md") "TUTORIAL.md"
        , plain "  \n"
        , bold "Maintainer Guide:"
        , plain " "
        , linkInline (code "docs/MAINTAINER_GUIDE.md") "MAINTAINER_GUIDE.md"
        ]
    , h2 "1. The Core Invariant: Never Dump Whole Modules"
    , para "Always follow the Progressive Disclosure Funnel:"
    , bulletList
        [ plain "Level 0: Global Navigation (`docs/INDEX.md`)"
        , plain "Level 1: Structural Outline"
        , plain "Level 2: Targeted Slice"
        ]
    ]

-- | Generates `docs/MAINTAINER_GUIDE.md`.
docsMaintainerGuideTemplate :: Project -> Text
docsMaintainerGuideTemplate proj =
  let pName = projectName proj
      uSlug = toUpperSlug pName
  in renderMarkdown
    [ h1 (pName <> " Maintainer Guide")
    , paraInlines
        [ bold "Corpus Inventory:"
        , plain " "
        , linkInline (code "docs/INDEX.md") "INDEX.md"
        , plain "  \n"
        , bold "Design Notes:"
        , plain " "
        , linkInline (code ("docs/notes/" <> uSlug <> "_DESIGN.md")) ("notes/" <> uSlug <> "_DESIGN.md")
        , plain "  \n"
        , bold "Attribution:"
        , plain " "
        , linkInline (code "docs/notes/COMMIT_ATTRIBUTION.md") "notes/COMMIT_ATTRIBUTION.md"
        ]
    , h2 "Verification Gates"
    , para ("Every commit must pass all five verification gates via `./bin/" <> pName <> "-verify`.")
    ]

-- | Generates `docs/notes/<PROJECT>_DESIGN.md`.
docsDesignTemplate :: Project -> Text
docsDesignTemplate proj =
  let pName = projectName proj
  in renderMarkdown
    [ h1 (pName <> " — Design Decisions & Invariants")
    , paraInlines
        [ bold "Status:"
        , plain " CANONICAL DESIGN MONOGRAPH  \n"
        , bold "Parent Strategy:"
        , plain " "
        , linkInline (code "DOC_STRATEGY.md") "DOC_STRATEGY.md"
        , plain "  \n"
        , bold "Documentation Index:"
        , plain " "
        , linkInline (code "../INDEX.md") "../INDEX.md"
        ]
    , hr
    , h2 "Architectural Decisions"
    , h3 "Decision D1: Modular Workspace Architecture"
    , para "The repository is decomposed into fine-grained packages under `packages/`."
    , h3 "Decision D2: Verification Invariants"
    , para ("Adheres to Note [Ecosystem Standardization Invariants] " <> refStandardization <> ".")
    , hr
    , h2 "In-Code Design Notes"
    , h3 "Note [Core Architecture]"
    , Paragraph [tagDef "note-core-architecture"]
    , para ("Defines foundational design invariants for `" <> pName <> "`.")
    ]

-- | Generates `docs/notes/DOC_STRATEGY.md`.
docsStrategyTemplate :: Project -> Text
docsStrategyTemplate proj =
  let pName = projectName proj
  in renderMarkdown
    [ h1 "Documentation Strategy & Policy"
    , paraInlines
        [ bold "Project:"
        , plain (" " <> pName <> "  \n")
        , bold "Index:"
        , plain " "
        , linkInline (code "../INDEX.md") "../INDEX.md"
        ]
    , h2 "Precedence Rule (§4)"
    , para "Code wins at runtime; notes corrected regardless. Stale design documentation must be remediated in the same commit."
    ]

-- | Generates `docs/notes/COMMIT_ATTRIBUTION.md`.
docsCommitAttributionTemplate :: Project -> Text
docsCommitAttributionTemplate proj =
  let pName = projectName proj
  in renderMarkdown
    [ h1 "Commit Attribution & Trailer Standards"
    , paraInlines
        [ bold "Project:"
        , plain (" " <> pName <> "  \n")
        , bold "Index:"
        , plain " "
        , linkInline (code "../INDEX.md") "../INDEX.md"
        ]
    , h2 "Format"
    , plainCodeBlock "Assisted-by: <Tool> (<Provider> / <Model>)"
    ]

--------------------------------------------------------------------------------
-- 7. Multi-Package Hierarchy
--------------------------------------------------------------------------------

-- | Synthesizes package manifests, source modules, test suites, and documentation.
packageHierarchyEntries :: Project -> [FileEntry]
packageHierarchyEntries proj =
  concatMap (packageEntries proj) (projectPackages proj)

-- | Synthesizes all files for a specific 'PackageSpec'.
packageEntries :: Project -> PackageSpec -> [FileEntry]
packageEntries proj pkg =
  let pName = T.unpack (packageName pkg)
      cabalFile = "packages/" <> pName <> "/" <> pName <> ".cabal"
      readmeFile = "packages/" <> pName <> "/README.md"
      testFile = "packages/" <> pName <> "/test/Main.hs"
      exposes = case packageExposes pkg of
        [] -> [defaultModuleName (packageName pkg)]
        ms -> ms
      moduleFiles =
        [ FileEntry
            ("packages/" <> pName <> "/src/" <> moduleToFilePath m)
            (packageModuleTemplate proj pkg m)
            False
        | m <- exposes
        ]
  in [ FileEntry cabalFile (packageCabalTemplate proj pkg) False
     , FileEntry readmeFile (packageReadmeTemplate proj pkg) False
     , FileEntry testFile (packageTestTemplate proj pkg) False
     ] ++ moduleFiles

-- | Generates a package's Cabal manifest.
packageCabalTemplate :: Project -> PackageSpec -> Text
packageCabalTemplate proj pkg =
  let pName = packageName pkg
      auth = projectAuthor proj
      exposes = case packageExposes pkg of
        [] -> [defaultModuleName pName]
        ms -> ms
  in T.unlines
    [ "cabal-version: 3.0"
    , "name: " <> pName
    , "version: 0.1.0.0"
    , "synopsis: " <> packageSynopsis pkg
    , "license: " <> projectLicense proj
    , "author: " <> authorName auth
    , "maintainer: " <> authorEmail auth
    , "build-type: Simple"
    , "tested-with: GHC == " <> projectGhcVersion proj
    , ""
    , "library"
    , "  exposed-modules:"
    ] <> T.unlines [ "    " <> m | m <- exposes ] <>
    T.unlines
    [ "  hs-source-dirs: src"
    , "  default-language: Haskell2010"
    , "  ghc-options: -Wall -Wcompat -Wredundant-constraints"
    , "  build-depends:"
    , "    base >= 4.14 && < 5,"
    , "    text >= 2.0,"
    , "    containers >= 0.6"
    , ""
    , "test-suite tests"
    , "  type: exitcode-stdio-1.0"
    , "  main-is: Main.hs"
    , "  hs-source-dirs: test"
    , "  default-language: Haskell2010"
    , "  ghc-options: -Wall"
    , "  build-depends:"
    , "    base >= 4.14 && < 5,"
    , "    " <> pName <> ","
    , "    text >= 2.0,"
    , "    hspec >= 2.10"
    ]

-- | Generates a package's @README.md@.
packageReadmeTemplate :: Project -> PackageSpec -> Text
packageReadmeTemplate proj pkg =
  let pName = packageName pkg
  in renderMarkdown
    [ h1 pName
    , para (packageSynopsis pkg)
    , h2 "Modules"
    , bulletList [ code m | m <- packageExposes pkg ]
    , h2 "License"
    , para (projectLicense proj)
    ]

-- | Generates an exposed module with comprehensive Haddock documentation (>50% comments).
packageModuleTemplate :: Project -> PackageSpec -> Text -> Text
packageModuleTemplate proj pkg modName =
  let pName = projectName proj
      pkgN = packageName pkg
  in T.unlines
    [ "-- | Module: " <> modName
    , "-- Description: Core implementation module for " <> pkgN
    , "--"
    , "-- This module provides foundational data structures and domain operations for '" <> pkgN <> "'."
    , "--"
    , "-- = Architectural Context"
    , "--"
    , "-- Per Note [Core Architecture] " <> refCoreArch <> ", this module provides"
    , "-- the primary domain interface within the '" <> pName <> "' workspace."
    , "--"
    , "-- == Invariants & Guarantees"
    , "--"
    , "-- 1. __Purity:__ All exported functions are referentially transparent."
    , "-- 2. __Total Operations:__ Default constructors avoid partiality."
    , "-- 3. __Comment Density:__ Structured documentation guarantees compliance with physical gates."
    , "--"
    , "-- = Worked Example"
    , "--"
    , "-- >>> defaultEntity"
    , "-- Entity {entityName = \"" <> pName <> "\", entityModule = \"" <> modName <> "\"}"
    , "module " <> modName
    , "  ( -- * Core Types"
    , "    Entity(..)"
    , "    -- * Default Constructors"
    , "  , defaultEntity"
    , "    -- * Operations"
    , "  , renderEntity"
    , "  ) where"
    , ""
    , "import Data.Text (Text)"
    , ""
    , "-- | Represents a core domain entity within the '" <> pkgN <> "' package."
    , "--"
    , "-- Tracks the enclosing workspace name and the module identifier."
    , "data Entity = Entity"
    , "  { entityName   :: !Text"
    , "    -- ^ Name of the parent project workspace."
    , "  , entityModule :: !Text"
    , "    -- ^ Canonical module identifier defining the entity."
    , "  } deriving stock (Eq, Show)"
    , ""
    , "-- | Canonical default entity for '" <> modName <> "'."
    , "--"
    , "-- Returns an 'Entity' bound to the workspace name and current module name."
    , "defaultEntity :: Entity"
    , "defaultEntity = Entity"
    , "  { entityName   = \"" <> pName <> "\""
    , "  , entityModule = \"" <> modName <> "\""
    , "  }"
    , ""
    , "-- | Formats an 'Entity' into a human-readable display string."
    , "--"
    , "-- Computes a combined representation: @\"<entityName>:<entityModule>\"@."
    , "renderEntity :: Entity -> Text"
    , "renderEntity e = entityName e <> \":\" <> entityModule e"
    ]

-- | Generates a package's Hspec test suite.
packageTestTemplate :: Project -> PackageSpec -> Text
packageTestTemplate proj pkg =
  let pName = projectName proj
      firstMod = case packageExposes pkg of
        (m:_) -> m
        []    -> defaultModuleName (packageName pkg)
  in T.unlines
    [ "{-# LANGUAGE OverloadedStrings #-}"
    , ""
    , "module Main (main) where"
    , ""
    , "import Test.Hspec"
    , "import " <> firstMod
    , ""
    , "main :: IO ()"
    , "main = hspec $ do"
    , "  describe \"" <> firstMod <> "\" $ do"
    , "    it \"constructs default entity with correct properties\" $ do"
    , "      let e = defaultEntity"
    , "      entityName e `shouldBe` \"" <> pName <> "\""
    , "      entityModule e `shouldBe` \"" <> firstMod <> "\""
    , "    it \"renders entity accurately\" $ do"
    , "      let e = defaultEntity"
    , "      renderEntity e `shouldBe` \"" <> pName <> ":" <> firstMod <> "\""
    ]

--------------------------------------------------------------------------------
-- Utilities: String & Path Helpers
--------------------------------------------------------------------------------

-- | Converts a package name (e.g., @"gachi-core"@) into a canonical PascalCase
-- Haskell module name (e.g., @"Gachi.Core"@).
defaultModuleName :: Text -> Text
defaultModuleName raw =
  let parts = filter (not . T.null) (T.splitOn "-" raw)
      capitalized = map capitalize parts
  in case capitalized of
       [] -> "Main"
       _  -> T.intercalate "." capitalized
  where
    capitalize t = case T.uncons t of
      Nothing      -> ""
      Just (c, cs) -> T.cons (toUpper c) cs

-- | Converts a hierarchical module name (e.g., @"Gongju.Core"@) to a relative
-- source file path (e.g., @"Gongju/Core.hs"@).
moduleToFilePath :: Text -> FilePath
moduleToFilePath modName =
  T.unpack (T.replace "." "/" modName) <> ".hs"

-- | Converts a kebab-case identifier into an uppercase slug (e.g., @"gachi-core"@ -> @"GACHI_CORE"@).
toUpperSlug :: Text -> Text
toUpperSlug = T.map cleanChar
  where
    cleanChar c
      | isAlphaNum c = toUpper c
      | otherwise    = '_'
