// Generated by CoffeeScript 1.3.3
(function() {

  require.config({
    paths: {
      aloha: 'http://wysiwhat.github.com/Aloha-Editor/src/lib/aloha',
      'bookish/auth': 'gh-book/auth',
      base64: 'lib/github/lib/base64',
      github: 'lib/github/github'
    },
    shim: {
      github: {
        deps: ['underscore', 'base64'],
        exports: 'Github'
      }
    }
  });

}).call(this);
