#!/usr/bin/env python3
"""
Replicore Documentation HTML Generator

Converts all markdown documentation files to a professional website
with navigation, search, and responsive design.
"""

import os
import re
import json
from pathlib import Path
from datetime import datetime

# Try to import markdown, if not available use fallback
try:
    import markdown
    HAS_MARKDOWN = True
except ImportError:
    HAS_MARKDOWN = False


def simple_markdown_to_html(text):
    """Simple fallback markdown to HTML converter"""
    # Save code blocks
    code_blocks = []
    
    def save_code_block(match):
        code_blocks.append(match.group(0))
        return f"__CODE_BLOCK_{len(code_blocks)-1}__"
    
    # Extract code blocks
    text = re.sub(r'```[\s\S]*?```', save_code_block, text)
    
    # Headers
    text = re.sub(r'^# (.*?)$', r'<h1>\1</h1>', text, flags=re.MULTILINE)
    text = re.sub(r'^## (.*?)$', r'<h2>\1</h2>', text, flags=re.MULTILINE)
    text = re.sub(r'^### (.*?)$', r'<h3>\1</h3>', text, flags=re.MULTILINE)
    text = re.sub(r'^#### (.*?)$', r'<h4>\1</h4>', text, flags=re.MULTILINE)
    
    # Bold and italic
    text = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'__(.*?)__', r'<strong>\1</strong>', text)
    text = re.sub(r'\*(.*?)\*', r'<em>\1</em>', text)
    text = re.sub(r'_(.*?)_', r'<em>\1</em>', text)
    
    # Links
    text = re.sub(r'\[(.*?)\]\((.*?)\)', r'<a href="\2">\1</a>', text)
    
    # Inline code
    text = re.sub(r'`(.*?)`', r'<code>\1</code>', text)
    
    # Lists
    lines = text.split('\n')
    result = []
    in_list = False
    for line in lines:
        if re.match(r'^\s*[-*+] ', line):
            if not in_list:
                result.append('<ul>')
                in_list = True
            item = re.sub(r'^\s*[-*+] ', '', line)
            result.append(f'<li>{item}</li>')
        elif in_list:
            result.append('</ul>')
            in_list = False
            result.append(line)
        else:
            result.append(line)
    
    if in_list:
        result.append('</ul>')
    
    text = '\n'.join(result)
    
    # Paragraphs
    text = re.sub(r'\n\n', '</p><p>', text)
    text = f'<p>{text}</p>'
    
    # Restore code blocks
    for i, block in enumerate(code_blocks):
        # Check if it's a dart code block
        language = 'dart' if 'dart' in block.lower() else 'text'
        code_content = block.replace('```dart', '').replace('```', '').strip()
        code_html = f'<pre><code class="language-{language}">{html_escape(code_content)}</code></pre>'
        text = text.replace(f'__CODE_BLOCK_{i}__', code_html)
    
    # Clean up empty paragraphs
    text = re.sub(r'<p>\s*</p>', '', text)
    
    return text


def html_escape(text):
    """Escape HTML special characters"""
    return (text
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace("'", '&#39;'))


def markdown_to_html(filepath):
    """Convert markdown file to HTML"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if HAS_MARKDOWN:
        return markdown.markdown(content, extensions=['tables', 'fenced_code'])
    else:
        return simple_markdown_to_html(content)


def extract_title_from_markdown(filepath):
    """Extract the first heading from markdown file"""
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            if line.startswith('# '):
                return line[2:].strip()
    return Path(filepath).stem.replace('_', ' ').title()


def get_docs_structure():
    """Get the structure of documentation files"""
    docs_dir = Path('docs')
    
    # Order of docs (numerical prefix)
    doc_files = []
    for md_file in sorted(docs_dir.glob('*.md')):
        if md_file.name not in ['DOCUMENTATION_SUMMARY.md', 'START_HERE.md']:
            doc_files.append({
                'path': str(md_file),
                'name': md_file.stem.replace('_', ' '),
                'filename': md_file.name,
                'title': extract_title_from_markdown(md_file)
            })
    
    return doc_files


def generate_css():
    """Generate the main CSS stylesheet"""
    return """
/* ============================================
   Replicore Documentation - Main Stylesheet
   ============================================ */

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

