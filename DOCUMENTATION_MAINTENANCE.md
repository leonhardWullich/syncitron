# 📚 Documentation Management Guide

This guide explains how to manage and generate the Replicore documentation website.

## Directory Structure

```
replicore/
├── docs/                          # Source Markdown files
│   ├── 01_GETTING_STARTED.md
│   ├── 02_ARCHITECTURE.md
│   ├── ... (28 more docs)
│   ├── 24_SYNC_ORCHESTRATION_STRATEGY.md  # NEW!
│   ├── INDEX.md                   # Main documentation index
│   └── README.md                  # (This document)
│
├── docs_html/                     # Generated HTML website
│   ├── index.html                 # Home page
│   ├── 01_GETTING_STARTED.html    # All generated docs
│   ├── ... (all .html files)
│   ├── manifest.json              # Documentation metadata
│   └── README.md                  # Deployment instructions
│
├── generate_docs.py               # Generator script
└── README.md                      # Main project README
```

## 🆕 New Documentation: SyncOrchestrationStrategy

**File**: `docs/24_SYNC_ORCHESTRATION_STRATEGY.md`

This comprehensive guide covers:
- Complete `SyncOrchestrationStrategy` interface documentation
- All 5 built-in strategies (Standard, OfflineFirst, StrictManual, Priority, Composite)
- Custom orchestration examples
- Advanced patterns and best practices

**Added to**: `docs/INDEX.md` under "Implementation Patterns" section

---

## 🗑️ Removed Deprecated Files

The following outdated files have been removed from the root directory:

- ❌ **QUICK_REFERENCE.md** - v0.2.0 outdated reference (replaced by `docs/15_QUICK_REFERENCE.md`)
- ❌ **V0.3_V0.4_IMPLEMENTATION_SUMMARY.md** - Historical release info
- ❌ **TEST_SUMMARY.md** - Outdated test documentation
- ❌ **ENTERPRISE_README.md** - Redundant with main `README.md` and `docs/README.md`

Current documentation is fully centralized in the `docs/` directory and properly indexed.

---

## 🔄 Regenerating the Documentation Website

Whenever you modify or add documentation files:

### Step 1: Update Markdown Files

Edit or create files in `docs/`:
```bash
# Edit existing docs
nano docs/02_ARCHITECTURE.md

# Or create new documentation
touch docs/25_NEW_TOPIC.md
```

### Step 2: Update INDEX.md

Update `docs/INDEX.md` to reference new sections if you add new documentation.

### Step 3: Generate HTML

```bash
python3 generate_docs.py
```

This script will:
1. ✅ Read all `.md` files from `docs/`
2. ✅ Convert them to HTML with professional styling
3. ✅ Generate a sidebar navigation with search
4. ✅ Create responsive, dark-mode enabled pages
5. ✅ Output everything to `docs_html/`
6. ✅ Generate `manifest.json` with metadata

### Step 4: Preview Locally

```bash
# Using Python 3
python3 -m http.server 8000 --directory docs_html

# Then open: http://localhost:8000/
```

Test on different browsers and devices to ensure everything looks good.

### Step 5: Deploy

Choose one of these deployment options:

#### **GitHub Pages** (Free, Easiest)
```bash
# Setup once
git checkout --orphan gh-pages
rm -rf .git/index
git clean -fdx

# Deploy docs
cp -r docs_html/* .
git add .
git commit -m "Update documentation"
git push origin gh-pages
```

#### **Netlify** (Free, Recommended)
1. Connect your repo to Netlify
2. Set build command: `python3 generate_docs.py`
3. Set publish directory: `docs_html`
4. Click Deploy!

#### **Vercel, Firebase, AWS S3, etc.**
See `docs_html/README.md` for detailed instructions

---

## 📝 Documentation Standards

All documentation files follow these conventions:

### File Naming
- Use `NN_TOPIC_NAME.md` format (01, 02, 03, etc.)
- Numbers ensure correct ordering in navigation
- Underscores, no spaces

### Content Structure
```markdown
# Main Title
> Subtitle/description

**Version**: X.X.X | **Last Updated**: Date

---

## 📚 Overview

## 🎯 Quick Start / When to Use

## 📖 Core Concepts

## 🔄 Examples

## ✅ Best Practices

## 📋 Summary Table

## 🔗 Related Documentation

## 📞 Support
```

