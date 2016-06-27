{CompositeDisposable, Point, Range} = require 'atom'

String::addSlashes = ->
  @replace(/[\\"]/g, "\\$&").replace /\u0000/g, "\\0"

module.exports =
  config:
    whichApp:
      type: 'string'
      default: 'Stata'
      description: 'Which application to send code to'
    focusWindow:
      type: 'boolean'
      default: true
      description: 'After code is sent, bring focus to where it was sent'
    notifications:
      type: 'boolean'
      default: true
      description: 'Send notifications if there is an error sending code'

  subscriptions: null

  activate: (state) ->
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:run-dofile', => @runDofile()
    console.log('openned state exec!')

  deactivate: ->
    @subscriptions.dispose()

  runDofile: ->
    editor = atom.workspace.getActiveTextEditor()
    whichApp = atom.config.get 'stata-exec.whichApp'
    console.log('in runDofile!')
    osascript = require 'node-osascript'
    command = []
    focusWindow = atom.config.get 'stata-exec.focusWindow'
    documentTitle = editor.getPath()
    console.log(documentTitle)

    dofileCommand = 'tell application "' + whichApp + '" to open "' + documentTitle + '"'
    activateCommand = 'tell application "' + whichApp + '" to activate'

    if focusWindow
      command.push activateCommand
    command.push dofileCommand
    command = command.join('\n')
    console.log(command)

    osascript.execute command, (error, raw) ->
        if error
          console.error error
          console.error 'Applescript: ', command
