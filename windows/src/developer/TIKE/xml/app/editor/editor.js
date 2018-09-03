/*
 * Editor using monaco
 * 
 * Helpful references:
 * https://microsoft.github.io/monaco-editor/api/index.html
 * https://blog.expo.io/building-a-code-editor-with-monaco-f84b3a06deaf 
 */

window.editorGlobalContext = {
  loading: false
};

(function(context) {
  var editor = null;
  var errorRange = null;
  var executionPoint = [];
  var breakpoints = [];
  let params = (new URL(location)).searchParams;
  let filename = params.get('filename');
  let mode = params.get('mode');
  
  if(!mode) {
    mode = 'keyman';
  }


  /**
    Initialize the editor
  */

  require.config({ paths: { 'vs': '../lib/monaco/min/vs' } });
  require(['vs/editor/editor.main','language.keyman'], function (_editor, _language) {
    
    // Register Keyman .kmn tokens provider and language formatter
    // https://github.com/Microsoft/monaco-editor/blob/master/test/playground.generated/extending-language-services-custom-languages.html
    monaco.languages.register({ id: 'keyman' });
    monaco.languages.setMonarchTokensProvider('keyman', _language.language);
    
    //
    // Create editor and load source file
    //

    editor = monaco.editor.create(document.getElementById('editor'), {
      language: mode,
      minimap: {
        enabled: false
      },
      glyphMargin: true,
      disableMonospaceOptimizations: true
    });

    $.get("/app/source/file",
      {
        Filename: filename
      },
      function (response) {
        context.loading = true;
        editor.setValue(response);
        context.loading = false;
      },
      "text"
    );
    
    //
    // Setup callbacks
    //

    const model = editor.getModel();
    model.onDidChangeContent(() => {
      // Even when loading, we post back the data to the backend so we have an original version
      $.post("/app/source/file", {
        Filename: filename,
        Data: model.getValue()
        // delta.start, delta.end, delta.lines, delta.action
      });
      if (!context.loading) {
        context.highlightError(); // clear the selected error
        command('modified');
        updateState();
      }
    });

    editor.onDidChangeCursorPosition(updateState);
    editor.onDidChangeCursorSelection(updateState);
    editor.onMouseDown(e => {
      if (e.target.type !== monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN) {
        return;
      }
      command('breakpoint-clicked,'+(e.target.position.lineNumber-1));
    });
  });

  //
  // Search and replace interfaces 
  //
  
  context.searchFind = function () {
    editor.trigger('', 'actions.find');
  };

  context.searchFindNext = function() {  
    editor.trigger('', 'editor.action.nextMatchFindAction');
  };

  context.searchReplace = function() {  
    editor.trigger('', 'editor.action.startFindReplaceAction');
  };
  
  //
  // Edit command interfaces
  //

  context.editUndo = function() {
    editor.model.undo();
  };

  context.editRedo = function() {
    editor.model.redo();
  };
  
  context.editSelectAll = function() {
    editor.setSelection(editor.model.getFullModelRange());
  };

  //
  // Row selection
  //

  context.moveCursor = function (o) {
    editor.setPosition({ column: o.column + 1, lineNumber: o.row + 1 });
    editor.revealPositionInCenterIfOutsideViewport(editor.getPosition(), monaco.editor.ScrollType.Smooth);
  };
  
  //
  // Debug interactions
  //
  
  context.setBreakpoint = function (row) {
    if (!breakpoints[row]) {
      breakpoints[row] = editor.deltaDecorations(
        [],
        [{ range: new monaco.Range(row + 1, 1, row + 1, 1), options: { isWholeLine: true, glyphMarginClassName: 'km_breakpoint' } }]
      );
    }
  };
  
  context.clearBreakpoint = function (row) {
    if (breakpoints[row]) {
      editor.deltaDecorations(breakpoints[row], []);
      breakpoints[row] = null;
    }
  };

  context.updateExecutionPoint = function (row) {
    executionPoint = editor.deltaDecorations(
      executionPoint,
      row >= 0 ? [{ range: new monaco.Range(row + 1, 1, row + 1, 1), options: { isWholeLine: true, linesDecorationsClassName: 'km_executionPoint' } }] : []
    );
    context.moveCursor({ row: row, column: 0 });
  };

  //
  // Error highlighting
  //

  context.highlightError = function (row) {
    if (errorRange) {
      editor.deltaDecorations(errorRange, []);
      errorRange = null;
    }
    if (typeof row == 'number') {
      errorRange = editor.deltaDecorations([], [{ range: new monaco.Range(row + 1, 1, row + 1, 1), options: { isWholeLine: true, linesDecorationsClassName: 'km_error', className: 'km_error' } }]);
    }
  };

  context.replaceSelection = function (o) {
    let r = new monaco.Range(o.top + 1, o.left + 1, o.bottom + 1, o.right + 1);
    editor.setSelection(r);
    editor.executeEdits("", [
      { range: r, text: o.newText }
    ]);
  };
  
  context.setText = function (text) {
    let range = editor.getSelection();
    context.loading = true;
    editor.setValue(text);
    editor.setSelection(range);
    context.loading = false;
  };

  //
  // Printing
  //

  context.print = function () {
    /****require("ace/config").loadModule("ace/ext/static_highlight", function (m) {
      var result = m.renderSync(
        editor.getValue(), editor.session.getMode(), editor.renderer.theme
      );
      var iframe = document.createElement('iframe');
      iframe.onload = function () {
        iframe.contentWindow.document.open();
        iframe.contentWindow.document.write(result.html);
        iframe.contentWindow.document.close();
        var s = iframe.contentWindow.document.createElement('style');
        s.type = 'text/css';
        s.appendChild(iframe.contentWindow.document.createTextNode(result.css));
        iframe.contentWindow.document.head.appendChild(s);
        // TODO: Add page setup -- paper size, margins
        window.setTimeout(function () {
          iframe.contentWindow.print();
          document.body.removeChild(iframe);
        }, 10);
      };
      document.body.appendChild(iframe);
    });*/
  };
      
  /**
    Notifies the host application of an event or command from the
    text editor. Commands are cached until idle to allow for batches
    of commands to be sent together.
    
    Copy of this is in builder.js (ready for refactor!)
  */
  var commands = [];

  var command = function (cmd) {
    if (navigator.userAgent.indexOf('TIKE') < 0) {
      // Don't execute command if not in the correct host application (allows for browser-based testing)
      return false;
    }
    // queue commands to build a single portmanteau command when we return to idle
    if (commands.length == 0) {
      window.setTimeout(function() {
        try {
          location.href = 'keyman:command?' + commands.reduce(function(a,v) { return a + '&' + v; });
          commands = [];
        } catch (e) {
          // ignore errors - saves weirdness happening when testing outside TIKE.exe
        }
      }, 10);
    }
    commands.push(cmd);
  };
  
  //
  // Updates the state of the host application 
  //
  
  var updateState = function () {
    let s = editor.getSelection();
    command(s.isEmpty() ? 'no-selection' : 'has-selection');
    command(editor.model.canUndo() ? 'undo-enable' : 'undo-disable');
    command(editor.model.canRedo() ? 'redo-enable' : 'redo-disable');

    var n = editor.model.getValueInRange(s).length;
    if (editor.getSelection().getDirection() == monaco.SelectionDirection.LTR) n = -n;
    command('location,' + (s.startLineNumber-1) + ',' + (s.startColumn-1) + ',' + (s.endLineNumber-1) + ',' + (s.endColumn-1) + ',' + n);
    var token = getTokenAtCursor();
    if (token) {
      command('token,' + token.column + ',' + encodeURIComponent(token.text));
    }
  };

  var getTokenAtCursor = function () {
    var txt = editor.model.getValueInRange(editor.getSelection());
    if (txt != '') {
      // We'll always return the first 100 characters of the selection and not 
      // do any manipulation here.
      return { column: null, text: txt.substr(0, 99) };
    }

    if (mode == 'keyman') {
      // Get the token under the cursor
      var c = editor.getSelection();
      try {
        var line = editor.model.getLineContent(c.positionLineNumber);
      } catch(e) {
        // In some situations, e.g. deleting a selection at the end of the document,
        // the selected line may be past the end of the document for a moment
        return null;
      }
      return { column: c.positionColumn-1, text: line };
    } else {
      // Get the character under the cursor
      return null;
    }
  };
})(window.editorGlobalContext);