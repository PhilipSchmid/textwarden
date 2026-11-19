# TextWarden for Obsidian on macOS

TextWarden checks editable Markdown notes in Obsidian (`md.obsidian`). Click in the note body in Live Preview or Source mode to see suggestions. Reading view, note titles, search, and the command palette are outside the integration.

Obsidian’s CodeMirror editor provides macOS with the portion of the note it has rendered. Scroll to another section to bring it into the editor’s accessibility tree. In Live Preview, the text Obsidian exposes can change as it renders or reveals Markdown syntax.

TextWarden positions underlines using the editor’s child text runs. When a suggestion spans text that macOS cannot locate precisely, it remains available in the floating indicator. Corrections use a verified selection in the note editor and a paste operation so Obsidian handles the edit and undo.
