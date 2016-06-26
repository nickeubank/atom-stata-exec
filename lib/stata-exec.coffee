{CompositeDisposable, Point, Range} = require 'atom'

String::addSlashes = ->
  @replace(/[\\"]/g, "\\$&").replace /\u0000/g, "\\0"

module.exports =
  config:
    whichApp:
      type: 'string'
      default: 'Stata 13.1'
      description: 'Which application to send code to'
    advancePosition:
      type: 'boolean'
      default: false
      description: 'Cursor advances to the next line after ' +
        'sending the current line when there is no selection'
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

  deactivate: ->
    @subscriptions.dispose()

  _getEditorAndBuffer: ->
    editor = atom.workspace.getActiveTextEditor()
    buffer = editor.getBuffer()
    return [editor, buffer]

  runDofile: ->
    window.beep()
    osascript = require 'node-osascript'
    command = []
    focusWindow = atom.config.get 'stata-exec.focusWindow'
    documentTitle = getPath()+getTitle()
    dofileCommand ='tell application "Stata 13.1" to open ' + documentTitle
    window.beep()
    window.alert(dofileCommand)
    if focusWindow
      command.push 'tell application "Stata 13.1" to activate'
    command.push dofileCommand
    command = command.join('\n')

    osascript.execute command, {code: selection},
      (error, result, raw) ->
        if error
          console.error error
          console.error 'code: ', selection
          console.error 'Applescript: ', command