:root {
    --color-primary: #2e539e;
    --color-secondary: #ff6b6b;
    --color-accent: #ffd43b;
    --color-success: #51cf66;
    --color-warning: #ffa94d;
    --color-danger: #ff6b6b;
    
    --color-bg-dark: #1a1a1a;
    --color-bg-light: #ffffff;
    --color-bg-alt: #f5f5f5;
    
    --color-text-dark: #1a1a1a;
    --color-text-light: #ffffff;
    --color-text-muted: #666666;
    
    --color-border: #e0e0e0;
    --color-border-dark: #333333;
    
    --font-primary: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', sans-serif;
    --font-mono: 'Monaco', 'Courier New', monospace;
    
    --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
    --shadow-md: 0 4px 6px rgba(0, 0, 0, 0.1);
    --shadow-lg: 0 10px 25px rgba(0, 0, 0, 0.15);
    
    --transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

/* Light Mode (Default) */
body {
    font-family: var(--font-primary);
    background-color: var(--color-bg-light);
    color: var(--color-text-dark);
    line-height: 1.6;
    transition: var(--transition);
}

/* Dark Mode */
body.dark-mode {
    background-color: var(--color-bg-dark);
    color: var(--color-text-light);
}

/* ============================================
   Layout & Structure
   ============================================ */

.container {
    display: flex;
    min-height: 100vh;
}

header {
    background: linear-gradient(135deg, var(--color-primary) 0%, #1a3a6e 100%);
    color: white;
    padding: 1rem 2rem;
    box-shadow: var(--shadow-md);
    position: sticky;
    top: 0;
    z-index: 100;
}

header h1 {
    font-size: 1.8rem;
    font-weight: 600;
    margin-bottom: 0.5rem;
}

header p {
    font-size: 0.9rem;
    opacity: 0.9;
}

.navbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 2rem;
}

.theme-toggle {
    background: rgba(255, 255, 255, 0.2);
    border: 1px solid rgba(255, 255, 255, 0.3);
    color: white;
    padding: 0.5rem 1rem;
    border-radius: 0.5rem;
    cursor: pointer;
    transition: var(--transition);
    font-size: 0.9rem;
}

.theme-toggle:hover {
    background: rgba(255, 255, 255, 0.3);
}

.main-content {
    display: flex;
    width: 100%;
}

/* ============================================
   Sidebar Navigation
   ============================================ */

.sidebar {
    width: 280px;
    background: var(--color-bg-alt);
    border-right: 1px solid var(--color-border);
    overflow-y: auto;
    padding: 2rem 0;
    position: sticky;
    top: 80px;
    height: calc(100vh - 80px);
    transition: var(--transition);
}

body.dark-mode .sidebar {
    background: linear-gradient(180deg, #2a2a2a 0%, #1a1a1a 100%);
    border-right: 1px solid var(--color-border-dark);
}

.sidebar h3 {
    padding: 1rem 1.5rem;
    font-size: 0.9rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-text-muted);
    margin-top: 1.5rem;
    margin-bottom: 0.5rem;
}

.sidebar a {
    display: block;
    padding: 0.75rem 1.5rem;
    color: var(--color-text-dark);
    text-decoration: none;
    transition: var(--transition);
    border-left: 3px solid transparent;
    font-size: 0.95rem;
}

body.dark-mode .sidebar a {
    color: var(--color-text-light);
}

.sidebar a:hover {
    background: rgba(46, 83, 158, 0.1);
    border-left-color: var(--color-primary);
}

.sidebar a.active {
    background: rgba(46, 83, 158, 0.15);
    border-left-color: var(--color-primary);
    color: var(--color-primary);
    font-weight: 600;
}

/* ============================================
   Main Content Area
   ============================================ */

.content {
    flex: 1;
    padding: 3rem;
    max-width: 900px;
    margin: 0 auto;
    width: 100%;
}

.article {
    margin-bottom: 3rem;
}

/* ============================================
   Typography
   ============================================ */

h1, h2, h3, h4, h5, h6 {
    line-height: 1.3;
    margin-top: 2rem;
    margin-bottom: 1rem;
    font-weight: 600;
    color: var(--color-primary);
}

body.dark-mode h1,
body.dark-mode h2,
body.dark-mode h3,
body.dark-mode h4,
body.dark-mode h5,
body.dark-mode h6 {
    color: #65b8f6;
}

.article > h1:first-child {
    margin-top: 0;
}

h1 { font-size: 2.5rem; }
h2 { font-size: 2rem; color: var(--color-primary); }
h3 { font-size: 1.5rem; }
h4 { font-size: 1.2rem; }

p {
    margin-bottom: 1rem;
    line-height: 1.8;
}

blockquote {
    border-left: 4px solid var(--color-primary);
    padding: 1rem;
    margin: 1.5rem 0;
    background: rgba(46, 83, 158, 0.05);
    border-radius: 0.25rem;
}

body.dark-mode blockquote {
    background: rgba(46, 83, 158, 0.15);
}

/* ============================================
   Code Blocks & Inline Code
   ============================================ */

code {
    font-family: var(--font-mono);
    background: var(--color-bg-alt);
    padding: 0.2rem 0.4rem;
    border-radius: 0.25rem;
    font-size: 0.9em;
    color: #d63384;
}

body.dark-mode code {
    background: #333333;
    color: #ff9eda;
}

pre {
    background: #282c34;
    color: #abb2bf;
    padding: 1.5rem;
    border-radius: 0.5rem;
    overflow-x: auto;
    margin: 1.5rem 0;
    line-height: 1.5;
    box-shadow: var(--shadow-md);
}

pre code {
    background: none;
    color: inherit;
    padding: 0;
}

pre code.language-dart {
    color: #56b6c2;
}

/* ============================================
   Lists
   ============================================ */

ul, ol {
    margin: 1rem 0;
    padding-left: 2rem;
}

li {
    margin: 0.5rem 0;
}

ul li::marker {
    color: var(--color-primary);
}

/* ============================================
   Links
   ============================================ */

a {
    color: var(--color-primary);
    text-decoration: none;
    border-bottom: 1px solid transparent;
    transition: var(--transition);
}

a:hover {
    border-bottom-color: var(--color-primary);
}

body.dark-mode a {
    color: #65b8f6;
}

/* ============================================
   Tables
   ============================================ */

table {
    width: 100%;
    border-collapse: collapse;
    margin: 2rem 0;
    box-shadow: var(--shadow-sm);
}

table th {
    background: var(--color-primary);
    color: white;
    padding: 1rem;
    text-align: left;
    font-weight: 600;
}

table td {
    padding: 0.75rem 1rem;
    border-bottom: 1px solid var(--color-border);
}

body.dark-mode table td {
    border-color: var(--color-border-dark);
}

table tbody tr:hover {
    background: var(--color-bg-alt);
}

body.dark-mode table tbody tr:hover {
    background: rgba(46, 83, 158, 0.1);
}

/* ============================================
   Badges & Highlights
   ============================================ */

.badge {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    border-radius: 0.25rem;
    font-size: 0.85rem;
    font-weight: 600;
    margin-right: 0.5rem;
    margin-bottom: 0.5rem;
}

.badge-success { background: var(--color-success); color: white; }
.badge-warning { background: var(--color-warning); color: white; }
.badge-danger { background: var(--color-danger); color: white; }
.badge-info { background: var(--color-primary); color: white; }

/* ============================================
   Search Box
   ============================================ */

.search-box {
    width: 100%;
    padding: 0.75rem 1.5rem;
    margin: 1rem 0;
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    font-family: var(--font-primary);
    background: var(--color-bg-light);
    color: var(--color-text-dark);
}

body.dark-mode .search-box {
    background: #333333;
    border-color: var(--color-border-dark);
    color: var(--color-text-light);
}

.search-box:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px rgba(46, 83, 158, 0.1);
}

