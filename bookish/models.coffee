# # Backbone Models
# This module contains backbone models used throughout the application
define ['exports', 'jquery', 'backbone', 'bookish/media-types', 'i18n!bookish/nls/strings'], (exports, jQuery, Backbone, MEDIA_TYPES, __) ->


  # Custom Models defined above are mixed in using `BaseContent.initialize`
  BaseContent = Backbone.Model.extend
    # New content is given an id before it is saved so it can be added to a book
    isNew = -> not @id or @id.match(/^_NEW:/)
    initialize: ->
      throw 'BUG: No mediaType set' if not @mediaType
      throw 'BUG: No mediaType not registered' if not MEDIA_TYPES.get @mediaType
      @id = "_NEW:#{@cid}" if not @id

  # This gets used by `DeferrableCollection` but is instantiated afterwards
  ALL_CONTENT = null

  # ## Promises
  # A model representing a piece of content may have been instantiated
  # (ie an entry as a result of a search) but not fetched yet.
  #
  # When dealing with a model (except for `id`, `title`, or `mediaType`)
  # be sure to call `.loaded().then(cb)` first.
  #
  # Once the model is loaded (fetched) call the callbacks.

  Deferrable = Backbone.Model.extend
    loaded: (flag=false) ->
      if flag
        deferred = jQuery.Deferred()
        deferred.resolve @
        @_promise = deferred.promise()
        # Mark it as loaded for the views
        @set {_done: true}

      # Silently update the model (the user has not seen the model yet)
      # so `model.hasChanged()` returns `false` (to know when to enable Saving)
      if not @_promise or 'rejected' == @_promise.state()
        @set {_loading: true}
        @_promise = @fetch # {silent:true}
          error: (model, message, options) =>
            @trigger 'error', model, message, options
        @_promise
        .progress (progress) =>
          @set {_progress: progress}
        .done =>
          # Once we are done fetching and the change events have fired
          # clear all the `.changed` flag so save does not think it has dirty models
          delete @changed
          @set {_done: true}
        .fail (error) =>
          @trigger 'error', error

      return @_promise

    toJSON: ->
      json = Backbone.Model.prototype.toJSON.apply(@, arguments)
      json.mediaType = @mediaType
      return json

  DeferrableCollection = Backbone.Collection.extend
    loaded: (flag) ->
      if flag
        deferred = jQuery.Deferred()
        deferred.resolve @
        @_promise = deferred.promise()
        # Mark it as loaded for the views
        @_done = true

      # Silently update the model (the user has not seen the model yet)
      # so `model.hasChanged()` returns `false` (to know when to enable Saving)
      if not @_promise or 'rejected' == @_promise.state()
        @_promise = @fetch # {silent:true}
          error: (model, message, options) =>
            @trigger 'error', model, message, options

        # Once we are done fetching and the change events have fired
        # clear all the `.changed` flag so save does not think it has dirty models
        @_promise.then => delete @changed

      return @_promise

    toJSON: -> (model.toJSON() for model in @models)
    initialize: ->
      @on 'add',   (model) -> ALL_CONTENT.add model
      @on 'reset', (collection, options) -> ALL_CONTENT.add collection.toArray()


  # ## All Content
  #
  # To prevent multiple copies of a model from floating around a single
  # copy of all referenced content (loaded or not) is kept in this Collection
  #
  # This should be read-only by others
  # New content models should be created by calling `ALL_CONTENT.add {}`
  AllContent = DeferrableCollection.extend
    model: BaseContent
    # Override the `DeferrableCollection` initialize because this is the `ALL_CONTENT`
    initialize: ->
      # Never wait to fetch
      @loaded(true)

  ALL_CONTENT = new AllContent()


  # When searching for text, perform a local filter on content while we wait
  # for the server to respond.
  #
  # This Collection takes another Collection and maintains an active filter on it.
  exports.FilteredCollection = Backbone.Collection.extend
    defaults:
      collection: null
    setFilter: (str) ->
      return if @filterStr == str
      @filterStr = str

      # Remove anything that no longer matches
      models = (@collection.filter (model) => @isMatch(model))
      @reset models

    isMatch: (model) ->
      return true if not @filterStr
      title = model.get('title') or ''
      found = title.toLowerCase().search(@filterStr.toLowerCase()) >= 0
      return true if found

      body = model.get('body') or ''
      bodyText = body.replace(/\<(\/?[^\\>]+)\\>/, ' ').replace(/\s+/, ' ').trim()

    initialize: (models, options) ->
      @filterStr = options.filterStr or ''
      @collection = options.collection
      throw 'BUG: Cannot filter on a non-existent collection' if not @collection

      @add (@collection.filter (model) => @isMatch(model))


      @listenTo @collection, 'add',    (model) => @add model if @isMatch(model)
      @listenTo @collection, 'remove', (model) => @remove model
      @listenTo @collection, 'reset',  (model, options) =>
        @reset()
        @add (@collection.filter (model) => @isMatch(model))

      @listenTo @collection, 'change', (model) =>
        if @isMatch(model)
          @add model
        else
          @remove model



  # The `Content` model contains the following members:
  #
  # * `title` - an HTML title of the content
  # * `language` - the main language (eg `en-us`)
  # * `subjects` - an array of strings (eg `['Mathematics', 'Business']`)
  # * `keywords` - an array of keywords (eg `['constant', 'boltzmann constant']`)
  # * `authors` - an `Collection` of `User`s that are attributed as authors
  BaseContent = Deferrable.extend
    mediaType: 'application/vnd.org.cnx.module'
    defaults:
      title: null
      subjects: []
      keywords: []
      authors: []
      copyrightHolders: []
      # Default language for new content is the browser's language
      language: (navigator?.userLanguage or navigator?.language or 'en').toLowerCase()


  # Represents a "collection" in [Connexions](http://cnx.org) terminology and an `.opf` file in an EPUB
  BaseBook = Deferrable.extend
    mediaType: 'application/vnd.org.cnx.collection'
    defaults:
      manifest: null
      # `navTreeStr` is stored as a JSON string so events are fired when changes are made
      navTreeStr: '[]'

    # Subclasses can provide a better Collection for storing Content items in a book
    # so the book can listen to changes.
    manifestType: Backbone.Collection

    toJSON: ->
      json = Deferrable.prototype.toJSON.apply(@, arguments)
      json.navTree = JSON.parse @get 'navTreeStr'
      return json

    # Takes an element representing a `<nav epub:type="toc"/>` element
    # and returns a JSON tree with the following structure:
    #
    #     [
    #       {id: 'path/to/file1.html', title: 'Appendix', children: [...] },
    #       {title: 'Unit 3', class: 'unit', children: [...] }
    #     ]
    # See [The toc nav Element](http://idpf.org/epub/30/spec/epub30-contentdocs.html#sec-xhtml-nav-def-types-toc) for more information.
    #
    # This method is also used by the DnD edit view.
    #
    # Example from an ePUB3:
    #
    #     <nav epub:type="toc">
    #       <ol>
    #         <li><a href="path/to/file1.html">Appendix</a></li>
    #         <li class="unit"><span>Unit 3</span><ol>[...]</ol></li>
    #       </ol>
    #     </nav>
    #
    # Example from the Drag-and-Drop Book editor (Tree View):
    #
    #     <div>
    #       <ol>
    #         <li><span data-id="path/to/file1.html">Appendix</a></li>
    #         <li class="unit"><span>Unit 3</span><ol>[...]</ol></li>
    #       </ol>
    #     </nav>
    parseNavTree: (li) ->
      $li = jQuery(li)

      $a = $li.children 'a, span'
      $ol = $li.children 'ol'

      obj = {id: $a.attr('href') or $a.data('id'), title: $a.text()}

      # The custom class is either set on the `$span` (if parsing from the editor) or on the `$a` (if parsing from an EPUB)
      obj.class = $a.data('class') or $a.not('span').attr('class')

      obj.children = (@parseNavTree(li) for li in $ol.children()) if $ol[0]
      return obj

    # Creates a Manifest collection of all content it should listen to.
    #
    # For example, changes to `id` or `title` of a piece of content will update the navigation tree.
    #
    # Similarly, an update to the navigation tree will create new models.
    initialize: ->
      ALL_CONTENT.add @

      @manifest = new @manifestType()
      @manifest.on 'add',   (model, collection) -> ALL_CONTENT.add model
      @manifest.on 'reset', (model, collection) -> ALL_CONTENT.add model

      # If a model's id changes then update the `navTree` (it was a new model that got saved)
      @manifest.on 'change:id', (model, newValue, oldValue) =>
        navTree = JSON.parse @get('navTreeStr')
        # Find the node that has an `id` to this model
        recFind = (nodes) ->
          for node in nodes
            return node if model.id == oldValue
            if node.children
              found = recFind node.children
              return found if found
        node = recFind(navTree)
        return console.error 'BUG: There is an entry in the tree but no corresponding model in the manifest' if not node
        node.id = newValue
        @set 'navTreeStr', JSON.stringify navTree

      @manifest.on 'change:title', (model, newValue, oldValue) =>
        navTree = JSON.parse @get('navTreeStr')
        # Find the node that has an `id` to this model
        recFind = (nodes) ->
          for node in nodes
            return node if model.id == node.id
            if node.children
              found = recFind node.children
              return found if found
        node = recFind(navTree)
        return console.error 'BUG: There is an entry in the tree but no corresponding model in the manifest' if not node
        node.title = newValue
        @set 'navTreeStr', JSON.stringify navTree

      @on 'change:navTreeStr', (model, navTreeStr, options) =>
        # **TODO:** Remove manifest entries if they are not referred to by the navTree or any modules in the book.
        recAdd = (nodes) =>
          for node in nodes
            if node.id
              contentModel = @manifest.add {id: node.id, title: node.title, mediaType: 'application/vnd.org.cnx.module'}
            recAdd node.children if node.children
        recAdd(JSON.parse navTreeStr)


    # **FIXME:** Somewhat hacky way of creating a new piece of content
    prependNewContent: (model, mediaType) ->
      if model instanceof Backbone.Model
        @manifest.add model

      else if mediaType
        config = model
        throw 'BUG: Media type not registered' if not MEDIA_TYPES.get mediaType

        # Create the model from a config and add it to the manifest
        ContentType = MEDIA_TYPES.get(mediaType).constructor
        model = new ContentType config
        # Mark it as sync'd so we don't try to fetch a non-existent file
        model.loaded(true)

        @manifest.add model
        # HACK: Since it is new content there is nothing to load but we already set an `id`
        console.warn 'FIXME: Hack for new content'

      else
        # Otherwise, just add a container
        model = new Backbone.Model model

      # Prepend to the navTree
      navTree = JSON.parse @get('navTreeStr')
      navTree.unshift {id: model.get('id'), title: model.get('title')}
      @set 'navTreeStr', JSON.stringify navTree


  # Compare by `mediaType` (Collections/Books 1st), then by title/URL
  CONTENT_COMPARATOR = (a, b) ->
    A = a.mediaType or ''
    B = b.mediaType or ''
    return -1 if B < A
    return 1  if A < B

    A = a.get('title') or a.id or ''
    B = b.get('title') or b.id or ''
    return 1 if B < A
    return -1  if A < B

    return 0

  # Add the 2 basic Media Types already defined above
  MEDIA_TYPES.add 'application/vnd.org.cnx.module',
    constructor: BaseContent

  MEDIA_TYPES.add 'application/vnd.org.cnx.collection',
    constructor: BaseBook

  # Finally, export only the pieces needed
  exports.BaseContent = BaseContent
  exports.BaseBook = BaseBook
  exports.Deferrable = Deferrable
  exports.DeferrableCollection = DeferrableCollection
  exports.ALL_CONTENT = ALL_CONTENT
  exports.MEDIA_TYPES = MEDIA_TYPES
  exports.CONTENT_COMPARATOR = CONTENT_COMPARATOR
  # Other implementations can override this
  exports.WORKSPACE = ALL_CONTENT
  return exports
