# Replicore Documentation Website

> **Professional documentation website for the Replicore Flutter framework**

This directory contains a complete, production-ready HTML documentation website that can be deployed to any web hosting platform.

## 📁 Contents

- **index.html** - Main documentation hub
- **01_GETTING_STARTED.html** through **24_SYNC_ORCHESTRATION_STRATEGY.html** - All documentation pages
- **manifest.json** - Documentation metadata and index
- **styles/** - CSS stylesheets (embedded in HTML for portability)

## 🚀 Quick Start

### Local Testing

#### macOS/Linux
```bash
# Using Python 3
python3 -m http.server 8000

# Then open: http://localhost:8000/
```

#### Windows
```bash
# Using Python 3
python -m http.server 8000

# Or using Node.js
npx serve
```

### Using Docker

```dockerfile
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

Build and run:
```bash
docker build -t replicore-docs .
docker run -p 80:80 replicore-docs
```

## 🌍 Deployment Options

### 1. **GitHub Pages** (Free, Easy)

```bash
# Copy contents to gh-pages branch
git checkout --orphan gh-pages
git rm -rf .
cp -r docs_html/* .
git add .
git commit -m "Deploy documentation"
git push origin gh-pages
```

Then enable Pages in GitHub settings → Pages → Source: gh-pages

Your docs will be at: `https://yourusername.github.io/replicore/`

### 2. **Netlify** (Free, Recommended)

1. Push to GitHub
2. Connect repo to Netlify
3. Build command: `python3 generate_docs.py`
4. Publish directory: `docs_html`
5. Deploy!

### 3. **Vercel** (Free, Fast)

```bash
npm install -g vercel

# Deploy directory
vercel deploy docs_html
```

### 4. **Traditional Web Host** (Paid, Full Control)

1. Upload all files to your hosting provider via FTP/SFTP
2. Ensure `index.html` is the default document
3. Your docs are live!

### 5. **AWS S3** (Scalable)

```bash
aws s3 sync docs_html s3://your-bucket-name \
  --acl public-read

# Enable static website hosting in S3 bucket settings
```

### 6. **Firebase Hosting** (Free Tier Available)

```bash
npm install -g firebase-tools
firebase init hosting
firebase deploy
```

## 🎨 Customization

### Changing Colors

Edit `generate_docs.py` in the CSS section:

```python
:root {
    --color-primary: #2e539e;      /* Main brand color */
    --color-secondary: #ff6b6b;    /* Accent color */
    --color-accent: #ffd43b;       /* Highlight color */
}
```

### Changing Logo/Branding

In `generate_docs.py`, modify the header HTML in `generate_html_page()`:

```html
<h1>📚 Replicore Documentation</h1>  <!-- Change this -->
```

### Adding Custom Pages

1. Create a new `.md` file in the `docs/` directory
2. Run: `python3 generate_docs.py`
3. New HTML files are automatically generated

## 📊 Features

- ✅ **Responsive Design** - Works on mobile, tablet, desktop
- ✅ **Dark Mode** - Toggle with button, saved to local storage
- ✅ **Search** - Filter docs by typing in sidebar search box
- ✅ **Fast Navigation** - Organized sidebar with 10+ sections
- ✅ **No Dependencies** - Pure HTML/CSS/JavaScript
- ✅ **SEO Friendly** - Proper meta tags, semantic HTML
- ✅ **Accessibility** - WCAG compliant structure
- ✅ **Performance** - No external dependencies, <100KB per page

## 🔄 Regenerating Documentation

Whenever you update markdown files in `docs/`:

```bash
python3 generate_docs.py
```

This will:
1. Read all `.md` files from `docs/`
2. Convert to HTML with proper styling
3. Generate navigation sidebar
4. Create `manifest.json` with metadata
5. Output to `docs_html/`

## 📋 File Structure

```
docs_html/
├── index.html                              # Main hub
├── 01_GETTING_STARTED.html                # All documentation
├── 02_ARCHITECTURE.html
├── ... (28 more documentation files)
├── 24_SYNC_ORCHESTRATION_STRATEGY.html
├── manifest.json                           # Metadata
└── README.md                               # This file
```

## 🔐 Security Considerations

- All files are static HTML - no server-side code
- No database connections or sensitive data
- Safe to host on any standard web server
- Consider:
  - HTTPS/SSL certificate (free with Let's Encrypt)
  - CSP headers to prevent injections
  - Cache headers for performance

### Example Nginx config with security headers:

```nginx
server {
    listen 443 ssl http2;
    server_name docs.example.com;

    ssl_certificate /etc/letsencrypt/live/docs.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/docs.example.com/privkey.pem;

    root /var/www/replicore/docs_html;
    index index.html;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Caching
    expires 1h;
    add_header Cache-Control "public, max-age=3600" always;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

## 📈 Analytics

The documentation website is static, but you can add analytics by:

### Option 1: Google Analytics (No Code Required)
Add a `<script>` tag to track page views

### Option 2: Plausible Analytics (Privacy-Focused)
```html
<script defer data-domain="docs.replicore.dev" src="https://plausible.io/js/script.js"></script>
```

## 🐛 Troubleshooting

### Pages not found (404 errors)

**Cause**: Web server not configured correctly
**Fix**: Ensure `index.html` is the default document in your server config

### Dark mode not working

**Cause**: localStorage blocked
**Fix**: No fix needed - graceful degradation, uses light mode

### Slow loading

**Cause**: Large page files
**Fix**: Enable gzip compression on web server

### Navigation links broken

**Cause**: Incorrect file paths
**Fix**: Regenerate with `python3 generate_docs.py`

## 📞 Support

For issues with the documentation website:

1. Check if source `.md` files are updated
2. Regenerate HTML: `python3 generate_docs.py`
3. Clear browser cache (Cmd+Shift+R on Mac)
4. Try a different browser
5. Check server logs for errors

## 📝 Maintenance

### Weekly
- Check for broken links (manual or automated tools)
- Monitor analytics/usage stats
- Review error logs

### Monthly
- Update documentation files as features change
- Regenerate HTML
- Test on different browsers/devices
- Update version numbers in header

### Quarterly
- Review design/UX
- Collect feedback from users
- Consider UI improvements
- Update dependencies (if using any)

## 🎁 Bonuses

### SEO Optimization

Each page includes:
- Proper `<title>` tags
- Meta descriptions
- Open Graph tags (for social sharing)
- Structured data (JSON-LD optional)

### Mobile Optimization

- Responsive design scales 320px → 4K
- Touch-friendly navigation
- Fast load times
- Mobile-tested layouts

### Accessibility (a11y)

- Semantic HTML structure
- ARIA labels where needed
- Keyboard navigation support
- High contrast mode support
- Screen reader friendly

## 📄 License

Same as Replicore framework (MIT)

---

**Generated**: March 9, 2026  
**Version**: 1.0  
**Total Pages**: 32  
**Total Size**: ~1.3 MB (all files)

For more information, visit the main [Replicore GitHub](https://github.com)
