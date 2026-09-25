# Runtime Accessibility ID Queries

All queries used `flowdeck ui simulator find <id> -S 3C2EE419-CC61-4F7A-A89D-9CFC7045B612 --by-id --json` against the live Noto 2 UI.

| ID | Runtime result | Observed state |
| --- | --- | --- |
| `browse_more_actions_menu` | `not_found` | Queried while the trailing ellipsis control was visibly present in `Projects`, then repeated in `Projects/Audit Child` after restarting the FlowDeck UI session. |
| `browse_new_note_action` | `id_exact`, enabled button, label `New Note` | More-actions dialog open in `Projects`, then rechecked in `Projects/Audit Child`. |
| `browse_new_folder_action` | `id_exact`, enabled button, label `New Folder` | More-actions dialog open in `Projects`. |
| `browse_new_folder_name_field` | `id_exact`, enabled text field | New Folder sheet open. |
| `browse_create_folder_button` | `id_exact`, button, label `Create` | New Folder sheet open in empty, whitespace-only, and valid-name states. |
| `browse_cancel_folder_button` | `id_exact`, enabled button, label `Cancel` | New Folder sheet open. |

Supporting trees: `02-projects-directory-tree.json`, `03-more-menu-tree.json`, `04-folder-sheet-empty-tree.json`, and `08-child-directory-tree.json`.
