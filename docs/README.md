# Omnizip Documentation

This directory contains the documentation site for Omnizip, built with [Jekyll](https://jekyllrb.com/) and the [Just the Docs](https://just-the-docs.github.io/just-the-docs/) theme.

## Building the Documentation Site

### Prerequisites

- Ruby 3.0 or higher
- Bundler

### Installation

```bash
cd docs
bundle install
```

### Building

```bash
bundle exec jekyll build
```

The built site will be in the `_site` directory.

### Serving Locally

```bash
bundle exec jekyll serve
```

Then open http://localhost:4000/omnizip/ in your browser.

## Documentation Structure

```
docs/
├── index.adoc                    # Home page
├── getting-started/              # Installation and quick start guides
├── guides/                       # Comprehensive usage guides
│   ├── basic-usage/             # Basic operations
│   ├── advanced-usage/          # Advanced features
│   ├── compression-algorithms/  # Algorithm documentation
│   ├── archive-formats/         # Format documentation
│   └── filters/                 # Filter documentation
├── reference/                    # Technical reference
│   ├── cli/                     # CLI documentation
│   └── api/                     # Ruby API documentation
├── resources/                    # Additional resources
├── concepts/                     # Core concepts
├── developer/                    # Development documentation
├── examples/                     # Usage examples
└── troubleshooting/              # Troubleshooting guides
```

## Writing Documentation

Documentation is written in [AsciiDoc](https://asciidoctor.org/) format. Each page should start with YAML front matter:

```yaml
---
title: Page Title
nav_order: 1
---
```

### Linking

Use AsciiDoc link syntax:

- Internal link: `link:path/to/page.adoc[Link text]`
- External link: `https://example.com[Link text]`

### Code Blocks

Use source code blocks with syntax highlighting:

```asciidoc
[source,ruby]
----
require 'omnizip'
----
```

## Checking Links

The documentation site includes a link checker using [lychee](https://github.com/lycheeverse/lychee). To check links:

```bash
# Install lychee
cargo install lychee

# Run link checker
cd docs
lychee --config .lychee.toml _site
```

## License

Copyright 2025 Ribose Inc.
