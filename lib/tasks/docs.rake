# frozen_string_literal: true

# Documentation pipeline — NO Jekyll. AsciiDoc sources (readme-docs/ and
# docs/) are rendered to static HTML by Coradoc (coradoc-html's Static
# converter: TOC, HTML5 layout, templates). Output lands in docs/site/.
#
#   rake docs:build   — render all .adoc pages into docs/site/
#   rake docs:index   — regenerate docs/site/index.html only
#   rake docs:links   — lychee link check over the built site
#
# Coradoc is a transformation library, not an SSG; this task is the thin
# multi-page orchestrator (page walk + nav index) per its architecture
# decision (FEATURE-template-renderer: emitters live downstream).

require "fileutils"

DOCS_PAGES = %w[
  README.adoc
  readme-docs/installation.adoc
  readme-docs/cli-usage.adoc
  readme-docs/api-usage.adoc
  readme-docs/compression-algorithms.adoc
  readme-docs/compression-profiles.adoc
  readme-docs/format-converter.adoc
  readme-docs/advanced-features.adoc
  readme-docs/archive-formats.adoc
  readme-docs/rar-archives.adoc
  readme-docs/par2-archives.adoc
  readme-docs/encryption-checksums.adoc
  readme-docs/preprocessing-filters.adoc
  readme-docs/architecture.adoc
  readme-docs/performance-profiler.adoc
  docs/compatibility.adoc
  docs/rust-backend.md
  docs/RAR_WRITE_SUPPORT.md
  docs/xar_format.md
].freeze

DOCS_SITE = File.expand_path("docs/site", "#{__dir__}/../..")

def docs_render_page(src, dest, title)
  require "coradoc/asciidoc" # registers the :asciidoc parse format
  require "coradoc/html"

  html =
    if src.end_with?(".md")
      # Markdown sources ride along verbatim (pre-wrapped) until they are
      # converted to AsciiDoc.
      <<~HTML
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><title>#{title}</title></head>
        <body><pre>#{File.read(src).gsub(/[<>&]/, '&' => '&amp;', '<' => '&lt;', '>' => '&gt;')}</pre></body></html>
      HTML
    else
      doc = Coradoc.parse(File.read(src), format: :asciidoc)
      Coradoc::Html::Static.convert(
        doc,
        include_toc: true,
        toc_levels: 2,
        meta_tags: { title: title },
      )
    end
  # AsciiDoc sources cross-link *.adoc siblings; the site serves .html.
  # The repo README renders as the site root index.html.
  html = html.gsub(/href="([^"]+?)\.(?:adoc|md)(#[^"]*)?"/) do
    target = Regexp.last_match(1)
    anchor = Regexp.last_match(2).to_s.sub(/\A#/, "")
    anchor = "##{anchor}" unless anchor.empty?
    if target.end_with?("/README", "README") && target !~ /docs\//
      %(href="#{target.sub(%r{/?(?:\.\./)?README\z}, '')}index.html#{anchor}")
    elsif File.exist?("#{DOCS_SITE}/#{target}.html")
      %(href="#{target}.html#{anchor}")
    else
      Regexp.last_match(0)
    end
  end
  File.write(dest, html)
end

def docs_page_title(path)
  File.read(path).lines.each do |line|
    return Regexp.last_match(1).strip if line =~ /\A=+\s+(.+)\z/
    break if line !~ /\A\s*\z/ && !line.start_with?("=")
  end
  File.basename(path, ".*")
end

namespace :docs do
  desc "Render all documentation pages into docs/site/ (Coradoc, no Jekyll)"
  task :build do
    FileUtils.rm_rf(DOCS_SITE)
    FileUtils.mkdir_p(DOCS_SITE)

    nav = []
    DOCS_PAGES.each do |page|
      next unless File.exist?(page)

      out = File.join(DOCS_SITE,
                      page == "README.adoc" ? "index.html" : "#{page.sub('.adoc', '').sub('.md', '')}.html")
      FileUtils.mkdir_p(File.dirname(out))
      title = docs_page_title(page)
      docs_render_page(page, out, title)
      nav << [title, out.delete_prefix("#{DOCS_SITE}/")]
      puts "rendered #{page} -> #{out}"
    end

    Rake::Task["docs:index"].reenable
    Rake::Task["docs:index"].invoke(nav)
  end

  desc "Regenerate the site index page"
  task :index, [:nav] do |_t, args|
    nav = args[:nav] || DOCS_PAGES.map do |p|
      rel = p == "README.adoc" ? "index" : p.sub(".adoc", "").sub(".md", "")
      [docs_page_title(p), "#{rel}.html"]
    end
    links = nav.map { |title, href| %(<li><a href="#{href}">#{title}</a></li>) }.join("\n")
    html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head><meta charset="utf-8"><title>Omnizip documentation</title></head>
      <body>
      <h1>Omnizip documentation</h1>
      <ul>
      #{links}
      </ul>
      </body>
      </html>
    HTML
    File.write(File.join(DOCS_SITE, "index.html"), html)
  end

  desc "Link-check the built site with lychee"
  task :links do
    sh "lychee --config docs/lychee.toml docs/site || true"
  end
end
