define [
  'underscore'
  'backbone'
  'marionette'
  'bookish/controller'
  'bookish/models'
  'epub/models'
  'bookish/auth'
  'bookish/views'
  'hbs!gh-book/sign-in-out'
  'hbs!gh-book/fork-book-item'
  'css!bookish'
], (_, Backbone, Marionette, Controller, AtcModels, EpubModels, Auth, Views, SIGN_IN_OUT, FORK_BOOK_ITEM) ->


  # ## Auth View
  # The top-right of each page should have either:
  #
  # 1. a Sign-up/Login link if not logged in
  # 2. a logoff link with the current user name if logged in
  #
  # This view updates when the login state changes
  Views.AuthView = Marionette.ItemView.extend
    template: SIGN_IN_OUT
    events:
      'click #sign-in':       'signIn'
      'click #sign-out':      'signOut'
      'click #save-settings': 'saveSettings'
      'click #save-content':  'saveContent'
      'click #fork-book':     'forkBook'
      'click .other-books':   'otherBooks'

    initialize: ->
      # Bind a function to the window if the user tries to navigate away from this page
      beforeUnload = =>
        return 'You have unsaved changes. Are you sure you want to leave this page?' if @hasChanged
      jQuery(window).on 'beforeunload', beforeUnload


      # Listen to all changes made on Content so we can update the save button
      @listenTo AtcModels.ALL_CONTENT, 'change', (model, b,c) =>
        # Figure out if the model was just fetched (all the changed attributes used to be 'undefined')
        # or if the attributes did actually change

        $save = @$el.find '#save-content'
        checkIfContentActuallyChanged = =>
          if model.hasChanged()
            @hasChanged = true
            $save.removeClass('disabled')
            $save.addClass('btn-primary')

        setTimeout (=> checkIfContentActuallyChanged()), 100

        if false
          # Delete any properties that were null before
          changes = model.changedAttributes()
          (delete changes[attribute] if not model.previous(attribute)) for attribute of changes

          # If there was anything that was actually changed (not null before) then mark the save button.
          if _.keys(changes).length
            @hasChanged = true
            $save = @$el.find '#save-content'
            $save.removeClass('disabled')
            $save.addClass('btn-primary')

      # If the repo changes and all of the content is reset, update the button
      disableSave = =>
        @hasChanged = false
        $save = @$el.find '#save-content'
        $save.addClass('disabled')
        $save.removeClass('btn-primary')

      @listenTo AtcModels.ALL_CONTENT, 'sync', disableSave
      @listenTo AtcModels.ALL_CONTENT, 'reset', disableSave

      # Listen to model changes
      @listenTo @model, 'change', => @render()

    # Add the `canFork` bit to the resulting JSON so the template knows if the
    # current user is the same as the current `repoUser` (Do not show the fork button).
    templateHelpers: ->
      return {canFork: @model.get('username') != @model.get('repoUser') or not @model.get('password')}

    onRender: ->
      # Enable tooltips
      @$el.find('*[title]').tooltip()

    signIn: ->
      # Set the username and password in the `Auth` model
      @model.set
        username: @$el.find('#github-username').val()
        password: @$el.find('#github-password').val()

    # Clicking on the link will redirect to the logoff page
    # Before it does, update the model
    signOut: -> @model.signOut()

    forkBook: ->
      # Show an alert if the user is not logged in
      return alert 'Please log in to fork or just go to the github page and fork the book!' if not @model.get 'password'

      # Populate the fork modal before showing it
      $fork = @$el.find '#fork-book-modal'


      forkHandler = (org) -> () ->
        Auth.getRepo().fork (err, resp) ->
          # Close the modal dialog
          $fork.modal('hide')

          throw "Problem forking: #{err}" if err

          setTimeout(->
            Auth.set 'repoUser', (org or Auth.get('username'))
          , 10000)

          alert 'Thanks for copying!\nThe current repository (in settings) will be updated to point to your copy of the book. \nThe next time you click Save the changes will be saved to your copied book.\nIf not, refresh the page and change the Repo User in Settings.'


      Auth.getUser().orgs (err, orgs) ->
        $list = $fork.find('.modal-body').empty()

        $item = @$(FORK_BOOK_ITEM {login: Auth.get 'username'})
        $item.find('button').on 'click', forkHandler(null)
        $list.append $item

        _.each orgs, (org) ->
          $item = @$(FORK_BOOK_ITEM {login: "#{org.login} (Organization)"})
          # For now disallow forking to organizations.
          #     $item.find('button').on 'click', forkHandler(org)
          $item.addClass 'disabled'

          $list.append $item


        # Show the modal
        $fork.modal('show')


    otherBooks: (evt) ->
      $config = @$(evt.target)

      # Add a trailing slash to the root path if one is set
      rootPath = $config.data('rootPath')
      rootPath += '/' if rootPath and rootPath[rootPath.length-1] != '/'

      # Close the modal
      $save = @$el.find '#save-settings-modal'
      $save.modal('hide')

      @model.set
        repoUser: $config.data('repoUser')
        repoName: $config.data('repoName')
        branch:   $config.data('branch')
        rootPath: rootPath


    saveSettings: ->
      # Add a trailing slash to the root path if one is set
      rootPath = @$el.find('#github-rootPath').val()
      rootPath += '/' if rootPath and rootPath[rootPath.length-1] != '/'

      # Update the repo settings
      @model.set
        repoUser: @$el.find('#github-repoUser').val()
        repoName: @$el.find('#github-repoName').val()
        branch:   @$el.find('#github-branch').val()
        rootPath: rootPath

    # Save each model in sequence.
    # **FIXME:** This should be done in a commit batch
    saveContent: ->
      return alert 'You need to sign (and probably fork this book) before you can save to github' if not Auth.get 'password'
      $save = @$el.find('#save-progress-modal')
      $saving     = $save.find('.saving')
      $alertError = $save.find('.alert-error')
      $successBar = $save.find('.progress > .bar.success')
      $errorBar   = $save.find('.progress > .bar.error')
      $label = $save.find('.label')

      allContent = AtcModels.ALL_CONTENT.filter (model) -> model.hasChanged()
      total = allContent.length
      errorCount = 0
      finished = false

      recSave = ->
        $successBar.width(((total - allContent.length - errorCount) * 100 / total) + '%')
        $errorBar.width((  errorCount                               * 100 / total) + '%')

        if allContent.length == 0
          if errorCount == 0
            finished = true
            AtcModels.ALL_CONTENT.trigger 'sync'
            # Clear the dirty flag
            AtcModels.ALL_CONTENT.each (model) -> delete model.changed
            $save.modal('hide')
          else
            $alertError.removeClass 'hide'

        else
          model = allContent.shift()
          $label.text(model.get('title'))

          # Clear the changed bit since it is saved.
          #     delete model.changed
          #     saving = true; recSave()
          saving = model.save null,
              success: recSave
              error: -> errorCount += 1
          if not saving
            console.log "Skipping #{model.id} because it is not valid"
            recSave()

      $alertError.addClass('hide')
      $saving.removeClass('hide')
      $save.modal('show')
      recSave()

      setTimeout(->
        if total and (not finished or errorCount)
          $save.modal('show')
          $alertError.removeClass('hide')
          $saving.addClass('hide')
      , 5000)
