#!/bin/bash
# Documentation verification script
# Checks links, structure, and consistency across all documentation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Expo Free Agent - Documentation Verification${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check 1: Verify all markdown files exist in INDEX.md
echo -e "${BLUE}📋 Checking documentation index...${NC}"
DOCS_DIR="docs"
INDEXED_FILES=$(grep -oE '\]\([^)]+\.md\)' "$DOCS_DIR/INDEX.md" | sed 's/](\(.*\))/\1/' | sed 's|^\.\./||' | sed 's|^\.\/||')

for file in $INDEXED_FILES; do
    # Convert relative path to absolute
    if [[ "$file" == ../* ]]; then
        full_path="$file"
    elif [[ "$file" == docs/* ]]; then
        full_path="$file"
    else
        full_path="$DOCS_DIR/$file"
    fi

    if [ ! -f "$full_path" ]; then
        echo -e "${RED}✗ Missing file referenced in INDEX.md: $full_path${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All indexed files exist${NC}"
fi
echo ""

# Check 2: Find broken internal links
echo -e "${BLUE}🔗 Checking internal links...${NC}"
find docs -name "*.md" -o -name "README.md" | while read -r file; do
    # Extract markdown links
    grep -oE '\]\([^)]+\)' "$file" 2>/dev/null | sed 's/](\(.*\))/\1/' | while read -r link; do
        # Skip external links, anchors, and mailto
        if [[ "$link" =~ ^http ]] || [[ "$link" =~ ^# ]] || [[ "$link" =~ ^mailto ]]; then
            continue
        fi

        # Resolve relative path
        dir=$(dirname "$file")
        target="$dir/$link"

        # Remove anchor fragments
        target="${target%%#*}"

        # Normalize path
        target=$(echo "$target" | sed 's|/\./|/|g')

        if [ ! -f "$target" ] && [ ! -d "$target" ]; then
            echo -e "${RED}✗ Broken link in $file: $link → $target${NC}"
            ERRORS=$((ERRORS + 1))
        fi
    done
done

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All internal links valid${NC}"
fi
echo ""

# Check 3: Verify required sections in key docs
echo -e "${BLUE}📖 Checking required documentation sections...${NC}"

# Check README.md has required sections
if ! grep -q "## Quick Links" README.md; then
    echo -e "${YELLOW}⚠ README.md missing 'Quick Links' section${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

if ! grep -q "## Get Started in 5 Minutes" README.md; then
    echo -e "${YELLOW}⚠ README.md missing 'Get Started in 5 Minutes' section${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Check docs/INDEX.md structure
required_sections=("Getting Started" "Architecture" "Operations" "Testing" "Reference" "Examples" "Contributing")
for section in "${required_sections[@]}"; do
    if ! grep -q "## $section" "$DOCS_DIR/INDEX.md"; then
        echo -e "${RED}✗ INDEX.md missing '$section' section${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All required sections present${NC}"
fi
echo ""

# Check 4: Verify code blocks have language tags
echo -e "${BLUE}💻 Checking code block language tags...${NC}"
find docs -name "*.md" -o -name "README.md" | while read -r file; do
    # Find code blocks without language tags
    if grep -q '```$' "$file"; then
        echo -e "${YELLOW}⚠ Code block without language tag in $file${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
done

if [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All code blocks have language tags${NC}"
fi
echo ""

# Check 5: Verify consistent terminology
echo -e "${BLUE}📝 Checking terminology consistency...${NC}"

# Common inconsistencies to check
find docs -name "*.md" | while read -r file; do
    # Check for "mac" vs "macOS"
    if grep -qi '\bmac\b' "$file" && ! grep -q 'macOS' "$file"; then
        echo -e "${YELLOW}⚠ Use 'macOS' instead of 'mac' in $file${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check for "OSX" or "OS X"
    if grep -qE '\bOS ?X\b' "$file"; then
        echo -e "${YELLOW}⚠ Use 'macOS' instead of 'OS X' in $file${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
done

if [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Terminology consistent${NC}"
fi
echo ""

# Check 6: Verify examples directory structure
echo -e "${BLUE}📁 Checking examples structure...${NC}"
EXAMPLE_DIRS=$(find examples -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)

for dir in $EXAMPLE_DIRS; do
    if [ ! -f "$dir/README.md" ]; then
        echo -e "${RED}✗ Missing README.md in $dir${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All examples have README.md${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ Documentation verification passed!${NC}"
    echo -e "${GREEN}   All checks completed successfully.${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Documentation verification passed with warnings${NC}"
    echo -e "${YELLOW}   Errors: $ERRORS | Warnings: $WARNINGS${NC}"
    exit 0
else
    echo -e "${RED}❌ Documentation verification failed${NC}"
    echo -e "${RED}   Errors: $ERRORS | Warnings: $WARNINGS${NC}"
    exit 1
fi
