# What is this?

This is a Javascript book editor that saves to GitHub.
Since it is just javascript, it can be hosted on github.com by using the `gh-pages` branch.

Editing various mime-types is supported by writing plugins (ie SVG, Markdown, etc).

# How does it work?

Unzip an EPUB3 document and push it to GitHub.

This editor uses the GitHub API to read/write EPUB3 files (defined in http://idpf.org/epub/30/spec/epub30-overview.html ).


# Development and Building

Below are instructions for building the book editor yourself and a layout
of how the code is organized.

## Building Yourself

1. Create a local branch named `gh-pages`
2. Run `npm install .` to download the dependencies
3. Build a minified Javascript file by running `r.js` (see https://github.com/jrburke/r.js)
4. Add the minified Javscript file, commit, and push the changes back to github

## Building Documentation

Documentation is built using `docco`.

    find . -name "*.coffee" | grep -v './lib/' | grep -v './node_modules' | xargs ./node_modules/docco/bin/docco

Check the `./docs` directory to read through the different modules.

## Directory Layout

* `atc/*`   Base models and views for editing books (TOC navigation, HTML content, media resources)
* `epub/*`  Models specific to manipulating EPUB3 books (ie a book is an OPF file plus a separate navigation HTML file)
* `gh-book/*` GitHub-specific views and `Backbone.sync` calls that communicate to read/write files to GitHub

* `atc/models.coffee`    Backbone Models
* `atc/views.coffee`     Marionette Views
* `atc/views/*`          Handlebars Templates
* `atc/nls/*.coffee`     i18n strings (and HTML) http://requirejs.org/docs/api.html#i18n
* `lib/`                 3rd party libraries
* `config/*`             Custom configuration of 3rd party libraries (Aloha Editor and MathJax)
* `config/atc-config.coffee` Includes paths to 3rd party libs so we can minify them

* `gh-book.coffee`   The starting point for all javascript

## Adding a 3rd party library

1. If a npm version of it exists, add it to `package.json`
2. Otherwise, add it to `install-libs.sh` (which is called when you run `npm install .`)
3. Add the lib to `config/atc-config.coffee` (both in `path` and `shim`)
    * The name should be all lowercase
    * Use a `-` if the library name is more than one word
    * Don't use `/` or `.`

4. Use it in your module by adding it to the dependencies in `define`