### Formatting
- ✅ Use proper Markdown syntax
- ✅ Code blocks with language: ` ```dart ` 
- ✅ Emojis for section headers
- ✅ Tables for comparisons
- ✅ Links to related docs: `[Text](./FILE.md)`
- ✅ Inline code: ` `something` `
- ✅ Bold for emphasis: ` **important** `

---

## 🎨 Customizing the Website

### Colors and Branding

Edit `generate_docs.py`, find the `generate_css()` function:

```python
:root {
    --color-primary: #2e539e;       # Main brand color
    --color-secondary: #ff6b6b;     # Accent color
    --color-accent: #ffd43b;        # Highlight
}
```

### Header/Navigation

Edit the `generate_html_page()` function to customize:
- Logo/title
- Navigation sections
- Footer links

### Adding Analytics

Add to `generate_html_page()` inside `</head>` or before `</body>`:

```html
<script async src="https://www.googletagmanager.com/gtag/js?id=GA_ID"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'GA_ID');
</script>
```

---

## 📊 Documentation Statistics

| Category | Files | Status |
|----------|-------|--------|
| Getting Started | 2 | ✅ Current |
| Architecture | 2 | ✅ Current |
| Integration Guides | 9 | ✅ Current |
| Implementation Patterns | 3 | ✅ Current (+ NEW SyncOrchestrationStrategy) |
| Performance | 1 | ✅ Current |
| Real-Time | 1 | ✅ Current |
| Enterprise | 1 | ✅ Current |
| API Reference | 2 | ✅ Current |
| Migration | 1 | ✅ Current |
| Troubleshooting | 2 | ✅ Current |
| Ecosystem | 2 | ✅ Current |
| **TOTAL** | **28** | **✅ Complete** |

---

## 🚀 Workflow Example

Here's a typical workflow for adding new documentation:

```bash
# 1. Create new doc file
touch docs/25_NEW_FEATURE.md

# 2. Edit the file with your content
nano docs/25_NEW_FEATURE.md

# 3. Update the INDEX.md to reference it
nano docs/INDEX.md
# Add your new doc under appropriate section

# 4. Generate HTML
python3 generate_docs.py

# 5. Test locally
python3 -m http.server 8000 --directory docs_html
# Open: http://localhost:8000/

# 6. Commit changes
git add docs/ generate_docs.py docs_html/
git commit -m "Add documentation for new feature"

# 7. Push (triggers Netlify/GitHub Pages auto-deployment)
git push origin main
```

---

## ✅ Pre-Deployment Checklist

- [ ] All markdown files updated and properly formatted
- [ ] `INDEX.md` includes references to all new docs
- [ ] HTML generated: `python3 generate_docs.py`
- [ ] No broken links (test locally)
- [ ] Dark mode toggle works
- [ ] Search functionality works
- [ ] Navigation sidebar displays correctly
- [ ] Pages load on mobile (responsive design)
- [ ] Code blocks display properly
- [ ] Tables render correctly
- [ ] All links point to correct .html files

---

## 🆘 Troubleshooting

### Issue: "File not found" when generating

**Solution**: Check that all `.md` files are in the `docs/` directory and readable

### Issue: Broken links in generated HTML

**Solution**: Verify that links use `./{FILE}.md` format and files exist

### Issue: Search not working

**Solution**: Clear browser cache (Cmd+Shift+R on Mac)

### Issue: Dark mode button missing

**Solution**: Regenerate HTML - ensure `generate_docs.py` is current version

### Issue: Code blocks not syntax-highlighted

**Solution**: Use proper code block syntax: ` ```language_name ... ``` `

---

## 📚 Related Resources

- [README.md](./README.md) - Main project information
- [docs_html/README.md](./docs_html/README.md) - Website deployment guide
- [docs/INDEX.md](./docs/INDEX.md) - Complete documentation index
- [docs/01_GETTING_STARTED.md](./docs/01_GETTING_STARTED.md) - For new users
- [docs/02_ARCHITECTURE.md](./docs/02_ARCHITECTURE.md) - System design overview

---

## 📞 Contact & Support

For documentation questions or improvements:
- Check existing docs first
- Review the INDEX.md for navigation
- Update docs locally and regenerate
- Test before deploying

---

**Last Updated**: March 9, 2026  
**Documentation Version**: 0.5.1  
**Total Pages**: 32 (including new SyncOrchestrationStrategy)