/* ============================================
   Responsive Design
   ============================================ */

@media (max-width: 768px) {
    .container {
        flex-direction: column;
    }
    
    .main-content {
        flex-direction: column;
    }
    
    .sidebar {
        width: 100%;
        height: auto;
        position: static;
        border-right: none;
        border-bottom: 1px solid var(--color-border);
        padding: 1rem 0;
    }
    
    .content {
        padding: 2rem;
        max-width: 100%;
    }
    
    h1 { font-size: 2rem; }
    h2 { font-size: 1.5rem; }
    h3 { font-size: 1.2rem; }
    
    pre {
        padding: 1rem;
        font-size: 0.85rem;
    }
}

/* ============================================
   Syntax Highlighting
   ============================================ */

.hljs { color: #abb2bf; background: #282c34; }
.hljs-attr { color: #e06c75; }
.hljs-literal { color: #56b6c2; }
.hljs-number { color: #d19a66; }
.hljs-string { color: #98c379; }
.hljs-built_in { color: #e06c75; }
.hljs-type { color: #e06c75; }
.hljs-name { color: #e06c75; }

/* ============================================
   Footer
   ============================================ */

footer {
    background: var(--color-bg-alt);
    border-top: 1px solid var(--color-border);
    padding: 2rem;
    text-align: center;
    color: var(--color-text-muted);
    margin-top: 3rem;
}

body.dark-mode footer {
    background: #2a2a2a;
    border-color: var(--color-border-dark);
}

footer a {
    color: var(--color-primary);
}

/* ============================================
   Utilities
   ============================================ */

.text-center { text-align: center; }
.text-right { text-align: right; }
.text-muted { color: var(--color-text-muted); }
.mt-4 { margin-top: 2rem; }
.mb-4 { margin-bottom: 2rem; }
.max-width { max-width: 900px; margin: 0 auto; }

.highlight {
    background: rgba(255, 212, 59, 0.3);
    padding: 0.1rem 0.3rem;
    border-radius: 0.25rem;
}

.emoji {
    font-size: 1.2em;
    margin-right: 0.5rem;
}
"""


def generate_nav_html(docs):
    """Generate navigation HTML"""
    nav_html = '<nav class="sidebar">\n'
    nav_html += '<input type="text" class="search-box" id="searchBox" placeholder="Search docs...">\n'
    
    # Group docs by prefix number
    sections = {
        'getting_started': [],
        'architecture': [],
        'integration': [],
        'patterns': [],
        'performance': [],
        'enterprise': [],
        'api': [],
        'migration': [],
        'other': [],
    }
    
    for doc in docs:
        name = doc['filename']
        
        if name.startswith(('01_', '02_')):
            sections['getting_started'].append(doc)
        elif name.startswith(('02_', '03_', '04_')):
            sections['architecture'].append(doc)
        elif name.startswith(('05_', '06_', '07_', '08_', '09_', '20_', '22_', '23_')):
            sections['integration'].append(doc)
        elif name.startswith(('10_', '24_')):
            sections['performance'].append(doc)
        elif name.startswith(('11_', '12_', '13_', '14_', '15_', '21_')):
            sections['api'].append(doc)
        elif name.startswith(('16_', '17_', '18_', '19_')):
            sections['migration'].append(doc)
        else:
            sections['other'].append(doc)
    
    # Sort docs by name
    for section in sections.values():
        section.sort(key=lambda x: x['filename'])
    
    # Build nav
    if sections['getting_started']:
        nav_html += '<h3>🎯 Getting Started</h3>\n'
        for doc in sections['getting_started']:
            nav_html += f'<a href="/{doc["filename"].replace(".md", ".html")}" class="nav-link">{doc["title"]}</a>\n'
    
    if sections['architecture']:
        nav_html += '<h3>🏗️ Architecture</h3>\n'
        for doc in sections['architecture']:
            nav_html += f'<a href="/{doc["filename"].replace(".md", ".html")}" class="nav-link">{doc["title"]}</a>\n'
    
    if sections['integration']:
        nav_html += '<h3>🔌 Integration</h3>\n'
        for doc in sections['integration']:
            nav_html += f'<a href="/{doc["filename"].replace(".md", ".html")}" class="nav-link">{doc["title"]}</a>\n'
    
    if sections['performance']:
        nav_html += '<h3>⚡ Performance</h3>\n'
        for doc in sections['performance']:
            nav_html += f'<a href="/{doc["filename"].replace(".md", ".html")}" class="nav-link">{doc["title"]}</a>\n'
    
    if sections['api']:
        nav_html += '<h3>📚 Reference</h3>\n'
        for doc in sections['api']:
            nav_html += f'<a href="/{doc["filename"].replace(".md", ".html")}" class="nav-link">{doc["title"]}</a>\n'
    
    if sections['migration']:
        nav_html += '<h3>📦 Migration</h3>\n'
        for doc in sections['migration']:
            nav_html += f'<a href="/{doc["filename"].replace(".md", ".html")}" class="nav-link">{doc["title"]}</a>\n'
    
    nav_html += '</nav>\n'
    return nav_html


def generate_html_page(title, content, docs, current_doc=None):
    """Generate a complete HTML page"""
    nav_html = generate_nav_html(docs)
    css = generate_css()
    
    html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>""" + html_escape(title) + """ - Replicore Documentation</title>
    <style>
""" + css + """
    </style>
</head>
<body>
    <header>
        <div class="navbar">
            <div>
                <h1>📚 Replicore Documentation</h1>
                <p>Enterprise Local-First Sync for Flutter</p>
            </div>
            <button class="theme-toggle" id="themeToggle">🌙 Dark Mode</button>
        </div>
    </header>
    
    <div class="container">
        """ + nav_html + """
        
        <div class="content">
            <article class="article">
                """ + content + """
            </article>
        </div>
    </div>
    
    <footer>
        <p>&copy; 2026 Replicore Framework. All rights reserved.</p>
        <p><a href="https://github.com">GitHub Repository</a> | <a href="https://pub.dev/packages/replicore">Pub.dev</a></p>
    </footer>
    
    <script>
        // Theme toggle
        const themeToggle = document.getElementById('themeToggle');
        const htmlElement = document.documentElement;
        
        // Check localStorage for theme preference
        const theme = localStorage.getItem('theme') || 'light';
        if (theme === 'dark') {
            document.body.classList.add('dark-mode');
            themeToggle.textContent = '☀️ Light Mode';
        }
        
        themeToggle.addEventListener('click', () => {
            document.body.classList.toggle('dark-mode');
            const newTheme = document.body.classList.contains('dark-mode') ? 'dark' : 'light';
            localStorage.setItem('theme', newTheme);
            themeToggle.textContent = newTheme === 'dark' ? '☀️ Light Mode' : '🌙 Dark Mode';
        });
        
        // Highlight current page in sidebar
        const currentPath = window.location.pathname.split('/').pop();
        document.querySelectorAll('.nav-link').forEach(link => {
            if (link.getAttribute('href').endsWith(currentPath)) {
                link.classList.add('active');
            }
        });
        
        // Simple search functionality
        const searchBox = document.getElementById('searchBox');
        if (searchBox) {
            searchBox.addEventListener('keyup', (e) => {
                const query = e.target.value.toLowerCase();
                document.querySelectorAll('.nav-link').forEach(link => {
                    const text = link.textContent.toLowerCase();
                    link.style.display = text.includes(query) ? 'block' : 'none';
                });
            });
        }
    </script>
</body>
</html>
"""
    return html


def main():
    """Main function to generate documentation website"""
    
    # Get all documentation files
    docs = get_docs_structure()
    
    print(f"🚀 Generating HTML documentation for {len(docs)} files...")
    
    # Create output directory
    output_dir = Path('docs_html')
    output_dir.mkdir(exist_ok=True)
    
    # Generate HTML files
    for doc in docs:
        print(f"  ✓ Converting {doc['filename']}...", end='', flush=True)
        
        # Read markdown
        with open(doc['path'], 'r', encoding='utf-8') as f:
            markdown_content = f.read()
        
        # Convert to HTML
        try:
            if HAS_MARKDOWN:
                html_content = markdown.markdown(
                    markdown_content,
                    extensions=['tables', 'fenced_code', 'codehilite']
                )
            else:
                html_content = simple_markdown_to_html(markdown_content)
        except Exception as e:
            print(f"\n    ⚠️  Error converting {doc['filename']}: {e}")
            continue
        
        # Generate full HTML page
        output_filename = doc['filename'].replace('.md', '.html')
        full_html = generate_html_page(doc['title'], html_content, docs, doc)
        
        # Write to file
        output_path = output_dir / output_filename
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(full_html)
        
        print(f" → {output_filename}")
    
    # Create index.html
    print("  ✓ Creating index.html...", end='', flush=True)
    
    # Read main README
    with open('README.md', 'r', encoding='utf-8') as f:
        readme_content = f.read()
    
    try:
        if HAS_MARKDOWN:
            index_html_content = markdown.markdown(
                readme_content,
                extensions=['tables', 'fenced_code']
            )
        else:
            index_html_content = simple_markdown_to_html(readme_content)
    except:
        index_html_content = "<h1>Replicore Documentation</h1><p>Welcome to the Replicore documentation website.</p>"
    
    index_html = generate_html_page('Home - Replicore Documentation', index_html_content, docs)
    
    with open(output_dir / 'index.html', 'w', encoding='utf-8') as f:
        f.write(index_html)
    
    print(f" → index.html")
    
    # Create documentation index
    print("  ✓ Creating docs-manifest.json...", end='', flush=True)
    
    manifest = {
        'title': 'Replicore Documentation',
        'version': '0.5.1',
        'generated': datetime.now().isoformat(),
        'documents': docs,
        'stats': {
            'total_documents': len(docs),
            'total_pages': len(docs) + 1  # +1 for index
        }
    }
    
    with open(output_dir / 'manifest.json', 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2)
    
    print(f" → manifest.json")
    
    # Print summary
    print("\n✅ Documentation HTML generation complete!")
    print(f"\n📁 Output directory: {output_dir.absolute()}")
    print(f"📄 Total files generated: {len(docs) + 2}")
    print(f"\n🌍 Open in browser: file://{output_dir.absolute()}/index.html")
    print("\n📋 Document list:")
    for doc in docs:
        print(f"   • {doc['title']}")


if __name__ == '__main__':
    main()
