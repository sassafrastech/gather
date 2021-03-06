# Manages add to home screen button.
Gather.Views.AddToHomeScreenView = Backbone.View.extend
  initialize: (options) ->
    @options = options
    window.addEventListener('beforeinstallprompt', (event) =>
      # Prevent Chrome 67 and earlier from automatically showing the prompt
      event.preventDefault()
      unless @optedOut()
        # Stash the event so it can be triggered later.
        @deferredPrompt = event
        # Update UI notify the user they can add to home screen
        @$el.show()
    )

  events:
    'click .btn': 'add'
    'click .opt-out': 'optOut'

  add: ->
    # Hide our user interface that shows our A2HS button
    @$el.hide()
    # Show the prompt
    @deferredPrompt.prompt()
    # Wait for the user to respond to the prompt. We need to handle this event for it to work, I think.
    @deferredPrompt.userChoice.then((choiceResult) =>
      if choiceResult.outcome == 'accepted'
        console.log('User accepted the A2HS prompt')
      else
        console.log('User dismissed the A2HS prompt')
      @deferredPrompt = null
    )

  optOut: (event) ->
    event.preventDefault()
    @$el.hide()
    document.cookie = "dontAddToHomeScreen=1;domain=.#{@options.host};" +
      "path=/;expires=Tue, 19 Jan 2038 03:14:07 UTC;"

  optedOut: ->
    return true if window.localStorage.getItem('dontAddToHomeScreen') # Legacy
    return true if document.cookie.indexOf('dontAddToHomeScreen=1') != -1
    false
