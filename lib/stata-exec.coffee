{CompositeDisposable, Point, Range} = require 'atom'

String::addSlashes = ->
  @replace(/[\\"]/g, "\\$&").replace /\u0000/g, "\\0"

module.exports =
  config:
    whichApp:
      type: 'string'
      default: 'StataMP'
      description: 'Which application to send code to'
    advancePosition:
      type: 'boolean'
      default: false
      description: 'Cursor advances to the next line after ' +
        'sending the current line when there is no selection'
    skipComments:
      type: 'boolean'
      default: true
      description: 'When "advancePosition" is true, skip lines that contain ' +
        'only comments'
    focusWindow:
      type: 'boolean'
      default: true
      description: 'After code is sent, bring focus to where it was sent'
    notifications:
      type: 'boolean'
      default: true
      description: 'Send notifications if there is an error sending code'
    smartInsertOperator:
      type: 'boolean'
      default: true
      description: 'Try to be "smart" when inserting operators (see README)'

  subscriptions: null

  previousCommand: ''

  activate: (state) ->
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:send-command', => @sendCommand()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:send-previous-command', => @sendPreviousCommand()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:send-paragraph': => @sendParagraph()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:send-function': => @sendFunction()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:setwd', => @setWorkingDirectory()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:send-knitr': => @sendKnitr()

    # # this is for testing
    # @subscriptions.add atom.commands.add 'atom-workspace',
    #   'stata-exec:test',  => @getCurrentParagraphRange()

    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:insert-assignment', => @insertAssignment()

    @subscriptions.add atom.commands.add 'atom-workspace',
      'stata-exec:insert-pipe', => @insertPipe()

  deactivate: ->
    @subscriptions.dispose()

  _getEditorAndBuffer: ->
    editor = atom.workspace.getActiveTextEditor()
    buffer = editor.getBuffer()
    return [editor, buffer]

  sendCommand: ->
    whichApp = atom.config.get 'stata-exec.whichApp'
    [editor, buffer] = @_getEditorAndBuffer()
    # we store the current position so that we can jump back to it later
    # (if the user wants to)
    currentPosition = editor.getLastSelection().getScreenRange().end
    selection = @getSelection(whichApp)
    @sendCode(selection.selection, whichApp)

    advancePosition = atom.config.get 'stata-exec.advancePosition'
    if advancePosition and not selection.anySelection
      nextPosition = @_findForward(@nonEmptyLine, currentPosition.row + 1)
      if nextPosition?
        nextPosition ?= [currentPosition + 1, 0]
        editor.setCursorScreenPosition(nextPosition)
        editor.moveToFirstCharacterOfLine()
    else
      if not selection.anySelection
        editor.setCursorScreenPosition(currentPosition)

  sendPreviousCommand: ->
    whichApp = atom.config.get 'stata-exec.whichApp'
    @sendCode(@previousCommand, whichApp)

  sendCode: (code, whichApp) ->
    @previousCommand = code
    switch whichApp
      when apps.stata then @stata(code)
      else console.error 'stata-exec.whichApp "' + whichApp + '" is not supported.'

  getFunctionRange: ->
    # gets the range of the closest function above the cursor.
    # if there is no (proper) function, return false
    [editor, buffer] = @_getEditorAndBuffer()
    currentPosition = editor.getCursorBufferPosition()
    # search for the simple function that looks something like:
    # label <- function(...) {
    # in case the current function definition is on the current line
    currentPosition.row += 1
    backwardRange = [0, currentPosition]
    funRegex = new
      RegExp(/[a-zA-Z]+[a-zA-Z0-9_\.]*[\s]*(<-|=)[\s]*(function)[\s]*\(/g)
    foundStart = null
    editor.backwardsScanInBufferRange funRegex, backwardRange, (result) ->
      if result.range.start.column == 0
        foundStart = result.range
        result.stop()

    if not foundStart?
      console.error "Couldn't find the beginning of the function."
      return null

    # now look for the end
    numberOfLines = editor.getLineCount()
    forwardRange = [foundStart.start, new Point(numberOfLines + 1, 0)]

    foundEnd = null
    editor.scanInBufferRange /}/g, forwardRange, (result) ->
      if result.range.start.column == 0
        foundEnd = result.range
        result.stop()

    if not foundEnd?
      console.error "Couldn't find the end of the function."
      return null

    # check if cursor is contained in range
    currentPosition.row -= 1
    if foundStart.start.row <= currentPosition.row and
        currentPosition.row <= foundEnd.start.row
      return new Range(foundStart.start, foundEnd.end)
    else
      console.error "Couldn't find a function surrounding the current line."
      console.error "start: ", foundStart
      console.error "end: ", foundEnd
      console.error "currentPosition: ", currentPosition
      return null

  sendFunction: ->
    [editor, buffer] = @_getEditorAndBuffer()
    whichApp = atom.config.get 'stata-exec.whichApp'

    range = @getFunctionRange()
    if range?
      code = editor.getTextInBufferRange(range)
      code = code.addSlashes()
      @sendCode(code, whichApp)
    else
      @conditionalWarning("Couldn't find function.")

  getSelection: (whichApp) ->
    # returns an object with keys:
    # selection: the selection or line at which the cursor is present
    # anySelection: if true, the user made a selection.
    [editor, buffer] = @_getEditorAndBuffer()

    selection = editor.getLastSelection()
    anySelection = true

    if selection.getText().addSlashes() == ""
      anySelection = false
      # editor.selectLinesContainingCursors()
      # selection = editor.getLastSelection()
      currentPosition = editor.getCursorBufferPosition().row
      selection = editor.lineTextForBufferRow(currentPosition)
    else
      selection = selection.getText()
    selection = selection.addSlashes()

    {selection: selection, anySelection: anySelection}

  conditionalWarning: (message) ->
    notifications = atom.config.get 'stata-exec.notifications'
    if notifications
      atom.notifications.addWarning(message)

  onlyWhitespace: (str) ->
    # returns true if string is only whitespace
    return str.replace(/\s/g, '').length is 0

  getCurrentParagraphRange: ->
    [editor, buffer] = @_getEditorAndBuffer()
    currentPosition = editor.getCursorBufferPosition().row

    currentLine = buffer.lineForRow(currentPosition)

    if @onlyWhitespace(currentLine)
      return null

    startIndex = -1
    # if we exhaust loop, then this paragraph begins at the first line
    if currentPosition > 0
      for lineIndex in [(currentPosition - 1)..0]
        currentLine = buffer.lineForRow(lineIndex)
        if @onlyWhitespace(currentLine)
          startIndex = lineIndex
          break
    startIndex += 1

    endIndex = editor.getLineCount()
    numberOfLines = editor.getLineCount() - 1
    if currentPosition < endIndex - 1
      for lineIndex in [(currentPosition + 1)..numberOfLines]
        currentLine = buffer.lineForRow(lineIndex)
        if @onlyWhitespace(currentLine)
          endIndex = lineIndex
          break
    endIndex -= 1

    paragraphRange = new Range([startIndex, 0],
      [endIndex, buffer.lineLengthForRow(endIndex)])

    return paragraphRange

  sendParagraph: ->
    whichApp = atom.config.get 'stata-exec.whichApp'
    [editor, buffer] = @_getEditorAndBuffer()
    paragraphRange = @getCurrentParagraphRange()

    if paragraphRange
      code = editor.getTextInBufferRange(paragraphRange)
      code = code.addSlashes()
      @sendCode(code, whichApp)
      advancePosition = atom.config.get 'stata-exec.advancePosition'
      if advancePosition
        currentPosition = editor.getLastSelection().getScreenRange().end
        nextPosition = @_findForward(@nonEmptyLine, paragraphRange.end.row + 1)
        if nextPosition?
          nextPosition ?= [currentPosition + 1, 0]
          editor.setCursorScreenPosition(nextPosition)
          editor.moveToFirstCharacterOfLine()
    else
      console.error 'No paragraph at cursor.'
      @conditionalWarning("No paragraph at cursor.")

  isWhitespaceLine: (line) ->
    return line.replace(/\s/g, '').length is 0

  nonEmptyLine: (line) ->
    skipComments = atom.config.get 'stata-exec.skipComments'
    ret = true
    if skipComments
      ret = not /^\s*#/.test(line)
    # a non empty line is a line that doesn't contain only a comment
    # and at least 1 character
    return ret and /\S/.test(line)

  _findBackward: (searchFun, startPosition = null) ->
    [editor, buffer] = @_getEditorAndBuffer()

    if not startPosition?
      startPosition = editor.getCursorBufferPosition().row

    index = null
    for lineIndex in [startPosition..0]
      currentLine = buffer.lineForRow(lineIndex)
      if searchFun(currentLine)
        index = lineIndex
        break

    position = null
    if index?
      position = [index, 0]

    return position

  _findForward: (searchFun, startPosition = null) ->
    editor = atom.workspace.getActiveTextEditor()
    buffer = editor.getBuffer()

    if not startPosition?
      startPosition = editor.getCursorBufferPosition().row

    index = null
    numberOfLines = editor.getLineCount() - 1
    if startPosition >= numberOfLines
      return null
    for lineIndex in [startPosition..numberOfLines]
      currentLine = buffer.lineForRow(lineIndex)
      if searchFun(currentLine)
        index = lineIndex
        break

    if index?
      return [index, buffer.lineLengthForRow(index)]

    return null

  getGeneralRange: (startFun, endFun) ->
    # returns a Range with the beginning being the first line of the
    # knitr block and the end of the knitr block.
    startPosition = @_findBackward(startFun)
    endPosition = null
    if startPosition?
      endPosition = @_findForward(endFun, startPosition[0] + 1)
    if startPosition? and endPosition?
      return new Range(startPosition, endPosition)

    return null

  rMarkdownStart: (line) ->
    return /^\s*([`]{3})\s*([\{]{0,1})([rR])([^\}]*)([\}]{0,1})\s*$/.test(line)

  rMarkdownEnd: (line) ->
    return /^\s*([`]{3})\s*$/.test(line)

  sendKnitr: ->
    [editor, buffer] = @_getEditorAndBuffer()
    codeRange = null
    fileName = editor.getPath()
    extension = fileName.split('.').pop()

    if /rmd/i.test(extension)
      codeRange = @getGeneralRange(@rMarkdownStart, @rMarkdownEnd)
    else if /rnw/i.test(extension)
      @conditionalWarning("Rnw not implemented yet")
      return
    else
      @conditionalWarning("File not recognized as knitr.")
      return

    whichApp = atom.config.get 'stata-exec.whichApp'
    currentPosition = editor.getCursorBufferPosition().row

    if not codeRange?
      msg = "Couldn't find the beginning or end of a knitr block."
      atom.notifications.addError(msg)
      console.error msg
      return

    # ensure that current line is contained in codeRange
    if not(codeRange.start.row <= currentPosition and
    currentPosition <= codeRange.end.row)
      msg = "Couldn't find a knitr block at the current position."
      atom.notifications.addError(msg)
      console.error msg
      return

    codeRange.start.row += 1
    codeRange.end.row -= 1
    codeRange.end.column = buffer.lineLengthForRow(codeRange.end.row)

    if (codeRange.end.row - codeRange.start.row) < 0
      msg = "Empty knitr block."
      atom.notifications.addError(msg)
      console.error msg
      return

    code = editor.getTextInBufferRange(codeRange)
    code = code.addSlashes()
    @sendCode(code, whichApp)

    advancePosition = atom.config.get 'stata-exec.advancePosition'
    if advancePosition
      nextBlockStart = @_findForward(@rMarkdownStart, codeRange.end.row + 1)
      if not nextBlockStart?
        nextBlockStart = [editor.getLineCount() - 1, 0]
      editor.setCursorScreenPosition(nextBlockStart)
      editor.moveToFirstCharacterOfLine()

    return null

  setWorkingDirectory: ->
    # set the current working directory to the directory of
    # where the current file is
    [editor, buffer] = @_getEditorAndBuffer()
    whichApp = atom.config.get 'stata-exec.whichApp'
    # TODO: add warning if connected to server

    cwd = editor.getPath()
    if not cwd
      console.error 'No current working directory (save the file first).'
      @conditionalWarning('No current working directory (save the file first).')
      return
    cwd = cwd.substring(0, cwd.lastIndexOf('/'))
    cwd = "setwd(\"" + cwd + "\")"

    @sendCode(cwd.addSlashes(), whichApp)

  stata: (selection) ->
    # This assumes the active pane item is an console
    osascript = require 'node-osascript'
    command = []
    focusWindow = atom.config.get 'stata-exec.focusWindow'
    if focusWindow
      command.push 'tell application "StataMP" to activate'
    command.push 'tell application "StataMP"'
    command.push '  tell the current terminal'
    # if focusWindow
    #   command.push '    activate current session'
    command.push '    tell the last session'
    command.push '      write text code'
    command.push '    end tell'
    command.push '  end tell'
    command.push 'end tell'
    command = command.join('\n')
    osascript.execute command, {code: selection}, (error, result, raw) ->
      if error
        console.error(error)

  getWhichApp: ->
    return atom.config.get 'stata-exec.whichApp'

  _getSurroundingCharacters: ->
    [editor, buffer] = @_getEditorAndBuffer()
    # get the character to the left and to the right.
    # if there is whitespace to the left do not insert whitespace
    currentPosition = editor.getCursorBufferPosition()
    leftPosition = Point(currentPosition.row, currentPosition.column - 1)
    rightPosition = Point(currentPosition.row, currentPosition.column + 1)

    return [
      editor.getTextInBufferRange(Range(leftPosition, currentPosition)),
      editor.getTextInBufferRange(Range(currentPosition, rightPosition))
    ]

  # behavior:
  # if there is a whitespace to the left or right, do not insert additional whitespace.
  # otherwise, insert whitespace.
  # XXX: behavior is a bit weird when text is selected.
  # unfortunately, it is unclear how to deal with selections because Atom does not report if there is currently a selection, but only the last selection.
  _smartInsert: (text) ->
    beSmart = atom.config.get 'stata-exec.smartInsertOperator'

    [editor, buffer] = @_getEditorAndBuffer()
    # get the character to the left and to the right.
    # if there is whitespace to the left do not insert whitespace
    [left, right] = @_getSurroundingCharacters()
    textInsert = text

    if !beSmart or left != ' '
      textInsert = ' ' + textInsert

    if !beSmart or right != ' '
      textInsert = textInsert + ' '

    editor.insertText(textInsert)
