# Configures modules specific to talking to a github repository
require.config

  # # Configure Library Locations
  paths:

    # Change the Stub Auth piece
    'bookish/auth': 'gh-book/auth'

    # Github-Specific libraries
    base64: 'node_modules/github-js/lib/base64'
    github: 'node_modules/github-js/github'


  # # Shims
  # To support libraries that were not written for AMD
  # configure a shim around them that mimics a `define` call.
  #
  # List the dependencies and what global object is available
  # when the library is done loading (for jQuery plugins this can be `jQuery`)
  shim:

    # ## Github-Specific libraries
    github:
      deps: ['underscore', 'base64']
      exports: 'Github'